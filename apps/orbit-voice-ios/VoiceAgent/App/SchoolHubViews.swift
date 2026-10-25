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
    var taskCoverage: String?
    var taskCoverageTruncated = false
    var tasksPhase: Phase = .idle
    var actionTasksPhase: Phase = .idle
    var actionTasks: [OrbitSchoolActionTask] = []
    var actionCapability: SchoolActionsCapability = .unknown
    var calendarLinks: [String: String] = [:]
    private(set) var updatingTaskIDs: Set<String> = []
    private(set) var gate = SchoolHubLoadGate()
    #if DEBUG
    private let fixture: Routes05SchoolFixture?
    #endif
    var scopeKey: String? { gate.scopeKey }

    #if DEBUG
    init(fixture: Routes05SchoolFixture? = nil) {
        self.fixture = fixture
        if let fixture {
            items = fixture.items
            events = fixture.events
            canonicalTasks = fixture.tasks
            studentNames = fixture.studentNames
            itemsLoadedOnce = true
            calendarLoadedOnce = true
            tasksLoadedOnce = true
            itemsPhase = .loaded
            calendarPhase = .loaded
            tasksPhase = .loaded
            actionTasksPhase = .loaded
            actionCapability = .unavailable
            taskCoverage = "all"
            gate.reset(to: "routes05-fixture")
        }
    }
    #endif

    func reset(to key: String) {
        gate.reset(to: key)
        items = []; events = []; canonicalTasks = []; actionTasks = []; studentNames = []
        actionCapability = .unknown
        calendarLinks = [:]; updatingTaskIDs = []
        itemsLoadedOnce = false; calendarLoadedOnce = false; tasksLoadedOnce = false; taskCoverage = nil; taskCoverageTruncated = false
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
                return SchoolHubTask(
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
                    sourceType: task.sourceType,
                    sourceExternalId: task.sourceExternalId,
                    actionID: state?.id,
                    status: state?.status ?? task.status ?? "open",
                    planningDate: state?.planningDate,
                    identityStable: task.stableIdentity ?? true,
                    calendarEventId: calendarLinks[task.id] ?? task.calendarEventId
                )
            }
        } else {
            sourceTasks = items.flatMap { item in
                (item.tasks ?? []).compactMap { task -> SchoolHubTask? in
                    guard let title = (task.title ?? task.action), !title.isEmpty else { return nil }
                    guard let key = task.key, !key.isEmpty else { return nil }
                    return SchoolHubTask(id: "\(item.id):\(key)", title: title, action: task.action, dueAt: task.dueAt, allDay: task.allDay ?? true, importance: task.importance, target: task.target, confidence: task.confidence, reason: task.reason, sourceItemId: item.id, sourceType: item.type, sourceExternalId: item.externalId)
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
        #if DEBUG
        if fixture != nil { return }
        #endif
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
            let result = try await MainProductAPI.shared.schoolTasks(coverage: "all")
            guard gate.accepts(token) else { return }
            canonicalTasks = result.tasks
            taskCoverage = result.coverage
            taskCoverageTruncated = result.truncated ?? false
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
            let result = try await MainProductAPI.shared.schoolActionTasks(preserveHTTPStatus: true)
            guard gate.accepts(token) else { return }
            actionTasks = result.tasks
            actionCapability = .available
            actionTasksPhase = .loaded
        } catch is CancellationError {
            guard gate.accepts(token) else { return }
            actionTasksPhase = actionTasks.isEmpty ? .idle : .loaded
        } catch {
            guard gate.accepts(token) else { return }
            actionTasksPhase = .failed
            actionCapability = Self.capability(for: error)
        }
    }

    private static func capability(for error: Error) -> SchoolActionsCapability {
        if let authError = error as? OrbitChatAPIError, case .notPaired = authError {
            return .unauthorized
        }
        return SchoolActionsCapability.from(error: error)
    }

    func setTaskStatus(_ task: SchoolHubTask, completed: Bool) async throws {
        guard actionTasksPhase == .loaded else { throw SchoolHubActionError.unavailable }
        guard task.identityStable else { throw SchoolHubActionError.unstableIdentity }
        guard !updatingTaskIDs.contains(task.id) else { return }
        updatingTaskIDs.insert(task.id)
        defer { updatingTaskIDs.remove(task.id) }
        do {
            let updated: OrbitSchoolActionTask
            if task.kind == "family", let actionID = task.actionID {
                updated = completed ? try await MainProductAPI.shared.completeSchoolActionTask(id: actionID) : try await MainProductAPI.shared.reopenSchoolActionTask(id: actionID)
            } else {
                guard !task.sourceItemId.isEmpty else { return }
                updated = completed ? try await MainProductAPI.shared.completeSourceSchoolTask(itemId: task.sourceItemId, taskKey: task.sourceTaskKey) : try await MainProductAPI.shared.reopenSourceSchoolTask(itemId: task.sourceItemId, taskKey: task.sourceTaskKey)
            }
            actionTasks.removeAll { $0.id == updated.id }
            actionTasks.append(updated)
        } catch {
            // The outcome of a failed request is unknown; re-read the confirmed state instead of guessing.
            if let token = gate.token() { await loadActionTasks(token) }
            throw error
        }
    }

    func isUpdating(_ task: SchoolHubTask) -> Bool { updatingTaskIDs.contains(task.id) }

    func recordCalendarLink(taskID: String, eventID: String?) {
        calendarLinks[taskID] = eventID ?? "created"
    }

    func refreshActionCapability() async {
        guard gate.token() != nil else { return }
        await loadActionTasks(gate.token() ?? 0)
    }

    func createFamilyTask(title: String, description: String, planningDate: String?) async throws {
        _ = try await MainProductAPI.shared.createSchoolActionTask(title: title, description: description, planningDate: planningDate)
        actionTasks = try await MainProductAPI.shared.schoolActionTasks().tasks
    }
}

// MARK: - School Hub v2

fileprivate enum SchoolV2Section: Hashable { case overview, exams, timetable }

private struct SchoolHubV2View: View {
    let studentLabel: String?
    let initialSection: SchoolV2Section
#if DEBUG
    private let debugFixture: Routes05SchoolFixture?
#endif
    @State private var store = SchoolHubV2Store()
    @State private var tab = 0

    init(studentLabel: String?, initialSection: SchoolV2Section = .overview) {
        self.studentLabel = studentLabel
        self.initialSection = initialSection
#if DEBUG
        self.debugFixture = nil
#endif
        _tab = State(initialValue: initialSection == .exams ? 1 : initialSection == .timetable ? 2 : 0)
    }

#if DEBUG
    init(studentLabel: String?, initialSection: SchoolV2Section = .overview, fixture: Routes05SchoolFixture) {
        self.studentLabel = studentLabel
        self.initialSection = initialSection
        self.debugFixture = fixture
        _store = State(initialValue: SchoolHubV2Store(fixture: fixture))
        _tab = State(initialValue: initialSection == .exams ? 1 : initialSection == .timetable ? 2 : 0)
    }
#endif

    var body: some View {
        Group {
            switch store.phase {
            case .loading, .idle: ProgressView("Завантажуємо шкільні дані…")
            case .unauthorized: SchoolV2StateView(title: "Потрібна авторизація", message: "Активуйте цей iPhone для перегляду шкільних даних.", icon: "lock", retry: nil)
            case .forbidden: SchoolV2StateView(title: "Доступ обмежено", message: "Цей профіль не має доступу до шкільного простору.", icon: "hand.raised", retry: nil)
            case .unavailable: SchoolV2StateView(title: "Школа тимчасово недоступна", message: "Спробуйте ще раз пізніше. Синхронізація з провайдером із цього екрана не запускається.", icon: "cloud.slash", retry: reload)
            case .failed: SchoolV2StateView(title: "Не вдалося завантажити", message: "Перевірте з’єднання й повторіть спробу.", icon: "exclamationmark.triangle", retry: reload)
            case .notSynced: content
            case .stale: content
            case .empty: content
            case .ready: content
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: store.weekStart) {
#if DEBUG
            if debugFixture == nil { await store.load() }
#else
            await store.load()
#endif
        }
        .refreshable { await store.load() }
    }

    private var content: some View {
        VStack(spacing: 0) {
            Routes05ContextHeader(
                section: "school",
                eyebrow: initialSection == .exams ? "SCHOOL / UPCOMING" : "WEEK / TIMETABLE",
                title: initialSection == .exams ? "Контрольні.\nСпокійно." : "Розклад\n5F.",
                detail: "Підтверджуйте інформацію джерелом; стан покриття відображається нижче.",
                accent: initialSection == .exams ? Routes05Tokens.lilac : Routes05Tokens.mint
            )
            weekToolbar
            Picker("Розділ", selection: $tab) {
                Text("Огляд").tag(0)
                Text("Іспити").tag(1)
                Text("Розклад").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16).padding(.vertical, 10)
            if let freshness = store.freshness {
                HStack(spacing: 6) {
                    let state = store.coverageState
                    Image(systemName: state == "READY_WITH_DATA" ? "checkmark.circle.fill" : state == "READY_EMPTY" ? "checkmark.circle" : "clock.badge.exclamationmark")
                    Text(state == "READY_WITH_DATA" ? "Дані за тиждень оновлено" : state == "READY_EMPTY" ? "Тиждень перевірено: даних немає" : state == "NOT_SYNCED" ? "Тиждень ще не синхронізовано" : state == "STALE" ? "Дані можуть бути застарілими" : "Дані тимчасово недоступні")
                    if let label = OrbitFreshness.label(from: freshness.observedAt) { Text("· \(label)") }
                    Spacer()
                }
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.bottom, 4)
            }
            switch tab {
            case 1: examsView
            case 2: timetableView
            default: overviewView
            }
        }
        .background(Routes05Tokens.canvas.ignoresSafeArea())
    }

    private var weekToolbar: some View {
        HStack {
            Button { store.shiftWeek(-7) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("Попередній тиждень")
            Spacer()
            Text("\(SchoolHubFormat.shortDay(store.weekStart)) – \(SchoolHubFormat.shortDay(SchoolHubLogic.addDays(6, to: store.weekStart) ?? store.weekStart))")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Button { store.shiftWeek(7) } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel("Наступний тиждень")
        }
        .frame(minHeight: 40).padding(.horizontal, 16)
    }

    private var overviewView: some View {
        List {
            Section {
                Routes05ContextHeader(section: "school", eyebrow: "SCHOOL / OVERVIEW", title: "Школа.\nНа зв’язку.", detail: "Підтверджені дані тижня для активного учнівського профілю.", accent: Routes05Tokens.mint)
            }
            Section {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Шкільний простір").font(.title3.weight(.semibold))
                    Text(studentLabel ?? "Поточний учень")
                        .font(.subheadline).foregroundStyle(.secondary)
                }.padding(.vertical, 6)
            }
            Section("Найближчі іспити") {
                if store.coverageState == "NOT_SYNCED" { Text("Дані за цей тиждень ще не завантажені.").foregroundStyle(.secondary) }
                else if ["PARTIAL", "UNAVAILABLE", "ERROR"].contains(store.coverageState) { Text("Дані за цей тиждень тимчасово недоступні.").foregroundStyle(.secondary) }
                else if store.exams.isEmpty { Text("Іспитів за цей період немає.").foregroundStyle(.secondary) }
                else { ForEach(store.exams) { examRow($0) } }
            }
            Section("Розклад") {
                Button { tab = 2 } label: { Label("Відкрити розклад (\(store.timetable.count) уроків)", systemImage: "calendar") }
            }
            if !(store.overview?.projects.isEmpty ?? true) {
                Section("Проєкти") { Text("Проєкти доступні в окремому оновленні.").foregroundStyle(.secondary) }
            }
        }.listStyle(.insetGrouped)
    }

    private var examsView: some View {
        List {
            if store.coverageState == "NOT_SYNCED" { ContentUnavailableView("Дані за цей тиждень ще не завантажені", systemImage: "clock.badge.exclamationmark", description: Text("Для вибраного тижня ще немає підтвердженої синхронізації.")) }
            else if ["PARTIAL", "UNAVAILABLE", "ERROR"].contains(store.coverageState) { ContentUnavailableView("Дані тимчасово недоступні", systemImage: "cloud.slash", description: Text("Стан синхронізації не підтверджено для цього тижня.")) }
            else if store.exams.isEmpty { ContentUnavailableView("Іспитів немає", systemImage: "checkmark.circle", description: Text("За вибраний період іспитів не знайдено.")) }
            else { ForEach(store.exams) { examRow($0) } }
        }.listStyle(.insetGrouped)
    }

    private var timetableView: some View {
        if store.timetable.isEmpty {
            let unsynced = store.coverageState == "NOT_SYNCED"
            let unavailable = ["PARTIAL", "UNAVAILABLE", "ERROR"].contains(store.coverageState)
            let title = unsynced ? "Дані за цей тиждень ще не завантажені" : unavailable ? "Дані тимчасово недоступні" : store.coverageState == "STALE" ? "Дані можуть бути застарілими" : "На цей тиждень уроків немає"
            let message = unsynced ? "Для вибраного тижня ще немає підтвердженої синхронізації." : unavailable ? "Стан синхронізації не підтверджено для цього тижня." : "За вибраний період уроків не знайдено."
            return AnyView(ContentUnavailableView(title, systemImage: "calendar.badge.exclamationmark", description: Text(message)))
        }

        let days = Array(Set(store.timetable.map(\.dayKey))).sorted()
        let lessonIndexes = Array(Set(store.timetable.map(\.lessonIndex))).sorted()
        return AnyView(ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("УРОК").font(.caption2.weight(.black).monospaced()).frame(width: 56, alignment: .leading)
                    ForEach(days, id: \.self) { day in
                        Text(SchoolHubFormat.shortDay(day).uppercased())
                            .font(.caption2.weight(.black).monospaced())
                            .frame(width: 148, alignment: .leading)
                    }
                }
                .padding(.horizontal, 16)
                ForEach(lessonIndexes, id: \.self) { lessonIndex in
                    HStack(alignment: .top, spacing: 8) {
                        Text(String(format: "%02d", lessonIndex))
                            .font(.headline.monospacedDigit())
                            .frame(width: 56, height: 92, alignment: .topLeading)
                        ForEach(days, id: \.self) { day in
                            if let entry = store.timetable.first(where: { $0.dayKey == day && $0.lessonIndex == lessonIndex }) {
                                Routes05TimetableCell(entry: entry, lessonIndex: lessonIndex)
                            } else {
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(Routes05Tokens.ink.opacity(0.18), lineWidth: 1)
                                    .frame(width: 148, height: 92)
                                    .overlay(Text("—").foregroundStyle(.secondary))
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 12)
            .safeAreaPadding(.horizontal, 0)
        }
        .scrollIndicators(.visible)
        .accessibilityElement(children: .contain))
    }

    private func examRow(_ exam: OrbitSchoolHubV2Exam) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(exam.subject).font(.subheadline.weight(.semibold))
            let details = [SchoolHubFormat.long(exam.dayKey), exam.room, exam.teacher, exam.typeName].compactMap { $0 }.filter { !$0.isEmpty }
            Text(details.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 4).accessibilityElement(children: .combine)
    }

    private func reload() { Task { await store.load() } }
}

private struct SchoolV2StateView: View {
    let title: String; let message: String; let icon: String; let retry: (() -> Void)?
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Routes05ContextHeader(
                    section: "school",
                    eyebrow: "SCHOOL / COVERAGE",
                    title: "Дані школи.\nПід контролем.",
                    detail: "Стан джерела відображається чесно; зовнішні записи залишаються лише для читання.",
                    accent: Routes05Tokens.mint
                )
                ContentUnavailableView { Label(title, systemImage: icon) } description: { Text(message) } actions: {
                    if let retry { Button("Повторити", action: retry).buttonStyle(.bordered) }
                }
                .padding(.vertical, 32)
            }
        }
        .background(Routes05Tokens.canvas)
    }
}

private struct SchoolActionsUnavailableView: View {
    let capability: SchoolActionsCapability
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Сімейні дії недоступні", systemImage: capability == .unavailable ? "lock.slash" : "exclamationmark.triangle")
        } description: {
            Text(capability.message)
        } actions: {
            Button("Перевірити знову", action: retry)
                .buttonStyle(.bordered)
        }
    }
}

private struct SchoolActionHistoryView: View {
    let store: SchoolHubStore
    @State private var phase: SchoolHubStore.Phase = .loading
    @State private var entries: [OrbitSchoolActionHistoryEntry] = []

    var body: some View {
        Group {
            if !store.actionCapability.canMutate {
                List {
                    Section {
                        Routes05ContextHeader(section: "discovery", eyebrow: "AUDIT / FAMILY ACTIONS", title: "Що\nзмінилось?", detail: "Історія лише Orbit-власних дій і підтверджених сервером результатів.", accent: Routes05Tokens.mint)
                    }
                    Section {
                        SchoolActionsUnavailableView(capability: store.actionCapability) { Task { await store.refreshActionCapability() } }
                    }
                }
                .listStyle(.plain)
            } else {
                historyList
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task { if store.actionCapability.canMutate { await reload() } }
        .refreshable { if store.actionCapability.canMutate { await reload() } }
    }

    private var historyList: some View {
        List {
            Section {
                Routes05ContextHeader(section: "discovery", eyebrow: "AUDIT / FAMILY ACTIONS", title: "Що\nзмінилось?", detail: "Історія лише Orbit-власних дій і підтверджених сервером результатів.", accent: Routes05Tokens.mint)
            }
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
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = SchoolHubLogic.schoolTimeZone
        let weekday = calendar.component(.weekday, from: date)
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        let weekdays = ["неділя", "понеділок", "вівторок", "середа", "четвер", "п’ятниця", "субота"]
        let months = ["січня", "лютого", "березня", "квітня", "травня", "червня", "липня", "серпня", "вересня", "жовтня", "листопада", "грудня"]
        guard (1...7).contains(weekday), (1...12).contains(month) else { return formatter("EEEE, d MMMM").string(from: date) }
        return "\(weekdays[weekday - 1]), \(day) \(months[month - 1])"
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

private struct Routes05TimetableCell: View {
    let entry: OrbitSchoolHubV2TimetableEntry
    let lessonIndex: Int

    private var fill: Color {
        [Routes05Tokens.blue, Routes05Tokens.mint, Routes05Tokens.lilac, Routes05Tokens.yellow, Routes05Tokens.orange][(lessonIndex - 1) % 5]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(entry.subject)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Routes05Tokens.accentInk)
                .lineLimit(2)
            Text([entry.startsAtLocal ?? entry.startsAt, entry.room, entry.teacher].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Routes05Tokens.accentInk.opacity(0.78))
                .lineLimit(3)
            if entry.isCancelled {
                Label("Скасовано", systemImage: "xmark.circle")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Routes05Tokens.accentInk)
            }
        }
        .frame(width: 148, height: 92, alignment: .topLeading)
        .padding(10)
        .background(fill)
        .overlay(Rectangle().stroke(Routes05Tokens.ink, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Урок \(lessonIndex), \(entry.subject)")
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
@MainActor @Observable
final class SchoolHubV2Store {
    enum Phase: Equatable { case idle, loading, ready, empty, notSynced, stale, unavailable, unauthorized, forbidden, failed }
    var phase: Phase = .idle
    var overview: OrbitSchoolHubV2Overview?
    var exams: [OrbitSchoolHubV2Exam] = []
    var timetable: [OrbitSchoolHubV2TimetableEntry] = []
    var freshness: OrbitSchoolHubV2Freshness?
    var coverageState: String = "NOT_SYNCED"
    var weekStart: String = SchoolHubV2Store.currentWeekStart()
    var errorText: String?
    var weekEnd: String { SchoolHubLogic.addDays(7, to: weekStart) ?? weekStart }

    init() {}

#if DEBUG
    init(fixture: Routes05SchoolFixture) {
        let observed = Date(timeIntervalSince1970: 1_729_555_200)
        let freshness = OrbitSchoolHubV2Freshness(state: "READY_WITH_DATA", sourceStates: ["schulmanager": "READY"], observedAt: observed, source: "schulmanager", fingerprint: "routes05")
        let coverage = OrbitSchoolHubV2Coverage(state: "READY_WITH_DATA", rowCount: 2, sourceStatus: "READY", sourceFingerprint: "routes05", successfulSyncAt: observed, observedAt: observed, errorCode: nil, startDayKey: "2026-10-19", endDayKey: "2026-10-25")
        let exam = OrbitSchoolHubV2Exam(id: "routes05-exam", subject: "Deutsch", dayKey: "2026-10-24", lessonStart: 3, lessonEnd: 4, startsAt: "2026-10-24T10:00:00+02:00", room: "5F", teacher: "M. Bauer", group: nil, groupName: nil, startClassHourNumber: 3, typeName: "Klassenarbeit", typeColor: "#C9B8FF", typeVisibleForStudents: true, comment: "Projektwoche", status: "upcoming", source: "schulmanager", sourceFingerprint: "routes05", observedAt: observed)
        let lessonDays = ["2026-10-19", "2026-10-20", "2026-10-21", "2026-10-22", "2026-10-23"]
        let subjects = ["Deutsch", "Mathematik", "Sport", "Englisch", "Biologie"]
        let lessons = lessonDays.enumerated().map { index, day in
            OrbitSchoolHubV2TimetableEntry(id: "routes05-lesson-\(index)", dayKey: day, localDate: day, lessonIndex: index + 1, subject: subjects[index], teacher: "M. Bauer", room: "5F", group: nil, groupName: nil, startsAt: "\(day)T08:00:00+02:00", endsAt: "\(day)T08:45:00+02:00", startsAtLocal: String(format: "%02d:00", 8 + index), endsAtLocal: String(format: "%02d:45", 8 + index), classHourNumber: index + 1, isCancelled: false, originalLessonCount: 1, teachers: [OrbitSchoolHubV2Teacher(abbreviation: "MB")], groups: [OrbitSchoolHubV2Group(name: "5F")], status: "scheduled", kind: "lesson", source: "schulmanager", sourceFingerprint: "routes05", observedAt: observed)
        }
        overview = OrbitSchoolHubV2Overview(state: "READY", freshness: freshness, sourceStates: ["schulmanager": "READY"], profileTitle: fixture.studentNames.first, todayDayKey: "2026-10-24", upcomingExams: [exam], projects: [], coverage: ["timetable": coverage, "exams": coverage])
        exams = [exam]
        timetable = lessons
        self.freshness = freshness
        coverageState = "READY_WITH_DATA"
        phase = .ready
    }
#endif

    func load() async {
        phase = .loading; errorText = nil
        do {
            async let overviewResult = MainProductAPI.shared.schoolOverview(start: weekStart, end: weekEnd)
            async let examsResult = MainProductAPI.shared.schoolExams(from: weekStart, to: weekEnd)
            async let timetableResult = MainProductAPI.shared.schoolTimetable(from: weekStart, to: weekEnd)
            let (overviewResponse, examsResponse, timetableResponse) = try await (overviewResult, examsResult, timetableResult)
            overview = overviewResponse.overview
            exams = examsResponse.exams
            timetable = timetableResponse.timetable.entries.sorted { lhs, rhs in
                if lhs.dayKey != rhs.dayKey { return lhs.dayKey < rhs.dayKey }
                if lhs.lessonIndex != rhs.lessonIndex { return lhs.lessonIndex < rhs.lessonIndex }
                return lhs.id < rhs.id
            }
            freshness = overviewResponse.overview.freshness
            let states = [examsResponse.coverage?.state, timetableResponse.timetable.coverage?.state].compactMap { $0 }
            coverageState = states.first(where: { ["PARTIAL", "UNAVAILABLE", "ERROR"].contains($0) }) ?? (states.contains("STALE") ? "STALE" : states.contains("READY_WITH_DATA") ? "READY_WITH_DATA" : states.contains("READY_EMPTY") ? "READY_EMPTY" : "NOT_SYNCED")
            switch coverageState {
            case "NOT_SYNCED": phase = .notSynced
            case "STALE": phase = .stale
            case "READY_EMPTY": phase = .empty
            default: phase = .ready
            }
        } catch is CancellationError {
            if phase == .loading { phase = .idle }
        } catch let failure as OrbitHTTPResponseFailure {
            switch failure.status { case 401: phase = .unauthorized; case 403: phase = .forbidden; case 503: phase = .unavailable; default: phase = .failed }
            errorText = failure.code
        } catch {
            phase = .failed; errorText = error.localizedDescription
        }
    }

    func shiftWeek(_ days: Int) { weekStart = SchoolHubLogic.addDays(days, to: weekStart) ?? weekStart }

    private static func currentWeekStart() -> String {
        let calendar = Calendar(identifier: .iso8601)
        let today = SchoolHubLogic.dayKey(of: Date())
        guard let date = SchoolHubLogic.date(fromDayKey: today), let monday = calendar.dateInterval(of: .weekOfYear, for: date)?.start else { return today }
        return SchoolHubLogic.dayKey(of: monday)
    }
}

struct SchoolHubView: View {
    fileprivate enum Route: Hashable { case inbox, tasks, calendar, timeline, search, briefing, brain, teams, history, notes(String, String), v2(SchoolV2Section), letter(String), event(String) }

    @State private var store = SchoolHubStore()
    @State private var path: [Route] = []
    @EnvironmentObject private var authentication: OrbitAuthentication

    #if DEBUG
    private let fixture: Routes05SchoolFixture?
    private let initialDebugRoute: String?
    init(fixture: Routes05SchoolFixture? = nil, initialDebugRoute: String? = nil) {
        self.fixture = fixture
        self.initialDebugRoute = initialDebugRoute
        _store = State(initialValue: SchoolHubStore(fixture: fixture))
        _path = State(initialValue: Self.debugPath(initialDebugRoute))
    }

    private static func debugPath(_ value: String?) -> [Route] {
        switch value {
        case "inbox": return [.inbox]
        case "letter": return [.letter("routes05-letter")]
        case "tasks": return [.tasks]
        case "timetable": return [.v2(.timetable)]
        case "exams": return [.v2(.exams)]
        case "brain": return [.brain]
        case "calendar": return [.calendar]
        case "search": return [.search]
        case "timeline": return [.timeline]
        case "briefing": return [.briefing]
        case "notes": return [.notes("task", "routes05-task")]
        case "history": return [.history]
        default: return []
        }
    }
    #endif

    private var scopeKey: String {
        SchoolHubLoadGate.scopeKey(personId: authentication.personId, impersonating: authentication.impersonating)
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                #if DEBUG
                if fixture != nil || store.scopeKey == scopeKey {
                    SchoolCommandCenter(store: store, open: { path.append($0) })
                } else {
                    ProgressView("Завантаження школи…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(NovaTodayTokens.canvas)
                }
                #else
                if store.scopeKey == scopeKey {
                    SchoolCommandCenter(store: store, open: { path.append($0) })
                } else {
                    ProgressView("Завантаження школи…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(NovaTodayTokens.canvas)
                }
                #endif
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                // SchoolHubView owns the navigation stack for this route. The inbox
                // must render its list directly so its letter links stay in the same
                // Route path and SwiftUI never compares nested path element types.
                case .inbox:
                    #if DEBUG
                    SchoolInboxView(embeddedInNavigation: true, hubMode: true, fixture: fixture).routes05ContextSurface()
                    #else
                    SchoolInboxView(embeddedInNavigation: true, hubMode: true).routes05ContextSurface()
                    #endif
                case .tasks: Routes05SchoolTasksProductionView(store: store).routes05ContextSurface()
                case .calendar: SchoolWeekCalendarView(store: store).routes05ContextSurface()
                case .timeline: SchoolTimelineView(store: store).routes05ContextSurface()
                case .search: SchoolUnifiedSearchView(store: store).routes05ContextSurface()
#if DEBUG
                case .briefing: SchoolTasksView(fixture: fixture ?? Routes05DebugFixtures.school).routes05ContextSurface()
                case .brain: SchoolBrainView(fixture: fixture ?? Routes05DebugFixtures.school).routes05ContextSurface()
#else
                case .briefing: SchoolTasksView().routes05ContextSurface()
                case .brain: SchoolBrainView().routes05ContextSurface()
#endif
                case .teams: SchoolTeamsFutureView()
                case .history: SchoolActionHistoryView(store: store).routes05ContextSurface()
                case let .notes(entityType, entityId): SchoolNotesView(store: store, entityType: entityType, entityId: entityId).routes05ContextSurface()
                case let .v2(section):
                    if section == .timetable {
#if DEBUG
                        if let fixture { Routes05SchoolTimetableProductionView(studentLabel: store.studentNames.first, fixture: fixture).routes05ContextSurface() }
                        else { Routes05SchoolTimetableProductionView(studentLabel: store.studentNames.first).routes05ContextSurface() }
#else
                        Routes05SchoolTimetableProductionView(studentLabel: store.studentNames.first).routes05ContextSurface()
#endif
                    } else {
#if DEBUG
                        if let fixture { SchoolHubV2View(studentLabel: store.studentNames.first, initialSection: section, fixture: fixture).routes05ContextSurface() }
                        else { SchoolHubV2View(studentLabel: store.studentNames.first, initialSection: section).routes05ContextSurface() }
#else
                        SchoolHubV2View(studentLabel: store.studentNames.first, initialSection: section).routes05ContextSurface()
#endif
                    }
                case let .letter(id):
                    #if DEBUG
                    if let item = fixture?.items.first(where: { $0.id == id }) { SchoolDetailView(item: item) }
                    else { SchoolDetailLoaderView(itemID: id) }
                    #else
                    SchoolDetailLoaderView(itemID: id)
                    #endif
                case let .event(id):
                    if let event = store.calendarEvent(uid: id) { SchoolEventDetailView(event: event) }
                    else { ContentUnavailableView("Подія недоступна", systemImage: "calendar.badge.exclamationmark") }
                }
            }
        }
        .task(id: scopeKey) {
            #if DEBUG
            if fixture != nil { return }
            #endif
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
    private var unread: Int { store.letters.filter(\.unread).count }
    private var priorities: [SchoolHomePriority] {
        SchoolHubLogic.homePriorities(
            tasks: store.openHubTasks,
            letters: store.letters,
            events: store.hubEvents,
            today: today,
            sourceDates: store.sourceDates,
            now: now,
            actionsAvailable: store.actionCapability.canMutate
        )
    }
    private var recentMessages: [SchoolHubLetter] { SchoolHubLogic.recentUnreadLetters(store.letters) }
    private var upcomingEvents: [SchoolHubEvent] { SchoolHubLogic.homeUpcomingEvents(store.hubEvents, today: today) }
    private var hasOverduePriority: Bool { priorities.contains { $0.detail.hasPrefix("Прострочено") } }

    var body: some View {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                Routes05Mast(section: "school") { open(.search) }
                routesHeader
                if store.itemsPhase == .failed || store.calendarPhase == .failed || store.tasksPhase == .failed { availabilityNotice }
                routesGrid
                routesAttention
                routesUpcoming
                        routesAsk
                    }
                    .padding(.bottom, 120)
                }
                .safeAreaPadding(.bottom, 96)
                .onAppear {
                    guard Routes05DebugCapture.scrollToBottom else { return }
                    DispatchQueue.main.async {
                        proxy.scrollTo("routes05-school-brain", anchor: .center)
                    }
                }
        }
        .background(Routes05Tokens.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await store.load() }
    }

    private var routesHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("SOURCE / SCHULMANAGER · READ ONLY")
                    .font(.system(size: 10, weight: .black, design: .monospaced)).tracking(1.2)
                    .foregroundStyle(Routes05Tokens.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(2)
                Text("Школа.\nНа зв’язку.")
                    .font(.system(.largeTitle, design: .rounded).weight(.black)).tracking(-1.8).lineSpacing(-4)
                Text("Профіль учня · події, листи й підготовка.")
                    .font(.footnote.weight(.medium)).foregroundStyle(Routes05Tokens.secondary)
                    .lineLimit(2)
                if !store.studentNames.isEmpty {
                    Text(store.studentNames.joined(separator: " · ")).font(.subheadline.weight(.bold))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("↗").font(.system(size: 29, weight: .black)).foregroundStyle(Routes05Tokens.accentInk)
                .frame(width: 59, height: 59).background(Routes05Tokens.mint, in: Circle())
                .overlay(Circle().stroke(Routes05Tokens.ink, lineWidth: 2))
                .layoutPriority(1)
        }
        .padding(.horizontal, 16).padding(.top, 12)
    }

    private var routesGrid: some View {
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)], spacing: 9) {
            Routes05FilledTile(title: "Вхідні", detail: unread == 0 ? "Усе прочитано" : "\(unread) нові", icon: "arrow.down.left", tint: Routes05Tokens.blue) { open(.inbox) }
            Routes05FilledTile(title: "Справи", detail: tasksQuickDetail, icon: "square", tint: Routes05Tokens.orange) { open(.tasks) }
            Routes05FilledTile(title: "Розклад", detail: "Відкрити огляд", icon: "list.bullet.rectangle", tint: Routes05Tokens.mint) { open(.v2(.timetable)) }
            Routes05FilledTile(title: "Іспити", detail: "Відкрити огляд", icon: "circle", tint: Routes05Tokens.lilac) { open(.v2(.exams)) }
        }
        .padding(.horizontal, 16)
    }

    private var routesAttention: some View {
        VStack(alignment: .leading, spacing: 8) {
            Routes05SectionHeader("Потребує уваги", action: "Усі справи") { open(.tasks) }
            if let item = priorities.first {
                Button { open(priority: item) } label: {
                    HStack(spacing: 0) {
                        Text("!").font(.system(size: 38, weight: .black)).foregroundStyle(Routes05Tokens.accentInk).frame(width: 88).frame(minHeight: 86).background(Routes05Tokens.yellow)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title).font(.headline.weight(.black)).lineLimit(2)
                            Text(priorityDetail(item)).font(.caption).foregroundStyle(Routes05Tokens.secondary).lineLimit(2)
                            Text(item.detail.hasPrefix("Прострочено") ? "ДЛЯ РОДИНИ" : "УВАГА")
                                .font(.caption2.weight(.black)).padding(.horizontal, 8).padding(.vertical, 4).background(Routes05Tokens.orange)
                        }.padding(10)
                        Spacer(minLength: 0)
                    }
                    .background(Routes05Tokens.surface).overlay(RoundedRectangle(cornerRadius: 3).stroke(Routes05Tokens.ink, lineWidth: 1))
                }.buttonStyle(.plain)
            } else { Routes05StateRow(text: "Немає термінових справ або нових важливих повідомлень.", tint: Routes05Tokens.yellow) }
        }.padding(.horizontal, 16)
    }

    private var routesUpcoming: some View {
        VStack(alignment: .leading, spacing: 8) {
            Routes05SectionHeader("Найближче", action: "Всі дати") { open(.calendar) }
            if upcomingEvents.isEmpty { Routes05StateRow(text: "Найближчих шкільних подій немає.", tint: Routes05Tokens.mint) }
            else {
                ForEach(Array(upcomingEvents.prefix(3).enumerated()), id: \.element.uid) { index, event in
                    Routes05IndexedRow(index: eventDay(event), tint: index.isMultiple(of: 2) ? Routes05Tokens.orange : Routes05Tokens.mint) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(event.title).font(.subheadline.weight(.bold)).lineLimit(2)
                            Text(eventSummary(event)).font(.caption).foregroundStyle(Routes05Tokens.secondary)
                        }
                    }
                }
            }
        }.padding(.horizontal, 16)
    }

    private var routesAsk: some View {
        Button { open(.brain) } label: {
            HStack { Text("Запитати про школу").font(.headline.weight(.black)); Spacer(); Text("Пошук і хронологія →").font(.caption.weight(.bold)).foregroundStyle(Routes05Tokens.blue) }
                .foregroundStyle(Routes05Tokens.ink).frame(minHeight: 52).padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
        .id("routes05-school-brain")
        .accessibilityIdentifier("routes05-school-brain")
    }

    private var schoolHubV2Section: some View {
        Button { open(.v2(.overview)) } label: {
            HStack(spacing: 12) {
                Image(systemName: "graduationcap.fill").font(.title3).foregroundStyle(NovaTodayTokens.teal)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Школа · огляд, іспити й розклад").font(.subheadline.weight(.semibold))
                    Text("Дані Schulmanager v2").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(); Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            }
            .padding(14).background(NovaTodayTokens.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Відкрити огляд шкільних даних")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Routes05Chapter("SCHOOL / SOURCE", title: "Школа.", detail: "Schulmanager · лише читання", accent: Routes05Tokens.mint)
            if !store.studentNames.isEmpty {
                Text(store.studentNames.count == 1 ? store.studentNames[0] : store.studentNames.joined(separator: " · "))
                    .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var availabilityNotice: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "clock.badge.exclamationmark").foregroundStyle(.orange)
            Text("Частину шкільних даних не вдалося оновити. Показано те, що вже завантажено.")
                .font(.footnote).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Button("Повторити") { Task { await store.load() } }.font(.footnote.weight(.semibold))
        }
        .accessibilityElement(children: .combine)
    }

    private var prioritySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Потребує уваги")
            if priorities.isEmpty && isInitiallyLoading {
                compactLoading("Завантажуємо важливі шкільні справи…")
            } else if priorities.isEmpty {
                Label("Немає термінових справ або нових важливих повідомлень.", systemImage: "checkmark.circle")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(minHeight: OrbitSpacing.minTarget, alignment: .leading)
            } else {
                NovaSurface(tint: hasOverduePriority ? NovaTodayTokens.coral : NovaTodayTokens.teal) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(priorities.enumerated()), id: \.element.id) { index, item in
                            Button { open(priority: item) } label: { priorityRow(item) }
                                .buttonStyle(.plain)
                            if index < priorities.count - 1 { Divider().padding(.vertical, 8) }
                        }
                    }
                }
            }
        }
    }

    private var quickAccessSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Швидкий доступ")
            HStack(spacing: 10) {
                quickAccess("Вхідні", detail: inboxQuickDetail, icon: "envelope", route: .inbox)
                quickAccess("Завдання", detail: tasksQuickDetail, icon: "checklist", route: .tasks)
                quickAccess("Календар", detail: calendarQuickDetail, icon: "calendar", route: .calendar)
            }
            if !store.actionCapability.canMutate, store.actionCapability != .unknown {
                Text(store.actionCapability.message)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var messagesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Нові повідомлення", actionTitle: "Усі повідомлення") { open(.inbox) }
            if recentMessages.isEmpty && store.itemsPhase == .loading && !store.itemsLoadedOnce {
                compactLoading("Завантажуємо повідомлення…")
            } else if recentMessages.isEmpty {
                compactEmpty("Нових повідомлень немає.", icon: "envelope.open")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recentMessages.enumerated()), id: \.element.id) { index, message in
                        Button { open(.letter(message.id)) } label: { messageRow(message) }
                            .buttonStyle(.plain)
                        if index < recentMessages.count - 1 { Divider().padding(.leading, 34) }
                    }
                }
                .padding(.horizontal, 14)
                .background(NovaTodayTokens.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Найближчі події", actionTitle: "Календар") { open(.calendar) }
            if upcomingEvents.isEmpty && store.calendarPhase == .loading && !store.calendarLoadedOnce {
                compactLoading("Завантажуємо події…")
            } else if upcomingEvents.isEmpty {
                compactEmpty("Найближчих шкільних подій немає.", icon: "calendar.badge.checkmark")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(upcomingEvents.enumerated()), id: \.element.uid) { index, event in
                        Button { open(.event(event.uid)) } label: { eventRow(event) }
                            .buttonStyle(.plain)
                        if index < upcomingEvents.count - 1 { Divider().padding(.leading, 42) }
                    }
                }
                .padding(.horizontal, 14)
                .background(NovaTodayTokens.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private var assistantEntry: some View {
        Button { open(.brain) } label: {
            HStack(spacing: 10) {
                Image(systemName: "bubble.left.and.text.bubble.right").foregroundStyle(NovaTodayTokens.indigo)
                Text("Запитати Orbit про школу").font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .frame(minHeight: OrbitSpacing.minTarget)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Запитати Orbit про школу")
    }

    private func quickAccess(_ title: String, detail: String, icon: String, route: SchoolHubView.Route) -> some View {
        Button { open(route) } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon).font(.subheadline.weight(.semibold)).foregroundStyle(NovaTodayTokens.teal)
                Text(title).font(.footnote.weight(.bold)).foregroundStyle(.primary)
                Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading).padding(10)
            .background(NovaTodayTokens.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func priorityRow(_ item: SchoolHomePriority) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: priorityIcon(item)).foregroundStyle(priorityTint(item)).frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(priorityDetail(item)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .frame(minHeight: OrbitSpacing.minTarget, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func messageRow(_ message: SchoolHubLetter) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: message.type == "letter" ? "envelope.fill" : "bubble.left.fill")
                .foregroundStyle(NovaTodayTokens.teal).frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(message.title.isEmpty ? "Повідомлення зі школи" : message.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text([message.sender, message.date.map { SchoolHubFormat.shortDay(SchoolHubLogic.dayKey(of: $0)) }].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if let preview = messagePreview(message), !preview.isEmpty {
                    Text(preview).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 12)
        .frame(minHeight: OrbitSpacing.minTarget, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Нове повідомлення: \(message.title)")
    }

    private func eventRow(_ event: SchoolHubEvent) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 2) {
                Text(eventDay(event)).font(.headline.weight(.bold))
                Text(eventMonth(event)).font(.caption2.weight(.bold)).foregroundStyle(NovaTodayTokens.indigo)
            }
            .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(eventSummary(event)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 12)
        .frame(minHeight: OrbitSpacing.minTarget, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var calendarQuickDetail: String {
        if store.calendarPhase == .loading && !store.calendarLoadedOnce { return "Завантаження…" }
        if store.calendarPhase == .failed && !store.calendarLoadedOnce { return "Дані недоступні" }
        guard let event = upcomingEvents.first, let key = eventKey(event) else { return "Немає подій" }
        return SchoolHubFormat.shortDay(key)
    }

    private var inboxQuickDetail: String {
        if store.itemsPhase == .loading && !store.itemsLoadedOnce { return "Завантаження…" }
        if store.itemsPhase == .failed && !store.itemsLoadedOnce { return "Дані недоступні" }
        return unread == 0 ? "Усе прочитано" : "\(unread) нових"
    }

    private var tasksQuickDetail: String {
        let openCount = SchoolHubLogic.taskCounts(store.hubTasks).open
        if openCount > 0 { return "\(openCount) відкритих" }
        if store.tasksPhase == .loading && !store.tasksLoadedOnce && store.itemsPhase == .loading && !store.itemsLoadedOnce { return "Завантаження…" }
        if store.tasksPhase == .failed && !store.itemsLoadedOnce { return "Дані недоступні" }
        return "Немає відкритих"
    }

    private var isInitiallyLoading: Bool {
        store.itemsPhase == .loading && !store.itemsLoadedOnce &&
        store.calendarPhase == .loading && !store.calendarLoadedOnce &&
        store.tasksPhase == .loading && !store.tasksLoadedOnce
    }

    private func sectionHeader(_ title: String, actionTitle: String? = nil, action: (() -> Void)? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.weight(.bold)).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let actionTitle, let action { Button(actionTitle, action: action).font(.footnote.weight(.semibold)) }
        }
    }

    private func compactEmpty(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: OrbitSpacing.minTarget, alignment: .leading)
    }

    private func compactLoading(_ title: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
            Text(title)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: OrbitSpacing.minTarget, alignment: .leading)
    }

    private func open(priority: SchoolHomePriority) {
        switch priority.kind {
        case .task: open(.tasks)
        case .message: if let id = priority.messageID { open(.letter(id)) }
        case .event: if let id = priority.eventUID { open(.event(id)) }
        }
    }

    private func priorityIcon(_ item: SchoolHomePriority) -> String {
        switch item.kind {
        case .task: item.detail.hasPrefix("Прострочено") ? "exclamationmark.circle.fill" : "checklist"
        case .message: "envelope.badge"
        case .event: "calendar"
        }
    }

    private func priorityTint(_ item: SchoolHomePriority) -> Color {
        item.detail.hasPrefix("Прострочено") ? NovaTodayTokens.coral : NovaTodayTokens.teal
    }

    private func priorityDetail(_ item: SchoolHomePriority) -> String {
        let pieces = item.detail.split(separator: "·", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
        guard item.kind == .task, let value = pieces.first else { return item.detail }
        if value.hasPrefix("Термін:"), let key = value.split(separator: ":", maxSplits: 1).last.map({ String($0).trimmingCharacters(in: .whitespaces) }) {
            let source = pieces.count > 1 ? " · \(pieces[1])" : ""
            return "Термін: \(SchoolHubFormat.shortDay(key))\(source)"
        }
        return item.detail
    }

    private func messagePreview(_ message: SchoolHubLetter) -> String? {
        let text = message.translation ?? message.originalText
        let compact = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return compact.isEmpty ? nil : compact
    }

    private func eventKey(_ event: SchoolHubEvent) -> String? { SchoolHubLogic.dayKey(for: event.startsAt, allDay: event.allDay) }
    private func eventDay(_ event: SchoolHubEvent) -> String { eventKey(event).map(SchoolHubFormat.dayNumber) ?? "—" }
    private func eventMonth(_ event: SchoolHubEvent) -> String { eventKey(event).map(SchoolHubFormat.month) ?? "" }
    private func eventSummary(_ event: SchoolHubEvent) -> String {
        guard let start = eventKey(event) else { return SchoolHubFormat.time(event) }
        if event.allDay, let end = SchoolHubLogic.dayKey(for: event.endsAt, allDay: event.allDay), end != start {
            return "\(SchoolHubFormat.shortDay(start)) – \(SchoolHubFormat.shortDay(end)) · увесь день"
        }
        return SchoolHubFormat.time(event)
    }
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
            taskPreviewSection(tasks: tasks)
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
        if store.itemsPhase == .failed || store.calendarPhase == .failed || store.tasksPhase == .failed || store.actionTasksPhase == .failed {
            Section {
                SchoolNotice(text: staleText, systemImage: "exclamationmark.triangle.fill")
                Button("Повторити") { Task { await store.load() } }.frame(minHeight: OrbitSpacing.minTarget)
            }
        } else if store.itemsPhase == .loading && !store.itemsLoadedOnce {
            Section { ProgressView("Завантажуємо школу…").frame(maxWidth: .infinity) }
        } else if store.taskCoverageTruncated {
            Section { SchoolNotice(text: "Показано перші 2 000 шкільних справ; відкрийте пошук або історію пізніше для решти записів.", systemImage: "exclamationmark.triangle") }
        } else if store.taskCoverage != nil && store.taskCoverage != "all" {
            Section { SchoolNotice(text: "Показано обмежене вікно шкільних справ; частина далеких або безстрокових записів може бути поза ним.", systemImage: "calendar.badge.exclamationmark") }
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

    private func taskPreviewSection(tasks: [SchoolHubTask]) -> some View {
        let openTasks = tasks.filter { $0.status != "completed" }
        let preview = openTasks.sorted { lhs, rhs in
            let left = SchoolHubLogic.dayKey(for: lhs.dueAt, allDay: lhs.allDay) ?? "9999-99-99"
            let right = SchoolHubLogic.dayKey(for: rhs.dueAt, allDay: rhs.allDay) ?? "9999-99-99"
            return left != right ? left < right : lhs.id < rhs.id
        }.prefix(3)
        return Section {
            if store.tasksPhase == .failed && !store.tasksLoadedOnce {
                SchoolNotice(text: "Справи не вдалося завантажити — нуль не означає, що справ немає.", systemImage: "exclamationmark.triangle")
            } else if preview.isEmpty {
                SchoolNotice(text: store.tasksPhase == .loaded ? "Відкритих справ немає." : "Справи ще завантажуються.", systemImage: "checkmark.circle")
            } else {
                ForEach(Array(preview)) { task in
                    SchoolTaskRow(store: store, task: task, today: today)
                }
            }
        } header: {
            SchoolSectionHeader(title: "Шкільні справи", count: openTasks.count, linkTitle: "Усі справи") { navigate(.tasks) }
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
    @State private var showCalendar = false
    @State private var pendingStatusChange: SchoolTaskStatusConfirmation?

    var body: some View {
        let item = store.item(id: task.sourceItemId)
        let evidence = SchoolHubLogic.evidence(forTask: task, sourceLoaded: item != nil, activeNames: store.studentNames, sourceText: item?.originalPlainText ?? item?.originalGerman ?? "")
        let dueKey = SchoolHubLogic.dayKey(for: task.dueAt, allDay: task.allDay)
        let days = dueKey.flatMap { SchoolHubFormat.daysFrom(today, to: $0) }
        let warn = overdue || (days.map { $0 <= 2 } ?? false)
        let updating = store.isUpdating(task)
        let row = HStack(alignment: .center, spacing: 10) {
            Button {
                toggleStatus()
            } label: {
                Image(systemName: task.status == "completed" ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.status == "completed" ? NovaTodayTokens.teal : Color.secondary.opacity(0.8))
                    .frame(width: 44, height: 44)
                    .overlay { if updating { ProgressView().tint(NovaTodayTokens.teal) } }
            }
            .buttonStyle(.plain)
            .disabled(updating || !task.identityStable || !store.actionCapability.canMutate)
            .accessibilityLabel(task.status == "completed" ? "Повернути справу у відкриті" : "Позначити справу виконаною")
            .accessibilityValue(updating ? "Зберігається" : (task.status == "completed" ? "Виконано" : "Відкрито"))
            .accessibilityHint("Подвійне натискання змінює стан справи")
            NavigationLink { SchoolTaskDetailView(store: store, task: task) } label: {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(task.title).font(.callout.weight(.medium)).lineLimit(2)
                            SchoolTrustGlyph(evidence: evidence)
                        }
                        metaLine(dueKey: dueKey, days: days, warn: warn, item: item, evidence: evidence)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.title)
            .accessibilityValue("\(task.status == "completed" ? "Виконано" : "Відкрито")\(task.calendarEventId != nil ? ", є в календарі" : "")")
        }
        .frame(minHeight: 56, alignment: .leading)
        row
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if store.actionTasksPhase == .loaded && task.identityStable {
                Button {
                    toggleStatus()
                } label: {
                    Label(task.status == "completed" ? "Відкрити" : "Готово", systemImage: task.status == "completed" ? "arrow.uturn.backward" : "checkmark")
                }.tint(task.status == "completed" ? .orange : NovaTodayTokens.teal)
                }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                if task.canAddToCalendar && task.calendarEventId == nil {
                    Button { showCalendar = true } label: { Label("До календаря", systemImage: "calendar.badge.plus") }.tint(NovaTodayTokens.indigo)
                }
            }
            .contextMenu {
                if task.canAddToCalendar && task.calendarEventId == nil {
                    Button { showCalendar = true } label: { Label("Додати до календаря", systemImage: "calendar.badge.plus") }
                }
            }
            .sheet(isPresented: $showCalendar) { SchoolTaskCalendarSheet(store: store, task: task) }
            .confirmationDialog(
                pendingStatusChange?.title ?? "Змінити стан справи?",
                isPresented: Binding(get: { pendingStatusChange != nil }, set: { if !$0 { pendingStatusChange = nil } }),
                titleVisibility: .visible
            ) {
                if let pendingStatusChange {
                    Button(pendingStatusChange.actionTitle) { confirmStatusChange(pendingStatusChange) }
                }
                Button("Скасувати", role: .cancel) { pendingStatusChange = nil }
            } message: {
                Text(task.title)
            }
            .alert("Стан справи", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("Гаразд") { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
    }

    private func toggleStatus() {
        guard !store.isUpdating(task), task.identityStable, store.actionCapability.canMutate else { return }
        pendingStatusChange = SchoolTaskStatusConfirmation(completed: task.status == "completed")
    }

    private func confirmStatusChange(_ confirmation: SchoolTaskStatusConfirmation) {
        guard !store.isUpdating(task), task.identityStable, store.actionCapability.canMutate else { return }
        pendingStatusChange = nil
        let completed = confirmation == .complete
        Task {
            do { try await store.setTaskStatus(task, completed: completed) }
            catch { actionError = "Не вдалося зберегти стан справи. Перевірте з’єднання й повторіть." }
        }
    }

    private func metaLine(dueKey: String?, days: Int?, warn: Bool, item: OrbitSchoolItem?, evidence: SchoolEvidence) -> some View {
        var due = "Без дати"
        if let dueKey {
            due = SchoolHubFormat.shortDay(dueKey)
            if let days { due += " · " + SchoolHubFormat.relative(days) }
        }
        var rest: [String] = [task.provenanceLabel]
        if task.isHighPriority { rest.append("важливо") }
        if let target = task.target, !target.isEmpty { rest.append(target) }
        if task.calendarEventId != nil { rest.append("у календарі") }
        if evidence == .needsVerification { rest.append("перевірити") }
        let dueColor: Color = overdue ? .red : (warn ? Color(red: 0.70, green: 0.42, blue: 0.0) : .secondary)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: dueKey == nil ? "calendar.badge.questionmark" : (overdue ? "clock.badge.exclamationmark" : "calendar"))
                    .foregroundStyle(dueColor)
                    .accessibilityHidden(true)
                Text(due)
                    .foregroundStyle(dueColor)
                    .fontWeight(warn ? .semibold : .regular)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            if !rest.isEmpty {
                Text(rest.joined(separator: " · "))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.caption2)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SchoolTaskDetailView: View {
    let store: SchoolHubStore
    let task: SchoolHubTask
    @State private var updating = false
    @State private var error: String?
    @State private var showCalendar = false
    @State private var pendingStatusChange: SchoolTaskStatusConfirmation?

    private var source: OrbitSchoolItem? { store.item(id: task.sourceItemId) }
    private var dueKey: String? { SchoolHubLogic.dayKey(for: task.dueAt, allDay: task.allDay) }

    var body: some View {
        List {
            Section {
                Routes05ContextHeader(section: "school", eyebrow: "TASK / DETAIL", title: "Справу\nпо черзі.", detail: "Стан Orbit-справи та її джерело залишаються окремими.", accent: Routes05Tokens.orange)
            }
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
                    Label("Крайній термін: \(SchoolHubFormat.long(dueKey))", systemImage: "calendar")
                } else {
                    Label("Термін не вказано в джерелі", systemImage: "calendar.badge.questionmark")
                        .foregroundStyle(.secondary)
                }
                if task.canAddToCalendar {
                    if task.calendarEventId != nil {
                        Label("Додано до календаря Orbit", systemImage: "calendar.badge.checkmark").foregroundStyle(NovaTodayTokens.teal)
                    } else {
                        Button { showCalendar = true } label: { Label("Додати до календаря", systemImage: "calendar.badge.plus") }
                            .frame(minHeight: OrbitSpacing.minTarget)
                    }
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
                LabeledContent("Походження", value: task.provenanceLabel)
                if task.kind == "source", let source {
                    NavigationLink { SchoolDetailView(item: source) } label: {
                        Label("Відкрити лист або повідомлення", systemImage: source.type == "letter" ? "envelope" : "message")
                    }
                } else if task.kind == "source" {
                    Label("Пов’язаний лист зараз недоступний", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                if store.actionTasksPhase == .loaded && task.identityStable {
                Button {
                    guard !updating else { return }
                    pendingStatusChange = SchoolTaskStatusConfirmation(completed: task.status == "completed")
                } label: {
                    Label(task.status == "completed" ? "Повернути у відкриті" : "Позначити виконаною", systemImage: task.status == "completed" ? "arrow.uturn.backward.circle" : "checkmark.circle")
                }
                .disabled(updating)
                .frame(minHeight: OrbitSpacing.minTarget)
                if updating { ProgressView().frame(maxWidth: .infinity) }
                } else {
                    Label(task.identityStable ? "Позначити виконання зараз неможливо: функція недоступна." : "Стан не можна зберегти: у джерела немає стабільного ідентифікатора.", systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                    if task.identityStable && !store.actionCapability.canMutate {
                        Button("Перевірити знову") { Task { await store.refreshActionCapability() } }.frame(minHeight: OrbitSpacing.minTarget)
                    }
                }
            } header: { Text("Стан Orbit") } footer: {
                Text(task.kind == "family" ? "Це сімейна справа Orbit і не змінює шкільне джерело." : "Стан зберігається в Orbit окремо від Schulmanager.")
            }
            .confirmationDialog(
                pendingStatusChange?.title ?? "Змінити стан справи?",
                isPresented: Binding(get: { pendingStatusChange != nil }, set: { if !$0 { pendingStatusChange = nil } }),
                titleVisibility: .visible
            ) {
                if let pendingStatusChange {
                    Button(pendingStatusChange.actionTitle) { confirmStatusChange(pendingStatusChange) }
                }
                Button("Скасувати", role: .cancel) { pendingStatusChange = nil }
            } message: {
                Text(task.title)
            }
            if store.actionCapability.canMutate {
                Section("Підготовка й нотатки") {
                    NavigationLink { SchoolChecklistView(store: store, sourceItemId: task.sourceItemId.isEmpty ? nil : task.sourceItemId, sourceTaskId: task.actionID) } label: {
                        Label("Чекліст підготовки", systemImage: "checklist.checked")
                    }
                    if let noteEntityID = task.kind == "family" ? task.actionID : task.sourceNoteEntityId, !noteEntityID.isEmpty {
                        NavigationLink { SchoolNotesView(store: store, entityType: "task", entityId: noteEntityID) } label: {
                            Label("Мої нотатки", systemImage: "note.text")
                        }
                    }
                }
            } else {
                Section("Підготовка й нотатки") {
                    Label(store.actionCapability.message, systemImage: "lock.slash")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Справа")
        .navigationBarTitleDisplayMode(.inline)
        .novaDockAwareScrollContent()
        .sheet(isPresented: $showCalendar) { SchoolTaskCalendarSheet(store: store, task: task) }
        .alert("Стан справи", isPresented: .constant(error != nil)) { Button("Гаразд") { error = nil } } message: { Text(error ?? "") }
    }

    private func confirmStatusChange(_ confirmation: SchoolTaskStatusConfirmation) {
        guard !updating, task.identityStable, store.actionCapability.canMutate else { return }
        pendingStatusChange = nil
        updating = true
        let completed = confirmation == .complete
        Task {
            defer { updating = false }
            do { try await store.setTaskStatus(task, completed: completed) }
            catch { self.error = "Не вдалося зберегти стан справи. Перевірте з’єднання й повторіть." }
        }
    }
}

private struct SchoolChecklistView: View {
    let store: SchoolHubStore
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
        Group {
            if !store.actionCapability.canMutate {
                SchoolActionsUnavailableView(capability: store.actionCapability) { Task { await store.refreshActionCapability() } }
            } else {
                checklistList
            }
        }
        .navigationTitle("Підготовка")
        .navigationBarTitleDisplayMode(.inline)
        .task { if store.actionCapability.canMutate { await load() } }
        .refreshable { if store.actionCapability.canMutate { await load() } }
        .alert("Підготовка", isPresented: .constant(error != nil)) { Button("Гаразд") { error = nil } } message: { Text(error ?? "") }
    }

    private var checklistList: some View {
        List {
            Section {
                Routes05ContextHeader(section: "school", eyebrow: "ACTION CENTER / FAMILY", title: "Справи.\nПо черзі.", detail: "Стан Orbit-справ і джерел школи залишається розділеним.", accent: Routes05Tokens.orange)
            }
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
        .novaDockAwareScrollContent()
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
        do { _ = try await MainProductAPI.shared.updateSchoolChecklistItem(id: item.id, completed: completed, revision: item.revision); await load() } catch { self.error = "Не вдалося оновити пункт. Можливо, список змінився — оновіть його." }
    }
    private func progress(_ checklist: OrbitSchoolActionChecklist) -> String {
        let done = checklist.items.filter { $0.completedAt != nil }.count
        return "\(done)/\(checklist.items.count)"
    }
}

private struct SchoolNotesView: View {
    let store: SchoolHubStore
    let entityType: String
    let entityId: String
    @State private var notes: [OrbitSchoolActionNote] = []
    @State private var draft = ""
    @State private var editing: OrbitSchoolActionNote?
    @State private var error: String?
    @State private var saving = false
    @State private var pendingRequestID: String?

    var body: some View {
        Group {
            if !store.actionCapability.canMutate {
                List {
                    Section {
                        Routes05ContextHeader(section: "discovery", eyebrow: "PRIVATE / NOTES", title: "Місце\nдля думок.", detail: "Приватні нотатки поточного Orbit-профілю, окремо від тексту школи.", accent: Routes05Tokens.lilac)
                    }
                    Section {
                        SchoolActionsUnavailableView(capability: store.actionCapability) { Task { await store.refreshActionCapability() } }
                    }
                }
                .listStyle(.plain)
            } else {
                notesList
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task { if store.actionCapability.canMutate { await load() } }
        .refreshable { if store.actionCapability.canMutate { await load() } }
        .sheet(item: $editing) { note in SchoolNoteEditor(note: note) { content in try await update(note, content: content) } }
        .alert("Нотатки", isPresented: .constant(error != nil)) { Button("Гаразд") { error = nil } } message: { Text(error ?? "") }
    }

    private var notesList: some View {
        List {
            Section {
                Routes05ContextHeader(section: "discovery", eyebrow: "PRIVATE / NOTES", title: "Місце\nдля думок.", detail: "Приватні нотатки поточного Orbit-профілю, окремо від тексту школи.", accent: Routes05Tokens.lilac)
            }
            Section {
                TextField("Нова нотатка", text: $draft, axis: .vertical).lineLimit(2...5)
                Button { create() } label: { HStack { Text("Зберегти нотатку"); if saving { Spacer(); ProgressView() } } }
                    .disabled(saving || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: { Text("Мої нотатки") } footer: { Text("Нотатки приватні для поточного Orbit-профілю й чітко відокремлені від тексту школи.") }
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
        .novaDockAwareScrollContent()
    }

    private func load() async {
        do { notes = try await MainProductAPI.shared.schoolActionNotes(entityType: entityType, entityId: entityId).notes }
        catch { self.error = noteError(error, operation: "load") }
    }
    private func create() {
        let content = draft.trimmingCharacters(in: .whitespacesAndNewlines); guard !content.isEmpty else { return }
        let requestID = pendingRequestID ?? UUID().uuidString
        pendingRequestID = requestID
        saving = true
        Task {
            defer { saving = false }
            do {
                _ = try await MainProductAPI.shared.createSchoolActionNote(entityType: entityType, entityId: entityId, content: content, clientRequestId: requestID)
                draft = ""
                pendingRequestID = nil
                await load()
            } catch {
                await load()
                if notes.contains(where: { $0.clientRequestId == requestID }) {
                    draft = ""; pendingRequestID = nil
                } else { self.error = noteError(error, operation: "save") }
            }
        }
    }
    private func update(_ note: OrbitSchoolActionNote, content: String) async throws {
        _ = try await MainProductAPI.shared.updateSchoolActionNote(id: note.id, content: content, revision: note.revision)
        await load()
    }
    private func noteError(_ error: Error, operation: String) -> String {
        if let failure = error as? OrbitHTTPResponseFailure {
            switch failure.status {
            case 401, 403: return "Немає доступу до цієї нотатки або шкільної справи."
            case 404: return "Джерело справи більше недоступне. Оновіть список і спробуйте ще раз."
            case 409: return operation == "save" ? "Нотатку вже збережено або запит конфліктує. Оновіть список." : "Нотатку змінили в іншому місці. Відкрийте її знову перед редагуванням."
            default: return "Сервер тимчасово недоступний. Збережіть текст і повторіть спробу."
            }
        }
        return "Не вдалося \(operation == "load" ? "завантажити нотатки" : operation == "save" ? "зберегти нотатку" : "оновити нотатку"). Перевірте з’єднання й повторіть спробу."
    }
}

private struct SchoolNoteEditor: View {
    let note: OrbitSchoolActionNote
    let save: (String) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var content: String

    @State private var saving = false
    @State private var error: String?
    init(note: OrbitSchoolActionNote, save: @escaping (String) async throws -> Void) { self.note = note; self.save = save; _content = State(initialValue: note.content) }

    var body: some View {
        NavigationStack {
            TextEditor(text: $content).padding(12).navigationTitle("Редагувати нотатку").navigationBarTitleDisplayMode(.inline).toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Скасувати") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button { saving = true; Task { do { try await save(content); dismiss() } catch { self.error = "Не вдалося оновити нотатку. Перевірте з’єднання або відкрийте нотатку знову."; saving = false } } } label: { if saving { ProgressView() } else { Text("Зберегти") } }.disabled(saving || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
        }
        .alert("Нотатки", isPresented: .constant(error != nil)) { Button("Гаразд") { error = nil } } message: { Text(error ?? "") }
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

struct LiveSchoolTaskCalendarService: SchoolTaskCalendarService {
    func createEvent(_ request: SchoolTaskCalendarRequest) async throws -> SchoolTaskCalendarOutcome {
        let result = try await MainProductAPI.shared.createSchoolTaskCalendarEvent(request)
        return SchoolTaskCalendarOutcome(created: result.created, duplicate: result.duplicate ?? false, eventID: result.eventId)
    }
}

private struct SchoolTaskCalendarSheet: View {
    let store: SchoolHubStore
    let task: SchoolHubTask
    @Environment(\.dismiss) private var dismiss
    @State private var model: SchoolTaskCalendarModel

    init(store: SchoolHubStore, task: SchoolHubTask) {
        self.store = store
        self.task = task
        _model = State(initialValue: SchoolTaskCalendarModel(
            itemID: task.sourceItemId, taskKey: task.sourceTaskKey, title: task.title, notes: task.action == task.title ? "" : (task.action ?? ""),
            knownDeadline: SchoolHubLogic.calendarPrefillDay(for: task), service: LiveSchoolTaskCalendarService()
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                if case .saved(_, let duplicate) = model.state {
                    Section {
                        Label(duplicate ? "Ця справа вже є в календарі Orbit." : "Додано до календаря Orbit.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(NovaTodayTokens.teal)
                    }
                } else {
                    Section("Подія") {
                        TextField("Назва", text: $model.title, axis: .vertical)
                    }
                    Section {
                        if model.knownDeadline == nil {
                            Toggle("Вибрати дату", isOn: $model.hasDate)
                        }
                        if model.hasDate {
                            DatePicker("Дата", selection: $model.date, displayedComponents: .date)
                                .environment(\.timeZone, SchoolHubLogic.schoolTimeZone)
                            Toggle("Вказати час", isOn: $model.hasTime)
                            if model.hasTime {
                                DatePicker("Час", selection: $model.time, displayedComponents: .hourAndMinute)
                                    .environment(\.timeZone, SchoolHubLogic.schoolTimeZone)
                            }
                        }
                    } header: { Text("Коли") } footer: {
                        if model.knownDeadline != nil {
                            Text("Це крайній термін зі шкільного джерела. Час не вигадується — додайте його, якщо потрібно.")
                        } else {
                            Text("У справи немає терміну. Оберіть дату самостійно.")
                        }
                    }
                    Section("Нотатки") {
                        TextField("Нотатки (необов’язково)", text: $model.notes, axis: .vertical).lineLimit(2...6)
                    }
                    Section("Джерело") {
                        Label("Лист або повідомлення Schulmanager", systemImage: "envelope")
                        Text("Подія з’явиться в календарі Orbit вашої родини.").font(.footnote).foregroundStyle(.secondary)
                    }
                    if case .failed(let message) = model.state {
                        Section { SchoolNotice(text: message, systemImage: "exclamationmark.triangle.fill") }
                    }
                }
            }
            .navigationTitle("Додати до календаря")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(model.isSaved ? "Закрити" : "Скасувати") { dismiss() } }
                if !model.isSaved {
                    ToolbarItem(placement: .confirmationAction) {
                        if model.isSaving { ProgressView() } else {
                            Button("Додати") {
                                Task {
                                    await model.save()
                                    if case .saved(let eventID, _) = model.state { store.recordCalendarLink(taskID: task.id, eventID: eventID) }
                                }
                            }
                            .disabled(!model.canSave)
                        }
                    }
                }
            }
            .onChange(of: model.title) { model.dismissError() }
        }
        .presentationDetents([.large])
    }
}

// MARK: - Tasks

private struct SchoolTaskListView: View {
    let store: SchoolHubStore
    @State private var query = ""
    @State private var filter: SchoolTaskFilter = .open
    @State private var showCreate = false

    var body: some View {
        let today = SchoolHubLogic.dayKey(of: Date())
        let searched = searchedTasks
        let counts = SchoolHubLogic.taskCounts(searched)
        let sections = SchoolHubLogic.taskSections(searched, filter: filter, today: today, sourceDates: store.sourceDates, now: Date())
        List {
            Section {
                Routes05ContextHeader(section: "school", eyebrow: "ACTION CENTER / FAMILY", title: "Справи.\nПо черзі.", detail: "Стан Orbit-справ і джерел школи залишається розділеним.", accent: Routes05Tokens.orange)
            }
            Section {
                Picker("Показати", selection: $filter) {
                    ForEach(SchoolTaskFilter.allCases) { item in
                        Text("\(item.title) \(count(for: item, counts))").tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }
            statusSection
            group("Цього тижня", tasks: sections.thisWeek, today: today)
            group("Інші дати", tasks: sections.dated, today: today)
            group("Без дати", tasks: sections.undated, today: today)
            disclosure("Старіші без дати", tasks: sections.undatedOlder, today: today)
            if store.tasksPhase == .loaded && sections.visibleCount == 0 {
                emptyState
            }
        }
        .listSectionSpacing(.compact)
        .searchable(text: $query, prompt: "Шукати справи")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if store.actionCapability.canMutate {
                    Button { showCreate = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Створити сімейну справу")
                }
            }
        }
        .sheet(isPresented: $showCreate) {
            SchoolFamilyTaskEditorView(store: store)
        }
        .refreshable { await store.load() }
    }

    private func count(for filter: SchoolTaskFilter, _ counts: SchoolTaskCounts) -> Int {
        switch filter {
        case .open: counts.open
        case .completed: counts.completed
        case .all: counts.all
        }
    }

    private var searchedTasks: [SchoolHubTask] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? store.hubTasks : SchoolHubLogic.searchTasks(store.hubTasks, query: trimmed)
    }

    @ViewBuilder private var statusSection: some View {
        if store.tasksPhase == .failed {
            Section {
                SchoolNotice(
                    text: store.tasksLoadedOnce ? "Не вдалося оновити список справ. Показано останні завантажені дані." : (store.itemsLoadedOnce ? "Список справ оновити не вдалося. Показано справи з уже завантажених листів — він може бути неповним." : "Не вдалося завантажити справи."),
                    systemImage: "exclamationmark.triangle.fill"
                )
                Button("Повторити") { Task { await store.load() } }.frame(minHeight: OrbitSpacing.minTarget)
            }
        } else if store.tasksPhase == .loading && !store.tasksLoadedOnce {
            Section { ProgressView().frame(maxWidth: .infinity) }
        } else if store.taskCoverageTruncated {
            Section { SchoolNotice(text: "Показано не всі справи: список обмежено. Уточніть пошук.", systemImage: "info.circle") }
        }
        if !store.actionCapability.canMutate && store.actionCapability != .unknown {
            Section {
                Label(store.actionCapability.message, systemImage: "lock.slash").font(.footnote).foregroundStyle(.secondary)
                Button("Перевірити знову") { Task { await store.refreshActionCapability() } }.frame(minHeight: OrbitSpacing.minTarget)
            } footer: { Text("Справи доступні лише для перегляду.") }
        }
    }

    private var emptyState: some View {
        let searching = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let title = searching ? "Справ не знайдено" : (filter == .completed ? "Виконаних справ немає" : "Відкритих справ немає")
        return ContentUnavailableView(title, systemImage: searching ? "magnifyingglass" : "checklist", description: searching ? Text("Спробуйте інший запит або фільтр.") : nil)
    }

    @ViewBuilder private func group(_ title: String, tasks: [SchoolHubTask], overdue: Bool = false, today: String) -> some View {
        if !tasks.isEmpty {
            Section { ForEach(tasks) { SchoolTaskRow(store: store, task: $0, overdue: overdue, today: today) } } header: { SchoolSectionHeader(title: title, count: tasks.count) }
        }
    }

    @ViewBuilder private func disclosure(_ title: String, tasks: [SchoolHubTask], today: String) -> some View {
        if !tasks.isEmpty {
            Section {
                DisclosureGroup("\(title) (\(tasks.count))") {
                    ForEach(tasks) { SchoolTaskRow(store: store, task: $0, today: today) }
                }
                .font(.footnote)
                .frame(minHeight: OrbitSpacing.minTarget)
            }
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
                Routes05ContextHeader(section: "school", eyebrow: "SOURCE / SCHOOL CALENDAR", title: "Щодалі\nу школі?", detail: "Події джерела; додавання до сімейного календаря — лише через підтвердження.", accent: Routes05Tokens.yellow)
            }
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
        .novaDockAwareScrollContent()
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
                Routes05ContextHeader(section: "discovery", eyebrow: "SCHOOL / TIMELINE", title: "Усе\nпо порядку.", accent: Routes05Tokens.yellow)
            }
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
        .navigationTitle("")
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
            Section {
                Routes05ContextHeader(section: "school", eyebrow: "SEARCH / VERIFIED SOURCES", title: "Знайти.\nШвидко.", detail: "Пошук лише серед авторизованих завантажених джерел.", accent: Routes05Tokens.lilac)
            }
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
        .navigationTitle("")
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

// MARK: - ROUTES 05 pixel-fidelity school surfaces

/// Production presentation for the ROUTES 05 task route.  The store, API,
/// confirmation semantics and detail destinations remain the existing ones.
private struct Routes05SchoolTasksProductionView: View {
    let store: SchoolHubStore
    @Environment(\.dismiss) private var dismiss
    @State private var filter: Routes05TaskFilter = .all
    @State private var query = ""
    @State private var showSearch = false
    @State private var showCreate = false
    @State private var calendarTask: SchoolHubTask?
    @State private var pendingTask: SchoolHubTask?
    @State private var error: String?

    private var tasks: [SchoolHubTask] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = q.isEmpty ? store.hubTasks : SchoolHubLogic.searchTasks(store.hubTasks, query: q)
        return source.filter { task in
            switch filter {
            case .all: true
            case .open: !SchoolHubLogic.isCompleted(task)
            case .completed: SchoolHubLogic.isCompleted(task)
            }
        }
    }

    private var counts: SchoolTaskCounts { SchoolHubLogic.taskCounts(store.hubTasks) }
    private var today: String { SchoolHubLogic.dayKey(of: Date()) }

    var body: some View {
        VStack(spacing: 0) {
            Routes05Mast(section: "school")
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    topBar
                    intro
                    hero
                    filters
                    stateNotice
                    if store.tasksPhase == .loading && !store.tasksLoadedOnce {
                        ProgressView("Завантаження справ…").frame(maxWidth: .infinity, minHeight: 120)
                    } else if tasks.isEmpty {
                        ContentUnavailableView(query.isEmpty ? "Справ не знайдено" : "Нічого не знайдено", systemImage: "checklist", description: Text("Оберіть інший фільтр або оновіть дані."))
                            .padding(.vertical, 24)
                    } else {
                        ForEach(Routes05TaskGroup.allCases, id: \.self) { group in
                            let groupTasks = tasks.filter { taskGroup($0) == group }
                            if !groupTasks.isEmpty { taskGroupView(group, tasks: groupTasks) }
                        }
                    }
                    Text("Статус справ і дані зі шкільних джерел відображаються окремо. Зміни виконуються лише після перевірки прав та підтвердження.")
                        .font(.footnote).foregroundStyle(Routes05Tokens.secondary)
                        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 30)
                }
            }
            .refreshable { await store.load() }
        }
        .foregroundStyle(Routes05Tokens.ink)
        .background(Routes05Tokens.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showCreate) { SchoolFamilyTaskEditorView(store: store) }
        .sheet(item: $calendarTask) { SchoolTaskCalendarSheet(store: store, task: $0) }
        .confirmationDialog(pendingTask.map { $0.status == "completed" ? "Повернути справу у відкриті?" : "Позначити справу виконаною?" } ?? "Змінити стан справи?", isPresented: Binding(get: { pendingTask != nil }, set: { if !$0 { pendingTask = nil } }), titleVisibility: .visible) {
            if let task = pendingTask {
                Button(task.status == "completed" ? "Повернути у відкриті" : "Позначити виконаною") { confirm(task) }
            }
            Button("Скасувати", role: .cancel) { pendingTask = nil }
        } message: { Text(pendingTask?.title ?? "") }
        .alert("Стан справи", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("Гаразд") { error = nil }
        } message: { Text(error ?? "") }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: { Image(systemName: "arrow.left").font(.title3.weight(.semibold)).frame(width: 43, height: 43).overlay(RoundedRectangle(cornerRadius: 3).stroke(Routes05Tokens.ink, lineWidth: 1.5)) }.accessibilityLabel("Назад до школи")
            Text("Справи / школа").font(.system(.headline, design: .rounded).weight(.black)).lineLimit(1)
            Spacer(minLength: 4)
            Button { showSearch.toggle(); if !showSearch { query = "" } } label: { Image(systemName: showSearch ? "xmark" : "magnifyingglass").frame(width: 42, height: 44) }.accessibilityLabel(showSearch ? "Закрити пошук" : "Шукати справи")
            if store.actionCapability.canMutate { Button { showCreate = true } label: { Image(systemName: "plus").frame(width: 42, height: 44) }.accessibilityLabel("Створити сімейну справу") }
        }
        .padding(.horizontal, 16).padding(.top, 15).padding(.bottom, 17)
    }

    private var intro: some View {
        HStack { Text("ACTION CENTER / FAMILY").font(.system(size: 10, weight: .black, design: .monospaced)).tracking(1.8); Spacer(); Text("ORBIT / SCHOOL").font(.system(size: 9, weight: .medium, design: .monospaced)) }
            .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 10).overlay(alignment: .bottom) { Rectangle().fill(Routes05Tokens.ink).frame(height: 1.5) }
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Справи.\nПо черзі.").font(.system(.largeTitle, design: .rounded).weight(.black)).tracking(-2).lineSpacing(-5).fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
            Spacer()
            Text(String(format: "%02d", tasks.filter { !$0.status.elementsEqual("completed") && SchoolHubLogic.dayKey(for: $0.dueAt, allDay: $0.allDay) == today }.count)).font(.system(size: 30, weight: .black, design: .rounded)).foregroundStyle(Routes05Tokens.accentInk).frame(width: 77, height: 77).background(Routes05Tokens.orange, in: Circle()).overlay(Circle().stroke(Routes05Tokens.darkSurfaceInk, lineWidth: 2)).accessibilityLabel("Справ на сьогодні")
        }.padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 15)
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 8) { ForEach(Routes05TaskFilter.allCases) { item in
            let selected = item == filter
            Button { filter = item } label: { Text("\(item.title) \(item.count(counts))").font(.system(.subheadline, design: .rounded).weight(.bold)).foregroundStyle(selected ? Routes05Tokens.accentInk : Routes05Tokens.ink).padding(.horizontal, 15).frame(minHeight: 42).background(selected ? Routes05Tokens.darkSurfaceInk : Routes05Tokens.surface, in: Capsule()).overlay(Capsule().stroke(Routes05Tokens.rule, lineWidth: selected ? 0 : 1)) }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
        } }.padding(.horizontal, 16) }.padding(.bottom, 16)
    }

    @ViewBuilder private var stateNotice: some View {
        if showSearch { TextField("Пошук справ", text: $query).textFieldStyle(.roundedBorder).padding(.horizontal, 16).padding(.bottom, 10) }
        if store.tasksPhase == .failed { Label(store.tasksLoadedOnce ? "Не вдалося оновити список; показано останні дані." : "Не вдалося завантажити справи.", systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(Routes05Tokens.secondary).padding(.horizontal, 16).padding(.bottom, 8) }
        if store.taskCoverageTruncated { Label("Показано не всі справи: список обмежено.", systemImage: "info.circle").font(.footnote).foregroundStyle(Routes05Tokens.secondary).padding(.horizontal, 16).padding(.bottom, 8) }
        if !store.actionCapability.canMutate && store.actionCapability != .unknown { Label(store.actionCapability.message, systemImage: "lock").font(.footnote).foregroundStyle(Routes05Tokens.secondary).padding(.horizontal, 16).padding(.bottom, 8) }
    }

    private func taskGroup(_ task: SchoolHubTask) -> Routes05TaskGroup {
        guard let key = SchoolHubLogic.dayKey(for: task.dueAt, allDay: task.allDay) else { return .undated }
        if key == today { return .today }
        let week = Set(SchoolHubLogic.weekDays(containing: today))
        return week.contains(key) ? .thisWeek : .later
    }

    private func taskGroupView(_ group: Routes05TaskGroup, tasks: [SchoolHubTask]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(group.title).font(.system(.title3, design: .rounded).weight(.black)).padding(.bottom, 9)
            ForEach(tasks) { task in
                Routes05TaskRow(task: task, store: store, onStatus: { pendingTask = task }, onCalendar: { calendarTask = task })
                Rectangle().fill(Routes05Tokens.rule).frame(height: 1)
            }
        }.padding(.horizontal, 16).padding(.top, 16)
    }

    private func confirm(_ task: SchoolHubTask) {
        pendingTask = nil
        let completed = task.status != "completed"
        Task { do { try await store.setTaskStatus(task, completed: completed) } catch { self.error = "Не вдалося зберегти стан справи. Перевірте з’єднання й повторіть." } }
    }
}

private enum Routes05TaskFilter: CaseIterable, Identifiable { case all, open, completed; var id: Self { self }; var title: String { self == .all ? "Всі" : self == .open ? "Відкриті" : "Завершені" }; func count(_ counts: SchoolTaskCounts) -> Int { self == .all ? counts.all : self == .open ? counts.open : counts.completed } }
private enum Routes05TaskGroup: CaseIterable { case today, thisWeek, later, undated; var title: String { self == .today ? "Сьогодні" : self == .thisWeek ? "Цього тижня" : self == .later ? "Інші дати" : "Без дати" } }

private struct Routes05TaskRow: View {
    let task: SchoolHubTask
    let store: SchoolHubStore
    let onStatus: () -> Void
    let onCalendar: () -> Void
    private var evidence: SchoolEvidence { let item = store.item(id: task.sourceItemId); return SchoolHubLogic.evidence(forTask: task, sourceLoaded: item != nil, activeNames: store.studentNames, sourceText: item?.originalPlainText ?? item?.originalGerman ?? "") }
    var body: some View {
        HStack(spacing: 10) {
            Button(action: onStatus) { Image(systemName: task.status == "completed" ? "checkmark.square.fill" : "square").font(.system(size: 26)).frame(width: 44, height: 54).overlay { if store.isUpdating(task) { ProgressView().controlSize(.small) } } }.disabled(!store.actionCapability.canMutate || store.isUpdating(task)).accessibilityLabel(task.status == "completed" ? "Повернути справу у відкриті" : "Позначити справу виконаною")
            NavigationLink { SchoolTaskDetailView(store: store, task: task) } label: {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) { Text(task.title).font(.system(.body, design: .rounded).weight(.bold)).multilineTextAlignment(.leading); if evidence == .needsVerification { Image(systemName: "exclamationmark.triangle").foregroundStyle(Routes05Tokens.orange) } }
                    Text([task.dueAt.flatMap { SchoolHubLogic.dayKey(for: $0, allDay: task.allDay).map(SchoolHubFormat.shortDay) }, task.provenanceLabel, task.target].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(Routes05Tokens.secondary).lineLimit(2)
                }.frame(maxWidth: .infinity, minHeight: 77, alignment: .leading)
            }.buttonStyle(.plain)
            Image(systemName: "arrow.right").font(.subheadline.weight(.bold)).accessibilityHidden(true)
        }.padding(.vertical, 4).contextMenu { if task.canAddToCalendar && task.calendarEventId == nil { Button(action: onCalendar) { Label("До сімейного календаря", systemImage: "calendar.badge.plus") } } }
    }
}

private struct Routes05SchoolTimetableProductionView: View {
    let studentLabel: String?
    @State private var store = SchoolHubV2Store()
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDay: String?

    init(studentLabel: String?) {
        self.studentLabel = studentLabel
    }

#if DEBUG
    init(studentLabel: String?, fixture: Routes05SchoolFixture) {
        self.studentLabel = studentLabel
        _store = State(initialValue: SchoolHubV2Store(fixture: fixture))
    }
#endif

    private var days: [String] { Array(Set(store.timetable.map(\.dayKey))).sorted() }
    private var slots: [Int] { Array(Set(store.timetable.map(\.lessonIndex))).sorted() }
    private var classLabel: String { store.timetable.compactMap { $0.groupName ?? $0.group }.first ?? "школа" }
    private var weekNumber: String {
        guard let date = SchoolHubLogic.date(fromDayKey: store.weekStart) else { return "—" }
        var calendar = Calendar(identifier: .iso8601); calendar.timeZone = SchoolHubLogic.schoolTimeZone
        return String(calendar.component(.weekOfYear, from: date))
    }
    private var year: String { String(store.weekStart.prefix(4)) }

    var body: some View {
        VStack(spacing: 0) {
            Routes05Mast(section: "school")
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    intro
                    hero
                    weekControls
                    coverage
                    content
                }.padding(.bottom, 28)
            }.refreshable { await store.load() }
        }
        .foregroundStyle(Routes05Tokens.ink).background(Routes05Tokens.canvas.ignoresSafeArea()).toolbar(.hidden, for: .navigationBar)
        .task(id: store.weekStart) { await store.load() }
        .onChange(of: days) { _, value in if !value.contains(selectedDay ?? "") { selectedDay = value.first } }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: { Image(systemName: "arrow.left").font(.title3.weight(.semibold)).frame(width: 43, height: 43).overlay(RoundedRectangle(cornerRadius: 3).stroke(Routes05Tokens.ink, lineWidth: 1.5)) }.accessibilityLabel("Назад до школи")
            Text("Розклад").font(.system(.headline, design: .rounded).weight(.black))
            Spacer()
            Menu { Button("Огляд") { dismiss() }; Button("Іспити") { dismiss() } } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }.accessibilityLabel("Інші розділи школи")
        }.padding(.horizontal, 16).padding(.top, 15).padding(.bottom, 17)
    }
    private var intro: some View {
        HStack { Text("WEEK / \(weekNumber)").font(.system(size: 10, weight: .black, design: .monospaced)).tracking(1.8); Spacer(); Text(year).font(.system(size: 10, weight: .medium, design: .monospaced)) }
            .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 10).overlay(alignment: .bottom) { Rectangle().fill(Routes05Tokens.ink).frame(height: 1.5) }
    }
    private var hero: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Розклад\n\(classLabel).").font(.system(.largeTitle, design: .rounded).weight(.black)).tracking(-2).lineSpacing(-5).fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
            Spacer()
            Image(systemName: "calendar").font(.system(size: 29, weight: .heavy)).foregroundStyle(Routes05Tokens.accentInk).frame(width: 77, height: 77).background(Routes05Tokens.mint, in: Circle()).overlay(Circle().stroke(Routes05Tokens.darkSurfaceInk, lineWidth: 2)).accessibilityHidden(true)
        }.padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 8)
    }
    private var weekControls: some View {
        VStack(spacing: 11) {
            HStack { Button { store.shiftWeek(-7) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("Попередній тиждень"); Spacer(); Text("\(SchoolHubFormat.shortDay(store.weekStart)) – \(SchoolHubFormat.shortDay(SchoolHubLogic.addDays(4, to: store.weekStart) ?? store.weekStart))").font(.system(.headline, design: .rounded).weight(.bold)).multilineTextAlignment(.center); Spacer(); Button { store.shiftWeek(7) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.accessibilityLabel("Наступний тиждень") }.buttonStyle(.plain)
            ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 7) { ForEach(days, id: \.self) { day in
                let selected = selectedDay == day || (selectedDay == nil && day == days.first)
                Button { selectedDay = day } label: { VStack(spacing: 4) { Text(SchoolHubFormat.weekdayShort(day).uppercased()).font(.system(.caption2, design: .monospaced).weight(.bold)); Text(SchoolHubFormat.dayNumber(day)).font(.system(.largeTitle, design: .rounded).weight(.black)) }.frame(width: 72, height: 79).foregroundStyle(selected ? Routes05Tokens.accentInk : Routes05Tokens.ink).background(selected ? Routes05Tokens.yellow : Routes05Tokens.surface).overlay(RoundedRectangle(cornerRadius: 3).stroke(Routes05Tokens.ink, lineWidth: 1.2)) }.buttonStyle(.plain).accessibilityLabel(SchoolHubFormat.long(day)).accessibilityAddTraits(selected ? .isSelected : [])
            } }.padding(.horizontal, 16) }
        }.padding(.horizontal, 0).padding(.top, 12)
    }
    private var coverage: some View {
        Label(coverageText, systemImage: store.coverageState == "READY_WITH_DATA" ? "checkmark.circle" : "info.circle").font(.caption).foregroundStyle(Routes05Tokens.secondary).padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 16)
    }
    private var coverageText: String {
        switch store.coverageState { case "READY_WITH_DATA": return "Дані за тиждень оновлено"; case "READY_EMPTY": return "Тиждень перевірено: даних немає"; case "STALE": return "Дані можуть бути застарілими"; case "NOT_SYNCED": return "Тиждень ще не синхронізовано"; case "PARTIAL": return "Дані неповні"; default: return store.phase == .loading ? "Завантаження розкладу…" : "Дані тимчасово недоступні" }
    }
    @ViewBuilder private var content: some View {
        if store.phase == .loading && store.timetable.isEmpty { ProgressView("Завантаження розкладу…").frame(maxWidth: .infinity, minHeight: 150) }
        else if store.timetable.isEmpty { ContentUnavailableView("Немає підтвердженого розкладу", systemImage: "calendar.badge.exclamationmark", description: Text(coverageText)).padding(.vertical, 24) }
        else { GeometryReader { proxy in timetableGrid(width: proxy.size.width) }.frame(height: CGFloat(max(1, slots.count)) * 121 + 45) }
    }
    private func timetableGrid(width: CGFloat) -> some View {
        let axis: CGFloat = 50; let gap: CGFloat = 5; let dayWidth = max(76, floor((width - 32 - axis - gap * 4) / 4))
        return ScrollView(.horizontal, showsIndicators: true) { VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: gap) { Text("УРОК").font(.system(size: 10, weight: .bold, design: .monospaced)).frame(width: axis, alignment: .leading); ForEach(days, id: \.self) { day in Text("\(SchoolHubFormat.weekdayShort(day).uppercased()) / \(SchoolHubFormat.dayNumber(day))").font(.system(size: 10, weight: .black, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.7).frame(width: dayWidth) } }.frame(height: 40).overlay(alignment: .bottom) { Rectangle().fill(Routes05Tokens.rule).frame(height: 1) }
            ForEach(slots, id: \.self) { slot in HStack(alignment: .top, spacing: gap) { Text(String(format: "%02d", slot)).font(.system(size: 11, design: .monospaced)).foregroundStyle(Routes05Tokens.secondary).frame(width: axis, height: 115, alignment: .topLeading); ForEach(Array(days.enumerated()), id: \.element) { index, day in cell(day: day, slot: slot, dayIndex: index, width: dayWidth) } }.padding(.vertical, 3).overlay(alignment: .bottom) { Rectangle().fill(Routes05Tokens.rule).frame(height: 1) } }
        }.padding(.horizontal, 16) }.accessibilityElement(children: .contain)
    }
    @ViewBuilder private func cell(day: String, slot: Int, dayIndex: Int, width: CGFloat) -> some View {
        let entries = store.timetable.filter { $0.dayKey == day && $0.lessonIndex == slot }
        if entries.isEmpty { Rectangle().fill(Routes05Tokens.surface).overlay(Rectangle().stroke(Routes05Tokens.rule.opacity(0.55), lineWidth: 1)).overlay(Text("—").foregroundStyle(Routes05Tokens.secondary)).frame(width: width, height: 115) }
        else { VStack(alignment: .leading, spacing: 3) { ForEach(entries) { entry in VStack(alignment: .leading, spacing: 3) { Text(entry.subject).font(.system(.subheadline, design: .rounded).weight(.black)).strikethrough(entry.isCancelled).lineLimit(2).minimumScaleFactor(0.76); if let room = entry.room, !room.isEmpty { Text(room).font(.system(size: 10)).lineLimit(1) }; Text([entry.startsAtLocal, entry.teacher].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 9)).lineLimit(2); if entry.isCancelled { Text("Скасовано").font(.system(size: 9, weight: .bold)) } }.foregroundStyle(Routes05Tokens.accentInk) } }.padding(7).frame(width: width, height: 115, alignment: .topLeading).background([Routes05Tokens.lilac, Routes05Tokens.mint, Routes05Tokens.orange, Routes05Tokens.yellow, Routes05Tokens.blue][(dayIndex + slot - 1) % 5]).overlay(Rectangle().stroke(Routes05Tokens.darkSurfaceInk, lineWidth: 1)).accessibilityElement(children: .combine).accessibilityLabel("Урок \(slot), \(entries.map(\.subject).joined(separator: ", "))") }
    }
}
