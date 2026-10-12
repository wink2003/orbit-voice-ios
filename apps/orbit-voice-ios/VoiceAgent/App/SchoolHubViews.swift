import SwiftUI

// MARK: - Store

@MainActor @Observable
final class SchoolHubStore {
    enum Phase: Equatable { case idle, loading, loaded, failed }

    var itemsPhase: Phase = .idle
    var calendarPhase: Phase = .idle
    var items: [OrbitSchoolItem] = []
    var events: [OrbitSchulmanagerCalendarEvent] = []
    var canonicalTasks: [OrbitSchoolTask] = []
    var studentNames: [String] = []
    var itemsLoadedOnce = false
    var calendarLoadedOnce = false
    var tasksLoadedOnce = false
    var tasksPhase: Phase = .idle
    var actionTasksPhase: Phase = .idle
    var actionTasks: [OrbitSchoolActionTask] = []
    private(set) var gate = SchoolHubLoadGate()
    var scopeKey: String? { gate.scopeKey }

    func reset(to key: String) {
        gate.reset(to: key)
        items = []; events = []; canonicalTasks = []; actionTasks = []; studentNames = []
        itemsLoadedOnce = false; calendarLoadedOnce = false; tasksLoadedOnce = false
        itemsPhase = .idle; calendarPhase = .idle; tasksPhase = .idle; actionTasksPhase = .idle
    }

    var letters: [SchoolHubLetter] {
        items.map { item in
            SchoolHubLetter(
                id: item.id, type: item.type,
                title: item.titlePlainText?.isEmpty == false ? item.titlePlainText! : item.title,
                sender: item.sender,
                originalText: item.originalPlainText ?? item.originalGerman,
                translation: item.translationUkrainian, important: item.important,
                unread: item.unread, date: item.sourceTimestamp ?? item.importedAt
            )
        }
    }

    var hubEvents: [SchoolHubEvent] {
        events.map { SchoolHubEvent(uid: $0.uid, title: $0.title, description: $0.description, location: $0.location, startsAt: $0.startsAt, endsAt: $0.endsAt, allDay: $0.allDay, relevanceClass: $0.relevanceClass, audienceClass: $0.audienceClass, relevanceReason: $0.relevanceReason) }
    }

    var hubTasks: [SchoolHubTask] {
        let sourceTasks: [SchoolHubTask]
        if tasksLoadedOnce {
            sourceTasks = canonicalTasks.map { task in
                let state = actionTasks.first { $0.kind == "source" && $0.sourceItemId == task.sourceItemId && $0.sourceTaskKey == task.key }
                SchoolHubTask(
                    id: task.id,
                    title: task.title,
                    action: task.action,
                    dueAt: task.dueAt,
                    allDay: task.allDay,
                    importance: task.importance,
                    target: task.target,
                    confidence: task.confidence,
                    reason: task.reason,
                    sourceItemId: task.sourceItemId,
                    actionID: state?.id,
                    status: state?.status ?? "open",
                    planningDate: state?.planningDate
                )
            }
        } else {
            sourceTasks = items.flatMap { item in
                (item.tasks ?? []).enumerated().compactMap { index, task -> SchoolHubTask? in
                    guard let title = (task.title ?? task.action), !title.isEmpty else { return nil }
                    return SchoolHubTask(id: "\(item.id):\(task.key ?? String(index))", title: title, action: task.action, dueAt: task.dueAt, allDay: task.allDay ?? true, importance: task.importance, target: task.target, confidence: task.confidence, reason: task.reason, sourceItemId: item.id)
                }
            }
        }
        let familyTasks = actionTasks.filter { $0.kind == "family" }.map { task in
            SchoolHubTask(id: "family:\(task.id)", title: task.title, action: task.description.isEmpty ? nil : task.description, dueAt: task.schoolDueAt ?? task.planningDate, allDay: task.schoolDueAt == nil, importance: nil, target: nil, confidence: 1, reason: "Створено родиною в Orbit", sourceItemId: task.sourceItemId ?? "", kind: "family", actionID: task.id, status: task.status, planningDate: task.planningDate)
        }
        return sourceTasks + familyTasks
    }

    var openHubTasks: [SchoolHubTask] { hubTasks.filter { $0.status != "completed" } }

    var sourceDates: [String: Date] {
        Dictionary(items.compactMap { item in (item.sourceTimestamp ?? item.importedAt).map { (item.id, $0) } }, uniquingKeysWith: { first, _ in first })
    }

    func item(id: String) -> OrbitSchoolItem? { items.first { $0.id == id } }
    func calendarEvent(uid: String) -> OrbitSchulmanagerCalendarEvent? { events.first { $0.uid == uid } }

    func load() async {
        guard let token = gate.token() else { return }
        itemsPhase = .loading
        calendarPhase = .loading
        tasksPhase = .loading
        async let itemsResult: Void = loadItems(token)
        async let calendarResult: Void = loadCalendar(token)
        async let tasksResult: Void = loadTasks(token)
        async let actionTasksResult: Void = loadActionTasks(token)
        async let namesResult: Void = loadNames(token)
        _ = await (itemsResult, calendarResult, tasksResult, actionTasksResult, namesResult)
    }

    private func loadItems(_ token: Int) async {
        do {
            let result = try await MainProductAPI.shared.schoolItems(filter: "all").items
            guard gate.accepts(token) else { return }
            items = result
            itemsLoadedOnce = true
            itemsPhase = .loaded
        } catch is CancellationError {
            guard gate.accepts(token) else { return }
            itemsPhase = itemsLoadedOnce ? .loaded : .idle
        } catch {
            guard gate.accepts(token) else { return }
            itemsPhase = .failed
        }
    }

    private func loadCalendar(_ token: Int) async {
        let now = Date()
        do {
            let result = try await MainProductAPI.shared.schulmanagerCalendar(
                scope: "all",
                from: now.addingTimeInterval(-30 * 86400),
                to: now.addingTimeInterval(120 * 86400)
            )
            guard gate.accepts(token) else { return }
            events = result
            calendarLoadedOnce = true
            calendarPhase = .loaded
        } catch is CancellationError {
            guard gate.accepts(token) else { return }
            calendarPhase = calendarLoadedOnce ? .loaded : .idle
        } catch {
            guard gate.accepts(token) else { return }
            calendarPhase = .failed
        }
    }

    private func loadTasks(_ token: Int) async {
        do {
            let result = try await MainProductAPI.shared.schoolTasks()
            guard gate.accepts(token) else { return }
            canonicalTasks = result.tasks
            tasksLoadedOnce = true
            tasksPhase = .loaded
        } catch is CancellationError {
            guard gate.accepts(token) else { return }
            tasksPhase = tasksLoadedOnce ? .loaded : .idle
        } catch {
            guard gate.accepts(token) else { return }
            // The letter payload still supplies a read-only fallback.  We keep
            // that state visible rather than pretending that the task endpoint
            // returned an empty list.
            tasksPhase = .failed
        }
    }

    private func loadNames(_ token: Int) async {
        if let profiles = try? await MainProductAPI.shared.familyProfiles(), gate.accepts(token) {
            studentNames = profiles.filter(\.isMinor).map(\.displayName)
        }
    }

    private func loadActionTasks(_ token: Int) async {
        do {
            let result = try await MainProductAPI.shared.schoolActionTasks()
            guard gate.accepts(token) else { return }
            actionTasks = result.tasks
            actionTasksPhase = .loaded
        } catch is CancellationError {
            guard gate.accepts(token) else { return }
            actionTasksPhase = actionTasks.isEmpty ? .idle : .loaded
        } catch {
            guard gate.accepts(token) else { return }
            actionTasksPhase = .failed
        }
    }

    func setTaskStatus(_ task: SchoolHubTask, completed: Bool) async throws {
        let updated: OrbitSchoolActionTask
        if task.kind == "family", let actionID = task.actionID {
            updated = completed ? try await MainProductAPI.shared.completeSchoolActionTask(id: actionID) : try await MainProductAPI.shared.reopenSchoolActionTask(id: actionID)
        } else {
            guard !task.sourceItemId.isEmpty else { return }
            let sourceKey = task.id.hasPrefix("\(task.sourceItemId):") ? String(task.id.dropFirst(task.sourceItemId.count + 1)) : task.id
            updated = completed ? try await MainProductAPI.shared.completeSourceSchoolTask(itemId: task.sourceItemId, taskKey: sourceKey) : try await MainProductAPI.shared.reopenSourceSchoolTask(itemId: task.sourceItemId, taskKey: sourceKey)
        }
        if let index = actionTasks.firstIndex(where: { $0.id == updated.id }) { actionTasks[index] = updated }
    }

    func createFamilyTask(title: String, description: String, planningDate: String?) async throws {
        _ = try await MainProductAPI.shared.createSchoolActionTask(title: title, description: description, planningDate: planningDate)
        actionTasks = try await MainProductAPI.shared.schoolActionTasks().tasks
    }
}

private struct SchoolActionHistoryView: View {
    @State private var phase: SchoolHubStore.Phase = .loading
    @State private var entries: [OrbitSchoolActionHistoryEntry] = []

    var body: some View {
        List {
            if phase == .failed {
                SchoolNotice(text: "Історія змін тимчасово недоступна. Спробуйте ще раз.", systemImage: "exclamationmark.triangle")
                Button("Повторити") { load() }.frame(minHeight: OrbitSpacing.minTarget)
            } else if phase == .loading {
                ProgressView().frame(maxWidth: .infinity)
            } else if entries.isEmpty {
                ContentUnavailableView("Історія порожня", systemImage: "clock.arrow.circlepath", description: Text("Тут з’являться зміни сімейних справ, чеклістів і нотаток."))
            } else {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(historyTitle(entry)).font(.subheadline.weight(.semibold))
                        Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(minHeight: OrbitSpacing.minTarget, alignment: .leading)
                }
            }
        }
        .navigationTitle("Історія змін")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func load() { Task { await reload() } }

    private func reload() async {
        phase = .loading
        do {
            entries = try await MainProductAPI.shared.schoolActionHistory().history
            phase = .loaded
        } catch {
            phase = .failed
        }
    }

    private func historyTitle(_ entry: OrbitSchoolActionHistoryEntry) -> String {
        let action: String
        switch entry.action {
        case "created": action = "Створено"
        case "completed": action = "Позначено виконаним"
        case "reopened": action = "Повернуто у відкриті"
        case "updated": action = "Оновлено"
        case "archived": action = "Приховано"
        default: action = entry.action
        }
        return "\(action) · \(entry.entityType)"
    }
}

// MARK: - Formatting

private enum SchoolHubFormat {
    static func formatter(_ pattern: String) -> DateFormatter {
        let value = DateFormatter()
        value.locale = Locale(identifier: "uk_UA")
        value.timeZone = SchoolHubLogic.schoolTimeZone
        value.dateFormat = pattern
        return value
    }
    static func long(_ key: String) -> String {
        guard let date = SchoolHubLogic.date(fromDayKey: key) else { return key }
        return formatter("EEEE, d MMMM").string(from: date)
    }
    static func weekday(_ key: String) -> String {
        guard let date = SchoolHubLogic.date(fromDayKey: key) else { return "" }
        return formatter("EEEEE").string(from: date).uppercased()
    }
    static func dayNumber(_ key: String) -> String { String(Int(key.suffix(2)) ?? 0) }
    static func weekdayShort(_ key: String) -> String {
        guard let date = SchoolHubLogic.date(fromDayKey: key) else { return "" }
        return formatter("EE").string(from: date).capitalized
    }
    static func shortDay(_ key: String) -> String {
        guard let date = SchoolHubLogic.date(fromDayKey: key) else { return key }
        return formatter("d MMM").string(from: date)
    }
    static func month(_ key: String) -> String {
        guard let date = SchoolHubLogic.date(fromDayKey: key) else { return "" }
        return formatter("LLL").string(from: date)
    }
    static func daysFrom(_ today: String, to key: String) -> Int? {
        guard let a = SchoolHubLogic.date(fromDayKey: today), let b = SchoolHubLogic.date(fromDayKey: key) else { return nil }
        return Int((b.timeIntervalSince(a) / 86400).rounded())
    }
    static func relative(_ days: Int) -> String {
        switch days {
        case 0: "сьогодні"
        case 1: "завтра"
        case ..<0: "\(-days) д тому"
        default: "за \(days) д"
        }
    }
    static func time(_ event: SchoolHubEvent) -> String {
        if event.allDay { return "Увесь день" }
        guard let start = event.startsAt, let date = OrbitSchoolDateDecoding.date(from: start) else { return "Час не визначено" }
        var text = formatter("HH:mm").string(from: date)
        if let end = event.endsAt, let endDate = OrbitSchoolDateDecoding.date(from: end), endDate != date { text += "–" + formatter("HH:mm").string(from: endDate) }
        return text
    }
    static func due(_ task: SchoolHubTask) -> String? {
        guard let key = SchoolHubLogic.dayKey(for: task.dueAt, allDay: task.allDay) else { return nil }
        return long(key)
    }
}

// MARK: - Shared components

private struct SchoolEvidenceBadge: View {
    let evidence: SchoolEvidence
    var body: some View {
        Label(evidence.title, systemImage: evidence.systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(schoolEvidenceColor(evidence))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(schoolEvidenceColor(evidence).opacity(0.14), in: Capsule())
            .accessibilityLabel("Довіра: \(evidence.title)")
    }
}

private func schoolEvidenceColor(_ evidence: SchoolEvidence) -> Color {
    switch evidence {
    case .sourceRecord: Color(red: 0.12, green: 0.56, blue: 0.30)
    case .interpretation: .accentColor
    case .needsVerification: Color(red: 0.70, green: 0.42, blue: 0.0)
    }
}

private struct SchoolTrustGlyph: View {
    let evidence: SchoolEvidence
    var body: some View {
        Image(systemName: evidence.systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(schoolEvidenceColor(evidence))
            .accessibilityLabel("Довіра: \(evidence.title)")
    }
}

private struct SchoolClassDot: View {
    let relevance: SchoolEventRelevance
    var body: some View {
        Group {
            switch relevance {
            case .ours: Circle().fill(Color.accentColor)
            case .likely: Circle().fill(Color.accentColor.opacity(0.35)).overlay(Circle().stroke(Color.accentColor, lineWidth: 1.5))
            case .uncertain, .unclassified: Circle().strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
            case .unrelated, .staffOnly: RoundedRectangle(cornerRadius: 2).fill(Color.secondary.opacity(0.6))
            }
        }
        .frame(width: 9, height: 9)
        .accessibilityHidden(true)
    }
}

private struct SchoolRelevanceMarker: View {
    let relevance: SchoolEventRelevance
    var body: some View {
        HStack(spacing: 5) {
            SchoolClassDot(relevance: relevance)
            Text(relevance.title).font(.caption.weight(.medium)).foregroundStyle(relevance == .ours ? Color.accentColor : Color.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SchoolSectionHeader: View {
    let title: String
    var systemImage: String?
    var count: Int?
    var linkTitle: String?
    var link: (() -> Void)?
    var body: some View {
        HStack(spacing: 6) {
            Text(title.uppercased() + (count.map { " · \($0)" } ?? ""))
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let linkTitle, let link {
                Button(linkTitle, action: link).font(.caption.weight(.semibold)).textCase(nil)
            }
        }
        .textCase(nil)
    }
}

private struct SchoolNotice: View {
    let text: String
    let systemImage: String
    var body: some View {
        Label(text, systemImage: systemImage).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

private extension SchoolHubSection {
    var systemImage: String {
        switch self {
        case .overview: "house"
        case .letters: "envelope"
        case .calendar: "calendar"
        case .tasks: "checklist"
        }
    }
}

private func schoolDigestLines(store: SchoolHubStore) -> [String] {
    let now = Date()
    let today = SchoolHubLogic.dayKey(of: now)
    let tomorrow = SchoolHubLogic.addDays(1, to: today) ?? today
    let tasks = store.hubTasks
    let events = store.hubEvents
    let groups = SchoolHubLogic.groupTasks(tasks, today: today, sourceDates: store.sourceDates, now: now)
    let tomorrowCount = SchoolHubLogic.events(events, on: tomorrow).filter(SchoolHubLogic.isDayRelevant).count + SchoolHubLogic.tasks(tasks, dueOn: tomorrow).count
    return SchoolHubLogic.digest(.init(
        unreadLetters: store.letters.filter(\.unread).count, tomorrowEvents: tomorrowCount,
        overdueTasks: groups.overdue.count, datedTasks: groups.dated.count,
        undatedTasks: groups.undated.count + groups.undatedOlder.count,
        unclassifiedEvents: SchoolHubLogic.counts(events)[.unclassified] ?? 0
    ))
}

private struct SchoolDigestSheet: View {
    let store: SchoolHubStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        let lines = schoolDigestLines(store: store)
        NavigationStack {
            List {
                Section {
                    if lines.isEmpty {
                        SchoolNotice(text: store.itemsLoadedOnce ? "У завантажених даних немає нового, що вимагає уваги." : "Дані ще не завантажено.", systemImage: "list.bullet.clipboard")
                    } else {
                        ForEach(lines, id: \.self) { Text($0).font(.subheadline) }
                    }
                } header: { SchoolSectionHeader(title: "Коротко") } footer: { Text("Складено з завантажених даних без AI.") }
                Section {
                    ForEach([SchoolEvidence.sourceRecord, .interpretation, .needsVerification], id: \.self) { evidence in
                        Label { Text(evidence.title).font(.subheadline) } icon: { SchoolTrustGlyph(evidence: evidence) }
                    }
                } header: { SchoolSectionHeader(title: "Рівні довіри") } footer: { Text("Позначки показують, чи дані взято з джерела, чи це інтерпретація Orbit, чи їх треба перевірити за оригіналом.") }
                Section {
                    NavigationLink { SchoolBrainView() } label: { Label("Запитати про школу", systemImage: "sparkles") }.frame(minHeight: OrbitSpacing.minTarget)
                }
            }
            .listSectionSpacing(.compact)
            .navigationTitle("Коротко")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Hub

private struct LegacySchoolHubView: View {
    @State private var store = SchoolHubStore()
    @State private var section: SchoolHubSection = .overview
    @State private var search = ""
    @State private var searching = false
    @State private var showDigest = false
    @FocusState private var searchFocused: Bool
    @EnvironmentObject private var authentication: OrbitAuthentication

    private var scopeKey: String {
        SchoolHubLoadGate.scopeKey(personId: authentication.personId, impersonating: authentication.impersonating)
    }

    var body: some View {
        Group {
            if store.scopeKey == scopeKey {
                hub
            } else {
                ProgressView("Завантаження школи…").frame(maxWidth: .infinity, maxHeight: .infinity).background(OrbitColors.canvas)
            }
        }
        .task(id: scopeKey) {
            if store.scopeKey != scopeKey {
                section = .overview
                search = ""
                searching = false
                showDigest = false
                store.reset(to: scopeKey)
            }
            await store.load()
        }
    }

    private var hub: some View {
        NavigationStack {
            VStack(spacing: 0) {
                breadcrumb
                schoolNav
                header
                if searching { searchField }
                content
            }
            .background(NovaTodayTokens.canvas)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showDigest) { SchoolDigestSheet(store: store) }
        }
    }

    private var breadcrumb: some View {
        HStack(spacing: 7) {
            ZStack {
                Circle().stroke(Color.accentColor, lineWidth: 1.5)
                Text("·").font(.caption.weight(.bold)).foregroundStyle(Color.accentColor)
            }
            .frame(width: 15, height: 15)
            Text("SCHOOL · READ ONLY").fontWeight(.bold).tracking(1.1).foregroundStyle(NovaTodayTokens.teal)
            Spacer()
        }
        .font(.caption2)
        .frame(height: 28)
        .padding(.horizontal, OrbitSpacing.large)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Orbit, Школа")
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Шкільний простір").font(.system(.largeTitle, design: .rounded).weight(.bold)).minimumScaleFactor(0.7).lineLimit(1).accessibilityAddTraits(.isHeader)
                Text("Джерела, дати й справи без запису в Schulmanager").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    searching.toggle()
                    if searching { searchFocused = true } else { search = ""; searchFocused = false }
                }
            } label: { Image(systemName: searching ? "xmark" : "magnifyingglass").frame(width: OrbitSpacing.minTarget, height: OrbitSpacing.minTarget) }
                .accessibilityLabel(searching ? "Закрити пошук" : "Пошук")
            Button { showDigest = true } label: { Image(systemName: "text.alignleft").frame(width: OrbitSpacing.minTarget, height: OrbitSpacing.minTarget) }
                .accessibilityLabel("Коротко і рівні довіри")
        }
        .padding(.horizontal, OrbitSpacing.large)
        .padding(.bottom, 8)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Шукати в завантаженому", text: $search)
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !search.isEmpty {
                Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.accessibilityLabel("Очистити")
            }
        }
        .padding(.horizontal, 12).frame(minHeight: 40)
        .background(OrbitColors.card, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, OrbitSpacing.large).padding(.bottom, 5)
    }

    private var schoolNav: some View {
        let unread = store.letters.filter(\.unread).count
        let today = SchoolHubLogic.dayKey(of: Date())
        let groups = SchoolHubLogic.groupTasks(store.hubTasks, today: today, sourceDates: store.sourceDates, now: Date())
        let open = groups.overdue.count + groups.dated.count + groups.undated.count + groups.undatedOlder.count
        return HStack(spacing: 2) {
            ForEach(SchoolHubSection.allCases) { item in
                let badge = item == .letters ? unread : (item == .tasks ? open : 0)
                let selected = item == section
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { section = item }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: item.systemImage).font(.footnote)
                        Text(item.title).font(.footnote.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                        if badge > 0 {
                            Text("\(badge)").font(.caption2.weight(.bold)).padding(.horizontal, 5).padding(.vertical, 1)
                                .background(selected ? Color.accentColor : Color.secondary.opacity(0.25), in: Capsule())
                                .foregroundStyle(selected ? Color.white : Color.primary)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .background(selected ? OrbitColors.card : .clear, in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(badge > 0 ? "\(item.title), \(badge)" : item.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(NovaTodayTokens.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(NovaTodayTokens.teal.opacity(0.18), lineWidth: 1) }
        .padding(.horizontal, OrbitSpacing.large).padding(.bottom, 6)
        .sensoryFeedback(.selection, trigger: section)
    }

    @ViewBuilder private var content: some View {
        if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            SchoolSearchResultsView(store: store, query: search)
        } else {
            switch section {
            case .overview: SchoolOverviewView(store: store) { section = $0 }
            case .letters: SchoolInboxView(embeddedInNavigation: true, hubMode: true)
            case .calendar: SchoolWeekCalendarView(store: store)
            case .tasks: SchoolTaskListView(store: store)
            }
        }
    }
}

// MARK: - School Hub 3

/// Parent-focused School command center. It owns only presentation and routes;
/// all school records continue to come from the existing authorized API client.
struct SchoolHubView: View {
    fileprivate enum Route: Hashable { case inbox, tasks, calendar, timeline, search, briefing, brain, teams, history, letter(String), event(String) }

    @State private var store = SchoolHubStore()
    @State private var path: [Route] = []
    @EnvironmentObject private var authentication: OrbitAuthentication

    private var scopeKey: String {
        SchoolHubLoadGate.scopeKey(personId: authentication.personId, impersonating: authentication.impersonating)
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.scopeKey == scopeKey {
                    SchoolCommandCenter(store: store, open: { path.append($0) })
                } else {
                    ProgressView("Завантаження школи…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(NovaTodayTokens.canvas)
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                // SchoolHubView owns the navigation stack for this route. The inbox
                // must render its list directly so its letter links stay in the same
                // Route path and SwiftUI never compares nested path element types.
                case .inbox: SchoolInboxView(embeddedInNavigation: true, hubMode: true)
                case .tasks: SchoolTaskListView(store: store).navigationTitle("Справи").navigationBarTitleDisplayMode(.inline)
                case .calendar: SchoolWeekCalendarView(store: store).navigationTitle("Дати").navigationBarTitleDisplayMode(.inline)
                case .timeline: SchoolTimelineView(store: store)
                case .search: SchoolUnifiedSearchView(store: store)
                case .briefing: SchoolTasksView()
                case .brain: SchoolBrainView()
                case .teams: SchoolTeamsFutureView()
                case .history: SchoolActionHistoryView()
                case let .letter(id): SchoolDetailLoaderView(itemID: id)
                case let .event(id):
                    if let event = store.calendarEvent(uid: id) { SchoolEventDetailView(event: event) }
                    else { ContentUnavailableView("Подія недоступна", systemImage: "calendar.badge.exclamationmark") }
                }
            }
        }
        .task(id: scopeKey) {
            if store.scopeKey != scopeKey { store.reset(to: scopeKey) }
            await store.load()
        }
    }
}

private struct SchoolCommandCenter: View {
    let store: SchoolHubStore
    let open: (SchoolHubView.Route) -> Void

    private var now: Date { .now }
    private var today: String { SchoolHubLogic.dayKey(of: now) }
    private var groups: SchoolTaskGroups { SchoolHubLogic.groupTasks(store.openHubTasks, today: today, sourceDates: store.sourceDates, now: now) }
    private var upcoming: [SchoolHubEvent] {
        store.hubEvents
            .filter(SchoolHubLogic.isDayRelevant)
            .filter { (SchoolHubLogic.dayKey(for: $0.startsAt, allDay: $0.allDay) ?? "9999-12-31") >= today }
            .sorted { ($0.startsAt ?? "") < ($1.startsAt ?? "") }
    }
    private var attentionTasks: [SchoolHubTask] { Array((groups.overdue + groups.dated + groups.undated).prefix(3)) }
    private var unread: Int { store.letters.filter(\.unread).count }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                header
                if store.itemsPhase == .failed || store.calendarPhase == .failed || store.tasksPhase == .failed || store.actionTasksPhase == .failed { availabilityNotice }
                prioritySection
                preparationSection
                routesSection
                timelineSection
                latestSection
                sourceSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 120)
        }
        .background(NovaTodayTokens.canvas.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { open(.search) } label: { Label("Знайти у школі", systemImage: "magnifyingglass") }
                    Button { open(.timeline) } label: { Label("Хронологія", systemImage: "list.bullet.indent") }
                    Button { open(.briefing) } label: { Label("Огляд від Orbit", systemImage: "sparkles") }
                    Button { open(.brain) } label: { Label("Запитати Orbit", systemImage: "bubble.left.and.text.bubble.right") }
                    Button { open(.history) } label: { Label("Історія змін", systemImage: "clock.arrow.circlepath") }
                } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("Інструменти школи")
            }
        }
        .refreshable { await store.load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ОРГАНІЗАТОР ШКОЛИ").font(.caption2.weight(.bold)).tracking(1.1).foregroundStyle(NovaTodayTokens.teal)
            Text("Школа").font(.system(.largeTitle, design: .rounded).weight(.bold))
            Text("Що потребує уваги, що далі і де знайти першоджерело.")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var availabilityNotice: some View {
        NovaSurface(tint: .orange) {
            Label("Частина шкільних даних зараз недоступна. Показано лише те, що вже було завантажено.", systemImage: "clock.badge.exclamationmark")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var prioritySection: some View {
        NovaSurface(tint: groups.overdue.isEmpty ? NovaTodayTokens.teal : NovaTodayTokens.coral) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(groups.overdue.isEmpty ? "ЗАРАЗ У ФОКУСІ" : "ПОТРЕБУЄ УВАГИ").font(.caption2.weight(.bold)).tracking(1.2).foregroundStyle(groups.overdue.isEmpty ? NovaTodayTokens.teal : NovaTodayTokens.coral)
                    Text(priorityTitle).font(.title3.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                    Text(priorityDetail).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: groups.overdue.isEmpty ? "checklist" : "exclamationmark.circle.fill")
                    .font(.title2).foregroundStyle(groups.overdue.isEmpty ? NovaTodayTokens.teal : NovaTodayTokens.coral)
            }
            if let task = attentionTasks.first {
                Divider().padding(.vertical, 8)
                Button { open(.tasks) } label: {
                    HStack(spacing: 10) {
                        Circle().stroke(NovaTodayTokens.coral, lineWidth: 2).frame(width: 22, height: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                            Text(taskDue(task)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(); Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                    }
                }.buttonStyle(.plain)
            }
        }
    }

    private var routesSection: some View {
        HStack(spacing: 10) {
            routeCard("Вхідні", detail: unread == 0 ? "Усе прочитано" : "\(unread) нових", icon: "envelope", tint: NovaTodayTokens.teal, route: .inbox)
            routeCard("Справи", detail: taskCountText, icon: "checklist", tint: NovaTodayTokens.coral, route: .tasks)
            routeCard("Дати", detail: upcoming.isEmpty ? "Немає далі" : "\(upcoming.count) подій", icon: "calendar", tint: NovaTodayTokens.indigo, route: .calendar)
        }
    }

    @ViewBuilder private var preparationSection: some View {
        let today = SchoolHubLogic.dayKey(of: now)
        let tomorrow = SchoolHubLogic.addDays(1, to: today) ?? today
        let preparation = SchoolHubLogic.preparation(for: tomorrow, tasks: store.openHubTasks)
        if !preparation.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    sectionTitle("Підготуватися", detail: "Лише дії, які вказані у шкільному джерелі")
                    Spacer()
                    Button("Усі справи") { open(.tasks) }.font(.footnote.weight(.semibold))
                }
                NovaSurface(tint: NovaTodayTokens.coral) {
                    ForEach(Array(preparation.prefix(3).enumerated()), id: \.element.id) { index, task in
                        Button { open(.tasks) } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "circle.dotted").foregroundStyle(NovaTodayTokens.coral)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                                    Text(task.action ?? "Дія з джерела Schulmanager").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Spacer(minLength: 0)
                            }
                        }.buttonStyle(.plain)
                        if index < min(preparation.count, 3) - 1 { Divider().padding(.leading, 30) }
                    }
                }
            }
        }
    }

    private func routeCard(_ title: String, detail: String, icon: String, tint: Color, route: SchoolHubView.Route) -> some View {
        Button { open(route) } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon).font(.headline).foregroundStyle(tint).frame(width: 34, height: 34).background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(title).font(.footnote.weight(.bold)).foregroundStyle(.primary)
                Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading).padding(12)
            .background(NovaTodayTokens.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(tint.opacity(0.18), lineWidth: 1) }
        }.buttonStyle(.plain)
    }

    @ViewBuilder private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { sectionTitle("Далі у школі", detail: "Хронологія подій і підготовки"); Spacer(); Button("Календар") { open(.calendar) }.font(.footnote.weight(.semibold)) }
            if upcoming.isEmpty {
                emptyRow("У завантажених даних немає майбутніх шкільних подій.", icon: "calendar.badge.checkmark")
            } else {
                NovaSurface(tint: NovaTodayTokens.indigo) {
                    ForEach(Array(upcoming.prefix(4).enumerated()), id: \.element.id) { index, event in
                        Button { open(.event(event.uid)) } label: {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(spacing: 3) { Text(eventDay(event)).font(.headline.weight(.bold)); Text(eventMonth(event)).font(.caption2.weight(.bold)).foregroundStyle(NovaTodayTokens.indigo) }.frame(width: 38)
                                VStack(alignment: .leading, spacing: 3) { Text(event.title).font(.subheadline.weight(.semibold)).lineLimit(2); Text(eventTime(event)).font(.caption).foregroundStyle(.secondary) }
                                Spacer(); Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                            }
                        }.buttonStyle(.plain)
                        if index < min(upcoming.count, 4) - 1 { Divider().padding(.vertical, 8) }
                    }
                }
            }
        }
    }

    @ViewBuilder private var latestSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { sectionTitle("Останні повідомлення", detail: "Оригінал і переклад доступні всередині"); Spacer(); Button("Усі") { open(.inbox) }.font(.footnote.weight(.semibold)) }
            if let letter = store.letters.sorted(by: { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }).first {
                Button { open(.letter(letter.id)) } label: {
                    NovaSurface(tint: NovaTodayTokens.teal) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: letter.type == "letter" ? "envelope" : "bubble.left").foregroundStyle(NovaTodayTokens.teal).frame(width: 22)
                            VStack(alignment: .leading, spacing: 4) { Text(letter.title).font(.headline).lineLimit(2); Text([letter.sender, letter.date.map { $0.formatted(date: .abbreviated, time: .omitted) }].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary); if letter.unread { Text("Нове в Orbit").font(.caption2.weight(.bold)).foregroundStyle(NovaTodayTokens.coral) } }
                            Spacer(); Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                        }
                    }
                }.buttonStyle(.plain)
            } else { emptyRow("Нових листів і повідомлень немає.", icon: "envelope.open") }
        }
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Джерела", detail: "Лише читання та прозорі межі")
            NovaSurface(tint: NovaTodayTokens.teal) {
                HStack { Image(systemName: "graduationcap").foregroundStyle(NovaTodayTokens.teal); VStack(alignment: .leading, spacing: 2) { Text("Schulmanager").font(.subheadline.weight(.semibold)); Text("Підключено · лише читання").font(.caption).foregroundStyle(.secondary) }; Spacer() }
                Divider().padding(.vertical, 9)
                Button { open(.teams) } label: { HStack { Image(systemName: "person.2.badge.gearshape").foregroundStyle(.secondary); VStack(alignment: .leading, spacing: 2) { Text("Microsoft Teams").font(.subheadline.weight(.semibold)).foregroundStyle(.primary); Text("Не підключено · майбутнє джерело").font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary) } }.buttonStyle(.plain)
            }
        }
    }

    private var priorityTitle: String { groups.overdue.isEmpty ? (attentionTasks.isEmpty ? "Спокійний день" : "Підготовка до школи") : "Є прострочені справи" }
    private var priorityDetail: String { groups.overdue.isEmpty ? (attentionTasks.isEmpty ? "У джерелах немає відкритих справ із терміном." : "Перегляньте найближчу дію перед наступною подією.") : "Відкрийте справи, щоб перевірити першоджерело і термін." }
    private var taskCountText: String { let count = groups.overdue.count + groups.dated.count + groups.undated.count + groups.undatedOlder.count; return count == 0 ? "Відкритих немає" : "\(count) відкритих" }
    private func sectionTitle(_ title: String, detail: String) -> some View { VStack(alignment: .leading, spacing: 2) { Text(title).font(.title3.weight(.bold)); Text(detail).font(.caption).foregroundStyle(.secondary) } }
    private func emptyRow(_ title: String, icon: String) -> some View { Label(title, systemImage: icon).font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 78, alignment: .leading).padding(.horizontal, 14).background(NovaTodayTokens.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous)) }
    private func taskDue(_ task: SchoolHubTask) -> String { guard let value = task.dueAt, let key = SchoolHubLogic.dayKey(for: value, allDay: task.allDay) else { return "Термін не вказаний · джерело: Schulmanager" }; return SchoolHubFormat.shortDay(key) + " · джерело: Schulmanager" }
    private func eventKey(_ event: SchoolHubEvent) -> String? { SchoolHubLogic.dayKey(for: event.startsAt, allDay: event.allDay) }
    private func eventDay(_ event: SchoolHubEvent) -> String { eventKey(event).map(SchoolHubFormat.dayNumber) ?? "—" }
    private func eventMonth(_ event: SchoolHubEvent) -> String { eventKey(event).map(SchoolHubFormat.month) ?? "" }
    private func eventTime(_ event: SchoolHubEvent) -> String { SchoolHubFormat.time(event) }
}

private struct SchoolTeamsFutureView: View {
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 18) {
            NovaDestinationHeader(eyebrow: "МАЙБУТНЄ ДЖЕРЕЛО", title: "Microsoft Teams", detail: "Підключення ще не налаштоване для цієї сім’ї.", tint: NovaTodayTokens.indigo, symbol: "person.2.badge.gearshape")
            NovaSurface(tint: NovaTodayTokens.indigo) { Text("Коли безпечна інтеграція буде доступна, тут можуть з’явитися завдання, матеріали, оголошення й календар Teams. Orbit не підключатиме обліковий запис і не запитуватиме доступ без окремого підтвердження.").font(.subheadline).foregroundStyle(.secondary) }
        }.padding(16) }.background(NovaTodayTokens.canvas.ignoresSafeArea()).navigationTitle("Джерела")
    }
}

// MARK: - Overview

private struct SchoolOverviewView: View {
    let store: SchoolHubStore
    let navigate: (SchoolHubSection) -> Void
    private var now: Date { Date() }
    private var today: String { SchoolHubLogic.dayKey(of: now) }
    private var tomorrow: String { SchoolHubLogic.addDays(1, to: today) ?? today }

    var body: some View {
        let tasks = store.hubTasks
        let groups = SchoolHubLogic.groupTasks(tasks, today: today, sourceDates: store.sourceDates, now: now)
        let events = store.hubEvents
        let tomorrowEvents = SchoolHubLogic.events(events, on: tomorrow).filter(SchoolHubLogic.isDayRelevant)
        let tomorrowTasks = SchoolHubLogic.tasks(tasks, dueOn: tomorrow)
        let prep = SchoolHubLogic.preparation(for: tomorrow, tasks: tasks)
        List {
            statusSection
            tomorrowSection(events: tomorrowEvents, tasks: tomorrowTasks, prep: prep)
            attentionSection(groups: groups)
            newSection
            upcomingSection(events: events)
            sourcesSection
            Section {
                NavigationLink { SchoolBrainView() } label: { Label("Запитати про школу", systemImage: "sparkles") }.frame(minHeight: OrbitSpacing.minTarget)
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(.compact)
        .refreshable { await store.load() }
    }

    @ViewBuilder private var statusSection: some View {
        if store.itemsPhase == .failed || store.calendarPhase == .failed {
            Section {
                SchoolNotice(text: staleText, systemImage: "exclamationmark.triangle.fill")
                Button("Повторити") { Task { await store.load() } }.frame(minHeight: OrbitSpacing.minTarget)
            }
        } else if store.itemsPhase == .loading && !store.itemsLoadedOnce {
            Section { ProgressView("Завантажуємо школу…").frame(maxWidth: .infinity) }
        }
    }

    private var staleText: String {
        let hasData = store.itemsLoadedOnce || store.calendarLoadedOnce
        let failed = [store.itemsPhase == .failed ? "листи й справи" : nil, store.calendarPhase == .failed ? "календар" : nil].compactMap { $0 }.joined(separator: ", ")
        return hasData ? "Не вдалося оновити: \(failed). Показано раніше завантажені дані — вони можуть бути застарілими." : "Не вдалося завантажити: \(failed). Відсутність записів нижче не означає, що нічого немає."
    }

    private func tomorrowSection(events: [SchoolHubEvent], tasks: [SchoolHubTask], prep: [SchoolHubTask]) -> some View {
        Section {
            if events.isEmpty && tasks.isEmpty {
                SchoolNotice(text: store.calendarPhase == .loaded && store.itemsPhase == .loaded ? "У завантажених даних на завтра подій і справ немає." : "Дані на завтра недоступні — календар або справи не завантажено.", systemImage: "moon.zzz")
                    .listRowBackground(Color.accentColor.opacity(0.10))
            }
            ForEach(events) { event in
                if let source = store.calendarEvent(uid: event.uid) {
                    NavigationLink { SchoolEventDetailView(event: source) } label: { SchoolEventRow(event: event) }
                        .listRowBackground(Color.accentColor.opacity(0.10))
                }
            }
            ForEach(tasks) { SchoolTaskRow(store: store, task: $0, today: today).listRowBackground(Color.accentColor.opacity(0.10)) }
            if !prep.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Підготуватись (за текстами джерел)").font(.footnote.weight(.semibold))
                    ForEach(prep) { Label($0.action ?? $0.title, systemImage: "circle.dotted").font(.footnote) }
                }
                .accessibilityElement(children: .combine)
                .listRowBackground(Color.accentColor.opacity(0.10))
            }
        } header: { SchoolSectionHeader(title: "Завтра · \(SchoolHubFormat.long(tomorrow))", systemImage: "sunrise") }
    }

    private func attentionSection(groups: SchoolTaskGroups) -> some View {
        let weekHorizon = SchoolHubLogic.addDays(7, to: today) ?? today
        let soon = groups.dated.filter { task in
            guard let key = SchoolHubLogic.dayKey(for: task.dueAt, allDay: task.allDay) else { return false }
            return key <= weekHorizon
        }
        let urgent = groups.overdue + soon + groups.undated
        let shown = Array(urgent.prefix(4))
        let rest = urgent.count - shown.count
        return Section {
            if urgent.isEmpty && groups.undatedOlder.isEmpty {
                SchoolNotice(text: store.itemsPhase == .loaded ? "Відкритих справ без дати чи прострочених у завантажених листах немає." : "Справи не завантажено.", systemImage: "checkmark.circle")
            }
            ForEach(shown) { SchoolTaskRow(store: store, task: $0, overdue: groups.overdue.contains($0), today: today) }
            if rest > 0 {
                Button { navigate(.tasks) } label: { Text("Ще \(rest) · усі справи").font(.footnote.weight(.semibold)) }.frame(minHeight: OrbitSpacing.minTarget)
            }
            if !groups.undatedOlder.isEmpty {
                DisclosureGroup("Старіші без дати (\(groups.undatedOlder.count)) · лишаються відкритими") {
                    ForEach(groups.undatedOlder) { SchoolTaskRow(store: store, task: $0, today: today) }
                }.font(.footnote).frame(minHeight: OrbitSpacing.minTarget)
            }
        } header: {
            SchoolSectionHeader(title: "Потребує уваги", count: urgent.count + groups.undatedOlder.count, linkTitle: "Усі справи") { navigate(.tasks) }
        }
    }

    private var newSection: some View {
        let allUnread = store.items.filter(\.unread)
        let unread = allUnread.prefix(3)
        return Section {
            if unread.isEmpty { SchoolNotice(text: store.itemsPhase == .loaded ? "Непрочитаних у Orbit немає." : "Листи не завантажено.", systemImage: "envelope.open") }
            ForEach(Array(unread)) { item in
                NavigationLink { SchoolDetailView(item: item) } label: { SchoolLetterRow(item: item) }
            }
        } header: {
            SchoolSectionHeader(title: "Нове від школи", count: allUnread.count, linkTitle: "Усе") { navigate(.letters) }
        }
    }

    private func upcomingSection(events: [SchoolHubEvent]) -> some View {
        let horizon = SchoolHubLogic.addDays(14, to: today) ?? today
        let upcoming = events.filter { event in
            guard SchoolHubLogic.isDayRelevant(event), let key = SchoolHubLogic.dayKey(for: event.startsAt, allDay: event.allDay) else { return false }
            return key > tomorrow && key <= horizon
        }.sorted { ($0.startsAt ?? "") < ($1.startsAt ?? "") }.prefix(3)
        return Section {
            if upcoming.isEmpty { SchoolNotice(text: store.calendarPhase == .loaded ? "У завантаженому календарі найближчих 14 днів подій немає." : "Календар не завантажено.", systemImage: "calendar") }
            ForEach(Array(upcoming)) { event in
                if let source = store.calendarEvent(uid: event.uid) {
                    NavigationLink { SchoolEventDetailView(event: source) } label: { SchoolEventRow(event: event, showDay: true) }
                }
            }
        } header: {
            SchoolSectionHeader(title: "Найближчі події", linkTitle: "Календар") { navigate(.calendar) }
        }
    }

    private var sourcesSection: some View {
        Section {
            LabeledContent("Schulmanager") {
                Label("Лише читання", systemImage: "checkmark.circle.fill").foregroundStyle(NovaTodayTokens.teal)
            }
            Text("Листи, дати й вкладення показані з авторизованого джерела. Orbit не надсилає відповіді й не змінює Schulmanager.")
                .font(.footnote).foregroundStyle(.secondary)
            LabeledContent("Microsoft Teams") {
                Label("Не підключено", systemImage: "minus.circle").foregroundStyle(.secondary)
            }
        } header: { SchoolSectionHeader(title: "Джерела") }
    }
}

// MARK: - Rows

private struct SchoolLetterRow: View {
    let item: OrbitSchoolItem
    var body: some View {
        let title = item.titlePlainText?.isEmpty == false ? item.titlePlainText! : (item.title.isEmpty ? (item.type == "letter" ? "Лист" : "Повідомлення") : item.title)
        let sender = item.sender.isEmpty ? (item.type == "letter" ? "Лист" : "Повідомлення") : item.sender
        var meta = [sender]
        if let date = item.sourceTimestamp ?? item.importedAt { meta.append(SchoolHubFormat.formatter("d MMM").string(from: date)) }
        if let count = item.tasks?.count, count > 0 { meta.append("\(count) справ") }
        return HStack(alignment: .top, spacing: 10) {
            Circle().fill(item.unread ? Color.accentColor : .clear).frame(width: 8, height: 8).padding(.top, 6).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(item.unread ? .semibold : .regular)).lineLimit(2)
                Text(meta.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(minHeight: OrbitSpacing.minTarget, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityValue(item.unread ? "Непрочитано" : "")
    }
}

private struct SchoolEventRow: View {
    let event: SchoolHubEvent
    var showDay = false
    var body: some View {
        let relevance = SchoolHubLogic.relevance(of: event)
        let key = SchoolHubLogic.dayKey(for: event.startsAt, allDay: event.allDay)
        HStack(alignment: .top, spacing: 12) {
            Group {
                if showDay, let key {
                    VStack(spacing: 0) {
                        Text(SchoolHubFormat.dayNumber(key)).font(.title3.weight(.bold)).foregroundStyle(Color.accentColor)
                        Text(SchoolHubFormat.month(key)).font(.caption2).foregroundStyle(.secondary)
                    }
                } else {
                    Text(SchoolHubFormat.time(event)).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(Color.accentColor).lineLimit(2).minimumScaleFactor(0.8)
                }
            }
            .frame(width: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title).font(.callout.weight(.medium)).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    SchoolRelevanceMarker(relevance: relevance)
                    if showDay { Text("· \(SchoolHubFormat.time(event))").font(.caption).foregroundStyle(.secondary) }
                    if !event.location.isEmpty { Text("· \(event.location)").font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
            }
        }
        .frame(minHeight: OrbitSpacing.minTarget, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct SchoolTaskRow: View {
    let store: SchoolHubStore
    let task: SchoolHubTask
    var overdue = false
    var today = SchoolHubLogic.dayKey(of: Date())
    @State private var actionError: String?

    var body: some View {
        let item = store.item(id: task.sourceItemId)
        let evidence = SchoolHubLogic.evidence(forTask: task, sourceLoaded: item != nil, activeNames: store.studentNames, sourceText: item?.originalPlainText ?? item?.originalGerman ?? "")
        let dueKey = SchoolHubLogic.dayKey(for: task.dueAt, allDay: task.allDay)
        let days = dueKey.flatMap { SchoolHubFormat.daysFrom(today, to: $0) }
        let warn = overdue || (days.map { $0 <= 2 } ?? false)
        let row = HStack(alignment: .center, spacing: 10) {
            Image(systemName: task.status == "completed" ? "checkmark.circle.fill" : "circle.dotted")
                .foregroundStyle(task.status == "completed" ? NovaTodayTokens.teal : Color.secondary.opacity(0.8))
                .frame(width: 21, height: 21)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(task.title).font(.callout.weight(.medium)).lineLimit(2)
                    SchoolTrustGlyph(evidence: evidence)
                }
                metaLine(dueKey: dueKey, days: days, warn: warn, item: item, evidence: evidence)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary).accessibilityHidden(true)
        }
        .frame(minHeight: 56, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(task.title). \(task.status == "completed" ? "Виконано." : "Відкрито.")")
        NavigationLink { SchoolTaskDetailView(store: store, task: task) } label: { row }
            .buttonStyle(.plain)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button {
                    Task {
                        do { try await store.setTaskStatus(task, completed: task.status != "completed") }
                        catch { actionError = "Не вдалося зберегти стан справи. Перевірте з’єднання й повторіть." }
                    }
                } label: {
                    Label(task.status == "completed" ? "Відкрити" : "Готово", systemImage: task.status == "completed" ? "arrow.uturn.backward" : "checkmark")
                }.tint(task.status == "completed" ? .orange : NovaTodayTokens.teal)
            }
        .alert("Стан справи", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("Гаразд") { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
    }

    private func metaLine(dueKey: String?, days: Int?, warn: Bool, item: OrbitSchoolItem?, evidence: SchoolEvidence) -> some View {
        var due = "Без дати"
        if let dueKey {
            due = SchoolHubFormat.shortDay(dueKey)
            if let days { due += " · " + SchoolHubFormat.relative(days) }
        }
        var rest: [String] = ["Schulmanager"]
        if let target = task.target, !target.isEmpty { rest.append(target) }
        if evidence == .needsVerification { rest.append("перевірити") }
        let dueColor: Color = overdue ? .red : (warn ? Color(red: 0.70, green: 0.42, blue: 0.0) : .secondary)
        return (Text(Image(systemName: dueKey == nil ? "calendar.badge.questionmark" : (overdue ? "clock.badge.exclamationmark" : "calendar"))).foregroundStyle(dueColor) + Text(" " + due).foregroundStyle(dueColor).fontWeight(warn ? .semibold : .regular) + Text(rest.isEmpty ? "" : " · " + rest.joined(separator: " · ")).foregroundStyle(.secondary))
            .font(.caption2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SchoolTaskDetailView: View {
    let store: SchoolHubStore
    let task: SchoolHubTask
    @State private var updating = false
    @State private var error: String?

    private var source: OrbitSchoolItem? { store.item(id: task.sourceItemId) }
    private var dueKey: String? { SchoolHubLogic.dayKey(for: task.dueAt, allDay: task.allDay) }

    var body: some View {
        List {
            Section {
                Text(task.title)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if let action = task.action, action != task.title {
                    Text(action).font(.body).textSelection(.enabled)
                }
            }
            Section("Термін") {
                if let dueKey {
                    Label(SchoolHubFormat.long(dueKey), systemImage: "calendar")
                } else {
                    Label("Термін не вказано в джерелі", systemImage: "calendar.badge.questionmark")
                        .foregroundStyle(.secondary)
                }
                if let target = task.target, !target.isEmpty {
                    LabeledContent("Кого стосується", value: target)
                }
                if let importance = task.importance, !importance.isEmpty {
                    LabeledContent("Позначка джерела", value: importance)
                }
            }
            if let reason = task.reason, !reason.isEmpty {
                Section("Контекст") { Text(reason).textSelection(.enabled) }
            }
            Section("Джерело") {
                LabeledContent("Система", value: "Schulmanager · лише читання")
                if let source {
                    NavigationLink { SchoolDetailView(item: source) } label: {
                        Label("Відкрити лист або повідомлення", systemImage: source.type == "letter" ? "envelope" : "message")
                    }
                } else {
                    Label("Пов’язаний лист зараз недоступний", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Button {
                    guard !updating else { return }
                    updating = true
                    Task {
                        defer { updating = false }
                        do { try await store.setTaskStatus(task, completed: task.status == "completed" ? false : true) }
                        catch { self.error = "Не вдалося зберегти стан справи. Перевірте з’єднання й повторіть." }
                    }
                } label: {
                    Label(task.status == "completed" ? "Повернути у відкриті" : "Позначити виконаною", systemImage: task.status == "completed" ? "arrow.uturn.backward.circle" : "checkmark.circle")
                }
                .disabled(updating)
                .frame(minHeight: OrbitSpacing.minTarget)
                if updating { ProgressView().frame(maxWidth: .infinity) }
            } header: { Text("Стан Orbit") } footer: {
                Text(task.kind == "family" ? "Це сімейна справа Orbit і не змінює шкільне джерело." : "Стан зберігається в Orbit окремо від Schulmanager.")
            }
            Section("Підготовка й нотатки") {
                NavigationLink { SchoolChecklistView(sourceItemId: task.sourceItemId.isEmpty ? nil : task.sourceItemId, sourceTaskId: task.actionID) } label: {
                    Label("Чекліст підготовки", systemImage: "checklist.checked")
                }
                NavigationLink { SchoolNotesView(entityType: "task", entityId: task.id) } label: {
                    Label("Сімейні нотатки", systemImage: "note.text")
                }
            }
            Section {
                Label("Стан збережено окремо в Orbit і не змінює запис у Schulmanager.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Справа")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Стан справи", isPresented: .constant(error != nil)) { Button("Гаразд") { error = nil } } message: { Text(error ?? "") }
    }
}

private struct SchoolChecklistView: View {
    let sourceItemId: String?
    let sourceTaskId: String?
    @State private var checklists: [OrbitSchoolActionChecklist] = []
    @State private var newTitle = ""
    @State private var newItem = ""
    @State private var loading = false
    @State private var error: String?

    private var visible: [OrbitSchoolActionChecklist] {
        checklists.filter { $0.sourceItemId == sourceItemId || (sourceTaskId != nil && $0.sourceTaskId == sourceTaskId) }
    }

    var body: some View {
        List {
            Section {
                TextField("Нова підготовка", text: $newTitle)
                Button("Створити чекліст") { createChecklist() }.disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: { Text("Сімейна підготовка") } footer: { Text("Пункти чекліста належать родині Orbit і не змінюють шкільне джерело.") }
            if visible.isEmpty && !loading {
                ContentUnavailableView("Чеклістів ще немає", systemImage: "checklist", description: Text("Створіть перший список підготовки для цієї справи."))
            }
            ForEach(visible) { checklist in
                Section {
                    ForEach(checklist.items) { item in
                        Button {
                            Task { await update(item, completed: item.completedAt == nil) }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: item.completedAt == nil ? "circle" : "checkmark.circle.fill")
                                    .foregroundStyle(item.completedAt == nil ? .secondary : NovaTodayTokens.teal)
                                Text(item.title).strikethrough(item.completedAt != nil).foregroundStyle(item.completedAt == nil ? .primary : .secondary)
                                Spacer()
                            }
                        }.buttonStyle(.plain).frame(minHeight: OrbitSpacing.minTarget)
                    }
                    HStack {
                        TextField("Додати пункт", text: $newItem)
                        Button("Додати") { addItem(checklist) }.disabled(newItem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } header: {
                    HStack { Text(checklist.title); Spacer(); Text(progress(checklist)).font(.caption).foregroundStyle(.secondary) }
                }
            }
            if loading { ProgressView().frame(maxWidth: .infinity) }
        }
        .navigationTitle("Підготовка")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .alert("Підготовка", isPresented: .constant(error != nil)) { Button("Гаразд") { error = nil } } message: { Text(error ?? "") }
    }

    private func load() async {
        loading = true; defer { loading = false }
        do { checklists = try await MainProductAPI.shared.schoolActionChecklists().checklists }
        catch { self.error = "Не вдалося завантажити чеклісти." }
    }
    private func createChecklist() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines); guard !title.isEmpty else { return }
        Task { do { _ = try await MainProductAPI.shared.createSchoolActionChecklist(title: title, sourceItemId: sourceItemId, sourceTaskId: sourceTaskId); newTitle = ""; await load() } catch { self.error = "Не вдалося створити чекліст." } }
    }
    private func addItem(_ checklist: OrbitSchoolActionChecklist) {
        let title = newItem.trimmingCharacters(in: .whitespacesAndNewlines); guard !title.isEmpty else { return }
        Task { do { _ = try await MainProductAPI.shared.addSchoolChecklistItem(checklistId: checklist.id, title: title); newItem = ""; await load() } catch { self.error = "Не вдалося додати пункт." } }
    }
    private func update(_ item: OrbitSchoolActionChecklistItem, completed: Bool) async {
        do { _ = try await MainProductAPI.shared.updateSchoolChecklistItem(id: item.id, completed: completed); await load() } catch { self.error = "Не вдалося оновити пункт." }
    }
    private func progress(_ checklist: OrbitSchoolActionChecklist) -> String {
        let done = checklist.items.filter { $0.completedAt != nil }.count
        return "\(done)/\(checklist.items.count)"
    }
}

private struct SchoolNotesView: View {
    let entityType: String
    let entityId: String
    @State private var notes: [OrbitSchoolActionNote] = []
    @State private var draft = ""
    @State private var editing: OrbitSchoolActionNote?
    @State private var error: String?

    var body: some View {
        List {
            Section {
                TextField("Нова нотатка", text: $draft, axis: .vertical).lineLimit(2...5)
                Button("Зберегти нотатку") { create() }.disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: { Text("Сімейні нотатки") } footer: { Text("Нотатки приватні для поточного Orbit-профілю й чітко відокремлені від тексту школи.") }
            if notes.isEmpty { ContentUnavailableView("Нотаток ще немає", systemImage: "note.text", description: Text("Збережіть власне рішення або пояснення батьків.")) }
            ForEach(notes) { note in
                Button { editing = note } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(note.content).foregroundStyle(.primary).multilineTextAlignment(.leading)
                        Text(note.updatedAt, format: .dateTime.day().month(.abbreviated).hour().minute()).font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                }.buttonStyle(.plain)
            }
        }
        .navigationTitle("Нотатки")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $editing) { note in SchoolNoteEditor(note: note) { content in await update(note, content: content) } }
        .alert("Нотатки", isPresented: .constant(error != nil)) { Button("Гаразд") { error = nil } } message: { Text(error ?? "") }
    }

    private func load() async {
        do { notes = try await MainProductAPI.shared.schoolActionNotes().notes.filter { $0.entityType == entityType && $0.entityId == entityId } }
        catch { self.error = "Не вдалося завантажити нотатки." }
    }
    private func create() {
        let content = draft.trimmingCharacters(in: .whitespacesAndNewlines); guard !content.isEmpty else { return }
        Task { do { _ = try await MainProductAPI.shared.createSchoolActionNote(entityType: entityType, entityId: entityId, content: content); draft = ""; await load() } catch { self.error = "Не вдалося зберегти нотатку." } }
    }
    private func update(_ note: OrbitSchoolActionNote, content: String) async {
        do { _ = try await MainProductAPI.shared.updateSchoolActionNote(id: note.id, content: content); await load() } catch { self.error = "Не вдалося оновити нотатку." }
    }
}

private struct SchoolNoteEditor: View {
    let note: OrbitSchoolActionNote
    let save: (String) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var content: String

    init(note: OrbitSchoolActionNote, save: @escaping (String) async -> Void) { self.note = note; self.save = save; _content = State(initialValue: note.content) }

    var body: some View {
        NavigationStack {
            TextEditor(text: $content).padding(12).navigationTitle("Редагувати нотатку").navigationBarTitleDisplayMode(.inline).toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Скасувати") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Зберегти") { Task { await save(content); dismiss() } }.disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
        }
    }
}

private struct SchoolFamilyTaskEditorView: View {
    let store: SchoolHubStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var description = ""
    @State private var hasPlanningDate = false
    @State private var planningDate = Date()
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Сімейна справа") {
                    TextField("Що потрібно зробити?", text: $title, axis: .vertical)
                        .lineLimit(1...3)
                    TextField("Деталі (необов’язково)", text: $description, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section("Планування") {
                    Toggle("Додати особисту дату", isOn: $hasPlanningDate)
                    if hasPlanningDate { DatePicker("Підготувати до", selection: $planningDate, displayedComponents: .date) }
                }
                Section {
                    Text("Це запис родини Orbit, а не вимога Schulmanager. Його можна буде завершити або відкрити знову.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Нова справа")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Скасувати") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Створити") { save() }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving)
                }
            }
            .overlay { if saving { ProgressView("Зберігаємо…") } }
            .alert("Справу не створено", isPresented: .constant(error != nil)) { Button("Гаразд") { error = nil } } message: { Text(error ?? "") }
        }
    }

    private func save() {
        saving = true
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let date: String?
        if hasPlanningDate {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            date = formatter.string(from: planningDate)
        } else {
            date = nil
        }
        Task {
            defer { saving = false }
            do { try await store.createFamilyTask(title: trimmedTitle, description: trimmedDescription, planningDate: date); dismiss() }
            catch { self.error = "Не вдалося зберегти сімейну справу. Перевірте з’єднання й повторіть." }
        }
    }
}

// MARK: - Tasks

private struct SchoolTaskListView: View {
    let store: SchoolHubStore
    @State private var query = ""
    @State private var filter: TaskFilter = .all
    @State private var showCreate = false

    private enum TaskFilter: String, CaseIterable, Identifiable {
        case all, dated, undated, verification, completed
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: "Усі"
            case .dated: "З терміном"
            case .undated: "Без терміну"
            case .verification: "Перевірити"
            case .completed: "Виконані"
            }
        }
    }

    var body: some View {
        let today = SchoolHubLogic.dayKey(of: Date())
            let tasks = filteredTasks
        let schedule = SchoolHubLogic.scheduleTasks(tasks, today: today, sourceDates: store.sourceDates, now: Date())
        List {
            Section {
                Picker("Показати", selection: $filter) {
                    ForEach(TaskFilter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
            } header: { Text("Фільтр") }
            if store.tasksPhase == .failed {
                Section {
                    SchoolNotice(
                        text: store.itemsLoadedOnce ? "Не вдалося оновити централізований список справ. Показано справи, витягнуті з уже завантажених листів — вони можуть бути неповними." : "Не вдалося завантажити справи.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    Button("Повторити") { Task { await store.load() } }.frame(minHeight: OrbitSpacing.minTarget)
                }
            } else if store.tasksPhase == .loading && !store.tasksLoadedOnce {
                Section { ProgressView().frame(maxWidth: .infinity) }
            }
            group("Прострочені", tasks: schedule.overdue, overdue: true, today: today)
            group("Сьогодні", tasks: schedule.today, today: today)
            group("Завтра", tasks: schedule.tomorrow, today: today)
            group("Цього тижня", tasks: schedule.thisWeek, today: today)
            group("Пізніше", tasks: schedule.later, today: today)
            group("Без дати", tasks: schedule.undated, today: today)
            if !schedule.undatedOlder.isEmpty {
                Section { DisclosureGroup("Старіші без дати (\(schedule.undatedOlder.count)) · лишаються відкритими") { ForEach(schedule.undatedOlder) { SchoolTaskRow(store: store, task: $0, today: today) } }.font(.footnote).frame(minHeight: OrbitSpacing.minTarget) }
            }
            if store.tasksPhase == .loaded && tasks.isEmpty {
                ContentUnavailableView(
                    query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Відкритих справ немає" : "Справ не знайдено",
                    systemImage: query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "checklist" : "magnifyingglass",
                    description: Text(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Це лише справи, які повернуло авторизоване шкільне джерело." : "Спробуйте інший запит або фільтр.")
                )
            }
            Section { SchoolNotice(text: "Позначення виконання ще не синхронізується між пристроями. Orbit не показує локальну позначку як збережену.", systemImage: "info.circle") }
        }
        .listSectionSpacing(.compact)
        .searchable(text: $query, prompt: "Шукати справи")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCreate = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Створити сімейну справу")
            }
        }
        .sheet(isPresented: $showCreate) {
            SchoolFamilyTaskEditorView(store: store)
        }
        .refreshable { await store.load() }
    }

    private var filteredTasks: [SchoolHubTask] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let searched = query.isEmpty ? store.hubTasks : SchoolHubLogic.searchTasks(store.hubTasks, query: query)
        return searched.filter { task in
            if filter != .completed && task.status == "completed" { return false }
            switch filter {
            case .all:
                return task.status != "completed"
            case .dated:
                return SchoolHubLogic.dayKey(for: task.dueAt, allDay: task.allDay) != nil
            case .undated:
                return SchoolHubLogic.dayKey(for: task.dueAt, allDay: task.allDay) == nil
            case .verification:
                let item = store.item(id: task.sourceItemId)
                return SchoolHubLogic.evidence(forTask: task, sourceLoaded: item != nil, activeNames: store.studentNames, sourceText: item?.originalPlainText ?? item?.originalGerman ?? "") == .needsVerification
            case .completed:
                return task.status == "completed"
            }
        }
    }

    @ViewBuilder private func group(_ title: String, tasks: [SchoolHubTask], overdue: Bool = false, today: String) -> some View {
        if !tasks.isEmpty {
            Section { ForEach(tasks) { SchoolTaskRow(store: store, task: $0, overdue: overdue, today: today) } } header: { SchoolSectionHeader(title: title, count: tasks.count) }
        }
    }
}

// MARK: - Calendar

private struct SchoolWeekCalendarView: View {
    let store: SchoolHubStore
    @State private var selected = SchoolHubLogic.dayKey(of: Date())
    @State private var filter: SchoolEventFilter = .all

    var body: some View {
        let events = store.hubEvents
        let week = SchoolHubLogic.weekDays(containing: selected)
        let filtered = SchoolHubLogic.filter(events, by: filter)
        let dayEvents = SchoolHubLogic.events(filtered, on: selected)
        let counts = SchoolHubLogic.counts(events)
        let later = filtered.filter { event in
            guard SchoolHubLogic.isDayRelevant(event), let key = SchoolHubLogic.dayKey(for: event.startsAt, allDay: event.allDay) else { return false }
            return key > selected
        }.sorted { ($0.startsAt ?? "") < ($1.startsAt ?? "") }.prefix(3)
        List {
            Section {
                weekHeader(week: week)
                weekStrip(week: week, events: filtered)
                filterChips(events: events)
                if (counts[.unclassified] ?? 0) > 0 {
                    SchoolNotice(text: "Без класифікації: \(counts[.unclassified] ?? 0) — показано у «Усі» та «Можливо», вони не вважаються нерелевантними.", systemImage: "circle.dashed")
                }
            }
            if store.calendarPhase == .failed {
                Section { SchoolNotice(text: store.calendarLoadedOnce ? "Не вдалося оновити календар — дані можуть бути застарілими." : "Не вдалося завантажити календар.", systemImage: "exclamationmark.triangle.fill"); Button("Повторити") { Task { await store.load() } }.frame(minHeight: OrbitSpacing.minTarget) }
            }
            Section {
                if dayEvents.isEmpty {
                    SchoolNotice(text: store.calendarPhase == .loaded ? "У завантаженому календарі на цей день подій немає (фільтр: \(filter.title))." : "Календар недоступний або ще завантажується.", systemImage: "calendar")
                }
                ForEach(dayEvents) { event in
                    if let source = store.calendarEvent(uid: event.uid) { NavigationLink { SchoolEventDetailView(event: source) } label: { SchoolEventRow(event: event) } }
                }
            } header: { SchoolSectionHeader(title: SchoolHubFormat.long(selected), count: dayEvents.count) }
            if !later.isEmpty {
                Section {
                    ForEach(Array(later)) { event in
                        if let source = store.calendarEvent(uid: event.uid) { NavigationLink { SchoolEventDetailView(event: source) } label: { SchoolEventRow(event: event, showDay: true) } }
                    }
                } header: { SchoolSectionHeader(title: "Далі") }
            }
            let undated = SchoolHubLogic.undatedEvents(filtered)
            if !undated.isEmpty {
                Section { ForEach(undated) { event in if let source = store.calendarEvent(uid: event.uid) { NavigationLink { SchoolEventDetailView(event: source) } label: { SchoolEventRow(event: event) } } } } header: { SchoolSectionHeader(title: "Без дати", count: undated.count) }
            }
        }
        .listSectionSpacing(.compact)
        .refreshable { await store.load() }
    }

    private func weekHeader(week: [String]) -> some View {
        HStack {
            stepButton("chevron.left", label: "Попередній тиждень", days: -7)
            Spacer()
            Text("\(SchoolHubFormat.shortDay(week.first ?? selected)) — \(SchoolHubFormat.shortDay(week.last ?? selected)) · тиждень").font(.footnote.weight(.semibold))
            Spacer()
            stepButton("chevron.right", label: "Наступний тиждень", days: 7)
        }
        .buttonStyle(.plain)
    }

    private func weekStrip(week: [String], events: [SchoolHubEvent]) -> some View {
        HStack(spacing: 4) {
            ForEach(week, id: \.self) { day in
                let dayList = SchoolHubLogic.events(events, on: day)
                let count = dayList.count
                let isSelected = day == selected
                Button { withAnimation(.easeOut(duration: 0.15)) { selected = day } } label: {
                    VStack(spacing: 3) {
                        Text(SchoolHubFormat.weekdayShort(day)).font(.caption2.weight(.medium))
                        Text(SchoolHubFormat.dayNumber(day)).font(.callout.weight(.semibold))
                        HStack(spacing: 2) {
                            ForEach(0..<min(3, count), id: \.self) { _ in Circle().fill(isSelected ? Color.white : Color.accentColor).frame(width: 4, height: 4) }
                        }.frame(height: 4)
                    }
                    .frame(maxWidth: .infinity, minHeight: 62)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(SchoolHubFormat.long(day)), подій: \(count)")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selected)
    }

    private func filterChips(events: [SchoolHubEvent]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SchoolEventFilter.allCases) { item in
                    let isSelected = item == filter
                    Button { withAnimation(.easeOut(duration: 0.15)) { filter = item } } label: {
                        Text("\(item.title) · \(SchoolHubLogic.filter(events, by: item).count)")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 12).frame(minHeight: 34)
                            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                            .background(isSelected ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.10), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
    }

    private func stepButton(_ icon: String, label: String, days: Int) -> some View {
        Button { withAnimation(.easeOut(duration: 0.15)) { selected = SchoolHubLogic.addDays(days, to: selected) ?? selected } } label: {
            Image(systemName: icon).frame(width: 36, height: OrbitSpacing.minTarget)
        }
        .buttonStyle(.plain).foregroundStyle(Color.accentColor).accessibilityLabel(label)
    }
}

struct SchoolEventDetailView: View {
    let event: OrbitSchulmanagerCalendarEvent
    @State private var message: String?
    @State private var pending = false

    var body: some View {
        let hub = SchoolHubEvent(uid: event.uid, title: event.title, description: event.description, location: event.location, startsAt: event.startsAt, endsAt: event.endsAt, allDay: event.allDay, relevanceClass: event.relevanceClass, audienceClass: event.audienceClass, relevanceReason: event.relevanceReason)
        let relevance = SchoolHubLogic.relevance(of: hub)
        List {
            Section {
                Text(event.title).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                Text(event.allDay ? OrbitSchoolCivilDate.inclusiveRange(start: event.startsAt, end: event.endsAt) : [SchoolHubLogic.dayKey(for: event.startsAt, allDay: false).map(SchoolHubFormat.long), SchoolHubFormat.time(hub)].compactMap { $0 }.joined(separator: ", "))
                if !event.location.isEmpty { Label(event.location, systemImage: "mappin.and.ellipse") }
            }
            Section("Релевантність") {
                SchoolRelevanceMarker(relevance: relevance)
                SchoolEvidenceBadge(evidence: SchoolHubLogic.evidence(forEvent: hub))
                if let reason = event.relevanceReason, !reason.isEmpty { Text(reason).font(.subheadline).foregroundStyle(.secondary) }
                if relevance == .unclassified || relevance == .uncertain { Text("Orbit не визначив, чи це стосується вас. Перевірте опис події.").font(.footnote).foregroundStyle(.orange) }
            }
            if !event.description.isEmpty { Section("Опис у джерелі") { Text(event.description).textSelection(.enabled) } }
            Section("Джерело") {
                LabeledContent("Система", value: "Schulmanager (лише читання)")
                LabeledContent("UID", value: event.uid)
            }
            Section {
                Button("Запропонувати додати до сімейного календаря") { Task { await propose() } }.frame(minHeight: OrbitSpacing.minTarget)
            } footer: { Text("Подію буде створено лише в сімейному календарі Orbit, не в зовнішніх календарях.") }
        }
        .navigationTitle("Подія")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Календар школи", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("Гаразд") { message = nil } } message: { Text(message ?? "") }
        .confirmationDialog("Додати подію до сімейного календаря Orbit?", isPresented: $pending, titleVisibility: .visible) {
            Button("Додати «\(event.title)»") { Task { await confirm() } }
            Button("Скасувати", role: .cancel) { pending = false }
        }
    }

    private func propose() async {
        do {
            let preview = try await MainProductAPI.shared.addSchoolCalendarEvent(uid: event.uid, confirm: false)
            if preview.duplicate == true { message = "Цю подію вже додано." } else if preview.requiresConfirmation == true { pending = true } else { message = "Не вдалося підготувати додавання події." }
        } catch { message = "Не вдалося підготувати додавання події." }
    }
    private func confirm() async {
        pending = false
        do {
            let result = try await MainProductAPI.shared.addSchoolCalendarEvent(uid: event.uid, confirm: true)
            message = result.duplicate == true ? "Цю подію вже додано." : (result.created ? "Подію додано до сімейного календаря." : "Не вдалося додати подію.")
        } catch { message = "Не вдалося додати подію." }
    }
}

// MARK: - School Life Manager views

private struct SchoolTimelineView: View {
    let store: SchoolHubStore
    @State private var horizon = 14

    private var today: String { SchoolHubLogic.dayKey(of: Date()) }
    private var through: String { SchoolHubLogic.addDays(horizon, to: today) ?? today }
    private var entries: [SchoolTimelineEntry] {
        SchoolHubLogic.timeline(letters: store.letters, tasks: store.hubTasks, events: store.hubEvents, from: today, through: through)
    }

    var body: some View {
        List {
            Section {
                SchoolNotice(text: "Хронологія об’єднує лише завантажені записи. Кожен рядок зберігає посилання на своє джерело.", systemImage: "link")
            }
            Picker("Період", selection: $horizon) {
                Text("14 днів").tag(14)
                Text("30 днів").tag(30)
                Text("90 днів").tag(90)
            }
            .pickerStyle(.segmented)
            if entries.isEmpty {
                ContentUnavailableView("Хронологія порожня", systemImage: "list.bullet.indent", description: Text("Немає датованих шкільних записів у вибраному періоді."))
            } else {
                ForEach(Dictionary(grouping: entries, by: \.day).keys.sorted(), id: \.self) { day in
                    Section(SchoolHubFormat.long(day)) {
                        ForEach(Dictionary(grouping: entries, by: \.day)[day] ?? []) { entry in
                            timelineLink(entry)
                        }
                    }
                }
            }
            let undated = store.hubTasks.filter { SchoolHubLogic.dayKey(for: $0.dueAt, allDay: $0.allDay) == nil }
            if !undated.isEmpty {
                Section("Без підтвердженої дати") {
                    Text("Ці справи залишаються видимими, але Orbit не призначає їм дату самостійно.")
                        .font(.footnote).foregroundStyle(.secondary)
                    ForEach(undated) { task in
                        NavigationLink { SchoolTaskDetailView(store: store, task: task) } label: {
                            Label(task.title, systemImage: "calendar.badge.questionmark")
                        }
                    }
                }
            }
        }
        .navigationTitle("Хронологія")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private func timelineLink(_ entry: SchoolTimelineEntry) -> some View {
        switch entry.kind {
        case .letter:
            if let id = entry.sourceItemId, let item = store.item(id: id) {
                NavigationLink { SchoolDetailView(item: item) } label: { timelineRow(entry) }
            } else if let id = entry.sourceItemId {
                NavigationLink { SchoolDetailLoaderView(itemID: id) } label: { timelineRow(entry) }
            }
        case .task:
            if let task = store.hubTasks.first(where: { $0.id == String(entry.id.dropFirst(5)) }) {
                NavigationLink { SchoolTaskDetailView(store: store, task: task) } label: { timelineRow(entry) }
            } else { timelineRow(entry) }
        case .event:
            if let uid = entry.eventUID, let event = store.calendarEvent(uid: uid) {
                NavigationLink { SchoolEventDetailView(event: event) } label: { timelineRow(entry) }
            } else { timelineRow(entry) }
        }
    }

    private func timelineRow(_ entry: SchoolTimelineEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: entry.kind.systemImage).foregroundStyle(entry.kind == .task ? NovaTodayTokens.coral : (entry.kind == .event ? NovaTodayTokens.indigo : NovaTodayTokens.teal)).frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(entry.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .frame(minHeight: OrbitSpacing.minTarget, alignment: .leading)
    }
}

private struct SchoolUnifiedSearchView: View {
    let store: SchoolHubStore
    @State private var query = ""
    @State private var kind: SearchKind = .all

    private enum SearchKind: String, CaseIterable, Identifiable {
        case all, letters, tasks, events
        var id: String { rawValue }
        var title: String {
            switch self { case .all: "Усе"; case .letters: "Листи"; case .tasks: "Справи"; case .events: "Події" }
        }
    }

    private var letters: [SchoolHubLetter] { kind == .tasks || kind == .events ? [] : SchoolHubLogic.searchLetters(store.letters, query: query) }
    private var tasks: [SchoolHubTask] { kind == .letters || kind == .events ? [] : SchoolHubLogic.searchTasks(store.hubTasks, query: query) }
    private var events: [SchoolHubEvent] { kind == .letters || kind == .tasks ? [] : SchoolHubLogic.searchEvents(store.hubEvents, query: query) }

    var body: some View {
        List {
            Section { SchoolNotice(text: SchoolHubLogic.searchScopeNote + ". Пошук не заявляє повну історію, якщо сервер не повернув її в завантаженому вікні.", systemImage: "magnifyingglass") }
            Picker("Тип", selection: $kind) { ForEach(SearchKind.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView("Пошук школи", systemImage: "magnifyingglass", description: Text("Знайдіть лист, справу або подію серед авторизованих даних."))
            } else if letters.isEmpty && tasks.isEmpty && events.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                if !letters.isEmpty {
                    Section("Листи й повідомлення · \(letters.count)") {
                        ForEach(letters) { letter in
                            if let item = store.item(id: letter.id) { NavigationLink { SchoolDetailView(item: item) } label: { searchLetterRow(letter) } }
                        }
                    }
                }
                if !tasks.isEmpty {
                    Section("Справи · \(tasks.count)") {
                        ForEach(tasks) { task in NavigationLink { SchoolTaskDetailView(store: store, task: task) } label: { searchTaskRow(task) } }
                    }
                }
                if !events.isEmpty {
                    Section("Події · \(events.count)") {
                        ForEach(events) { event in
                            if let source = store.calendarEvent(uid: event.uid) { NavigationLink { SchoolEventDetailView(event: source) } label: { SchoolEventRow(event: event, showDay: true) } }
                        }
                    }
                }
            }
        }
        .navigationTitle("Знайти у школі")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Листи, справи, події")
    }

    private func searchLetterRow(_ letter: SchoolHubLetter) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(letter.title.isEmpty ? (letter.type == "letter" ? "Лист" : "Повідомлення") : letter.title).font(.subheadline.weight(.semibold)).lineLimit(2)
            Text([letter.sender.isEmpty ? nil : letter.sender, letter.date?.formatted(date: .abbreviated, time: .omitted)].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
        }.frame(minHeight: OrbitSpacing.minTarget, alignment: .leading)
    }

    private func searchTaskRow(_ task: SchoolHubTask) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checklist").foregroundStyle(NovaTodayTokens.coral)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(task.dueAt.flatMap { SchoolHubLogic.dayKey(for: $0, allDay: task.allDay).map(SchoolHubFormat.shortDay) } ?? "Без підтвердженої дати").font(.caption).foregroundStyle(.secondary)
            }
        }.frame(minHeight: OrbitSpacing.minTarget, alignment: .leading)
    }
}

// MARK: - Search

private struct SchoolSearchResultsView: View {
    let store: SchoolHubStore
    let query: String
    var body: some View {
        let letters = SchoolHubLogic.searchLetters(store.letters, query: query)
        let events = SchoolHubLogic.searchEvents(store.hubEvents, query: query)
        let tasks = SchoolHubLogic.searchTasks(store.hubTasks, query: query)
        List {
            Section { SchoolNotice(text: SchoolHubLogic.searchScopeNote + ". Це не пошук по всій школі.", systemImage: "magnifyingglass") }
            if letters.isEmpty && events.isEmpty && tasks.isEmpty {
                ContentUnavailableView.search(text: query)
            }
            if !letters.isEmpty {
                Section { ForEach(letters) { letter in if let item = store.item(id: letter.id) { NavigationLink { SchoolDetailView(item: item) } label: { VStack(alignment: .leading, spacing: 3) { Text(letter.title.isEmpty ? (letter.type == "letter" ? "Лист" : "Повідомлення") : letter.title).font(.headline).lineLimit(2); Text(letter.translation ?? letter.originalText).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }.frame(minHeight: OrbitSpacing.minTarget, alignment: .leading) } } } } header: { SchoolSectionHeader(title: "Листи", systemImage: "envelope", count: letters.count) }
            }
            if !events.isEmpty {
                Section { ForEach(events) { event in if let source = store.calendarEvent(uid: event.uid) { NavigationLink { SchoolEventDetailView(event: source) } label: { SchoolEventRow(event: event, showDay: true) } } } } header: { SchoolSectionHeader(title: "Події", systemImage: "calendar", count: events.count) }
            }
            if !tasks.isEmpty {
                Section { ForEach(tasks) { SchoolTaskRow(store: store, task: $0) } } header: { SchoolSectionHeader(title: "Справи", systemImage: "checklist", count: tasks.count) }
            }
        }
    }
}
