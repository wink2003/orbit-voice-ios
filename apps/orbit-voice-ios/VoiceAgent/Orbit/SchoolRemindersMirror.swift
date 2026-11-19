import EventKit
import Foundation
import SwiftUI

// EventKit + API side of the School ↔ iCloud Reminders mirror (decisions live in SchoolRemindersMirrorLogic.swift).
// Runs ON THE DEVICE: reminder lists upgraded to the iOS 13+ format are not reachable through CalDAV, only through EventKit.
// It syncs when the app comes to the foreground and when the user taps «Синхронізувати зараз». Nothing runs unless the user switched it on.

extension Notification.Name {
    /// Posted after a successful create/update/complete/reopen of a School action task (see MainProductAPI.request).
    static let orbitSchoolTasksChanged = Notification.Name("orbit.school.tasks.changed")
}

@MainActor
final class SchoolRemindersMirror: ObservableObject {
    static let shared = SchoolRemindersMirror()
    static let listTitle = "Школа"

    enum Phase: Equatable { case off, idle, syncing, denied, failed(String) }

    @Published private(set) var phase: Phase = .off
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var lastSummary: String = ""

    private let store = EKEventStore()
    private let enabledKey = "orbit.school.remindersMirror.enabled"
    private let stateKey = "orbit.school.remindersMirror.state"
    private var running = false

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    private var pendingSync: Task<Void, Never>?
    private var observer: NSObjectProtocol?

    init() {
        phase = UserDefaults.standard.bool(forKey: "orbit.school.remindersMirror.enabled") ? .idle : .off
        // A change made in the app (new task, edit, complete/reopen) syncs right away, debounced so a burst of edits is one run.
        observer = NotificationCenter.default.addObserver(forName: .orbitSchoolTasksChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.tasksChanged() }
        }
    }

    /// Ignored while a run is in progress (the run's own API calls post the same notification); a trailing run is harmless: nothing is left to change.
    private func tasksChanged() {
        guard isEnabled, !running else { return }
        pendingSync?.cancel()
        pendingSync = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await self?.sync()
        }
    }

    // MARK: settings
    func setEnabled(_ on: Bool) async {
        if !on {
            UserDefaults.standard.set(false, forKey: enabledKey)
            phase = .off
            return
        }
        do {
            let granted = try await store.requestFullAccessToReminders()
            guard granted else { UserDefaults.standard.set(false, forKey: enabledKey); phase = .denied; return }
            UserDefaults.standard.set(true, forKey: enabledKey)
            phase = .idle
            await sync()
        } catch {
            UserDefaults.standard.set(false, forKey: enabledKey)
            phase = .failed("Немає доступу до Нагадувань")
        }
    }

    // MARK: sync
    func syncIfEnabled() async { if isEnabled { await sync() } }

    func sync() async {
        guard isEnabled, !running else { return }
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { phase = .denied; return }
        running = true; phase = .syncing
        defer { running = false }
        do {
            let summary = try await runOnce()
            lastSyncAt = Date(); lastSummary = summary; phase = .idle
        } catch {
            phase = .failed(String(describing: error).prefix(120).description)
        }
    }

    // MARK: one run
    private func runOnce() async throws -> String {
        let api = MainProductAPI.shared
        let calendar = try reminderList()
        async let actionTasks = api.schoolActionTasks()
        async let letterTasks = api.schoolTasks(coverage: "all")                // the Hub loads the full list, not just the current window
        let actionResponse = try await actionTasks
        let letterResponse = try await letterTasks
        let states = actionResponse.tasks

        // Assembled exactly like SchoolHubStore.hubTasks so the reminders list equals what the School tab shows:
        // a letter task takes its status and planned date from the action row matched by (source item, task key).
        var orbit: [MirrorOrbitTask] = []
        var sourceRefs: [String: (itemId: String, taskKey: String)] = [:]
        var revisions: [String: Int] = [:]
        var familyIds = Set<String>()
        for task in letterResponse.tasks {
            let state = states.first { $0.kind == "source" && $0.sourceItemId == task.sourceItemId && $0.sourceTaskKey == task.key }
            let effective = SchoolHubLogic.effectiveDue(dueAt: task.dueAt, allDay: task.allDay, planningDate: state?.planningDate)
            let hub = SchoolHubTask(
                id: task.id, title: task.title, action: task.action, dueAt: effective.dueAt, allDay: effective.allDay, importance: task.importance,
                target: task.target, confidence: task.confidence, reason: task.reason, sourceItemId: task.sourceItemId, sourceType: task.sourceType,
                sourceExternalId: task.sourceExternalId, actionID: state?.id, status: state?.status ?? task.status ?? "open", planningDate: state?.planningDate,
                effectiveDueAt: state?.planningDate == nil ? task.effectiveDueAt : nil, effectiveDueDateOrigin: state?.planningDate == nil ? task.effectiveDueDateOrigin : nil)
            let key = "src:\(task.sourceItemId):\(task.key)"
            sourceRefs[key] = (task.sourceItemId, task.key)
            let due = SchoolHubLogic.effectiveTaskDay(hub, sourceDates: [:]).map { String($0.prefix(10)) }
            orbit.append(MirrorOrbitTask(key: key, snapshot: MirrorSnapshot(title: task.title, notes: task.action ?? "", due: due, done: SchoolHubLogic.isCompleted(hub)), canEditText: false, canEditDue: false))
        }
        for task in states where task.kind == "family" {
            familyIds.insert(task.id); revisions[task.id] = task.revision
            let due = SchoolHubLogic.planningDayKey(task.planningDate) ?? task.schoolDueAt.flatMap { SchoolHubLogic.dayKey(for: $0, allDay: false) }
            orbit.append(MirrorOrbitTask(key: task.id, snapshot: MirrorSnapshot(title: task.title, notes: task.description, due: due, done: task.status == "completed"), canEditText: true, canEditDue: true))
        }

        var state = loadState()
        var reminders = try await fetchReminders(in: calendar)
        if state.version < MirrorState.currentVersion {
            // First release keyed and assembled tasks differently: drop only the reminders IT created (mirror-owned) and start clean.
            let legacy = Set(state.links.map(\.reminderId))
            for reminder in reminders where legacy.contains(reminder.calendarItemIdentifier) { try? store.remove(reminder, commit: false) }
            reminders.removeAll { legacy.contains($0.calendarItemIdentifier) }
            state = MirrorState(version: MirrorState.currentVersion)
        }
        let mirrorReminders = reminders.map { MirrorReminder(id: $0.calendarItemIdentifier, snapshot: snapshot(of: $0), hasTime: $0.dueDateComponents?.hour != nil) }
        let byId = Dictionary(reminders.map { ($0.calendarItemIdentifier, $0) }, uniquingKeysWith: { a, _ in a })
        let orbitByKey = Dictionary(orbit.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let actionsPlan = SchoolRemindersMirrorLogic.plan(orbit: orbit, reminders: mirrorReminders, state: state)

        var counts = (toReminders: 0, toOrbit: 0)
        var failures = 0
        for action in actionsPlan {
            do {
                switch action {
                case let .createReminder(key, snap):
                    let reminder = EKReminder(eventStore: store)
                    reminder.calendar = calendar
                    apply(snap, to: reminder, keepTime: false)
                    try store.save(reminder, commit: false)
                    state.links.append(MirrorLink(key: key, reminderId: reminder.calendarItemIdentifier, base: snap))
                    counts.toReminders += 1
                case let .updateReminder(key, reminderId, snap):
                    guard let reminder = byId[reminderId] else { continue }
                    apply(snap, to: reminder, keepTime: true)
                    try store.save(reminder, commit: false)
                    if let idx = state.links.firstIndex(where: { $0.key == key }) { state.links[idx].base = snap }
                    counts.toReminders += 1
                case let .createOrbitTask(reminderId, snap):
                    let created = try await api.createSchoolActionTask(title: snap.title, description: snap.notes, planningDate: snap.due, clientRequestId: "reminder-\(reminderId)")
                    state.links.append(MirrorLink(key: created.id, reminderId: reminderId, base: MirrorSnapshot(title: created.title, notes: created.description, due: created.planningDate ?? snap.due, done: false)))
                    counts.toOrbit += 1
                case let .updateOrbitTask(key, title, notes, due, dueChanged):
                    guard familyIds.contains(key) else { continue }
                    _ = try await api.updateSchoolActionTask(id: key, title: title, description: notes, planningDate: dueChanged ? due : nil, revision: revisions[key])
                    if let idx = state.links.firstIndex(where: { $0.key == key }), let o = orbitByKey[key] {
                        var base = state.links[idx].base
                        base.title = title ?? o.snapshot.title; base.notes = notes ?? o.snapshot.notes; base.due = dueChanged ? due : o.snapshot.due
                        state.links[idx].base = base
                    }
                    counts.toOrbit += 1
                case let .setOrbitDone(key, done):
                    if let ref = sourceRefs[key] {
                        if done { _ = try await api.completeSourceSchoolTask(itemId: ref.itemId, taskKey: ref.taskKey) }
                        else { _ = try await api.reopenSourceSchoolTask(itemId: ref.itemId, taskKey: ref.taskKey) }
                    } else if familyIds.contains(key) {
                        if done { _ = try await api.completeSchoolActionTask(id: key) } else { _ = try await api.reopenSchoolActionTask(id: key) }
                    } else { continue }
                    if let idx = state.links.firstIndex(where: { $0.key == key }) { state.links[idx].base.done = done }
                    counts.toOrbit += 1
                case let .detach(key):
                    state.links.removeAll { $0.key == key }
                    if !state.detached.contains(key) { state.detached.append(key) }
                }
            } catch { failures += 1 }                                           // one failed item must not stop the rest; it is retried next run
        }
        try store.commit()
        saveState(state)
        let tail = failures > 0 ? " · помилок: \(failures)" : ""
        return "У Нагадування: \(counts.toReminders) · у Orbit: \(counts.toOrbit)\(tail)"
    }

    // MARK: EventKit helpers
    private func reminderList() throws -> EKCalendar {
        if let found = store.calendars(for: .reminder).first(where: { $0.title == Self.listTitle && $0.allowsContentModifications }) { return found }
        guard let source = store.defaultCalendarForNewReminders()?.source ?? store.sources.first(where: { $0.sourceType == .calDAV }) else { throw MirrorError.noSource }
        let list = EKCalendar(for: .reminder, eventStore: store)
        list.title = Self.listTitle
        list.source = source
        try store.saveCalendar(list, commit: true)
        return list
    }

    private func fetchReminders(in calendar: EKCalendar) async throws -> [EKReminder] {
        let predicate = store.predicateForReminders(in: [calendar])
        let box: ReminderBox = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { continuation.resume(returning: ReminderBox(items: $0 ?? [])) }
        }
        return box.items
    }

    private func snapshot(of reminder: EKReminder) -> MirrorSnapshot {
        MirrorSnapshot(title: reminder.title ?? "", notes: reminder.notes ?? "", due: reminder.dueDateComponents.flatMap(Self.dayString), done: reminder.isCompleted)
    }

    private func apply(_ snap: MirrorSnapshot, to reminder: EKReminder, keepTime: Bool) {
        if reminder.title != snap.title { reminder.title = snap.title }
        if (reminder.notes ?? "") != snap.notes { reminder.notes = snap.notes.isEmpty ? nil : snap.notes }
        if reminder.isCompleted != snap.done { reminder.isCompleted = snap.done }
        let current = reminder.dueDateComponents.flatMap(Self.dayString)
        if current != snap.due {                                                // a time of day is kept when the day is unchanged
            if let day = snap.due, let parts = Self.dayComponents(day) { reminder.dueDateComponents = parts } else { reminder.dueDateComponents = nil }
        } else if !keepTime, let day = snap.due, let parts = Self.dayComponents(day) { reminder.dueDateComponents = parts }
    }

    // MARK: day strings (calendar day in the reminder's own calendar, no time-zone conversion)
    static func dayString(_ c: DateComponents) -> String? {
        guard let y = c.year, let m = c.month, let d = c.day else { return nil }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }
    static func dayComponents(_ day: String) -> DateComponents? {
        let p = day.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard p.count == 3 else { return nil }
        return DateComponents(calendar: Calendar(identifier: .gregorian), year: p[0], month: p[1], day: p[2])
    }

    // MARK: persistence
    private func loadState() -> MirrorState {
        guard let data = UserDefaults.standard.data(forKey: stateKey), let state = try? JSONDecoder().decode(MirrorState.self, from: data) else { return MirrorState() }
        return state
    }
    private func saveState(_ state: MirrorState) {
        if let data = try? JSONEncoder().encode(state) { UserDefaults.standard.set(data, forKey: stateKey) }
    }

    enum MirrorError: Error { case noSource }
    private struct ReminderBox: @unchecked Sendable { let items: [EKReminder] }
}

/// «Школа ↔ Нагадування» block for the settings screen.
struct SchoolRemindersMirrorSettingsRow: View {
    @ObservedObject private var mirror = SchoolRemindersMirror.shared
    @State private var on = SchoolRemindersMirror.shared.isEnabled

    var body: some View {
        Section {
            Toggle("Дзеркало у «Нагадуваннях»", isOn: Binding(get: { on }, set: { value in
                on = value
                Task { await mirror.setEnabled(value); on = mirror.isEnabled }
            }))
            if on {
                Button("Синхронізувати зараз") { Task { await mirror.sync() } }.disabled(mirror.phase == .syncing)
                if let last = mirror.lastSyncAt { Text("Остання синхронізація: \(last.formatted(date: .omitted, time: .shortened)). \(mirror.lastSummary)").font(.footnote).foregroundStyle(.secondary) }
            }
            switch mirror.phase {
            case .denied: Text("Доступ до Нагадувань вимкнено. Увімкніть його в Налаштуваннях iPhone → Orbit → Нагадування.").font(.footnote).foregroundStyle(.orange)
            case let .failed(text): Text("Не вдалося синхронізувати: \(text)").font(.footnote).foregroundStyle(.orange)
            default: EmptyView()
            }
        } header: { Text("Нагадування iCloud") } footer: {
            Text("Справи зі «Школи» дзеркаляться в список «\(SchoolRemindersMirror.listTitle)»: виконання, назва, нотатки й день працюють в обидва боки. Видалення нагадування лише відʼєднує справу, у Orbit вона лишається.")
        }
    }
}
