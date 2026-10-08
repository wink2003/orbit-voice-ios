import SwiftUI

// MARK: - Store

@MainActor @Observable
final class SchoolHubStore {
    enum Phase: Equatable { case idle, loading, loaded, failed }

    var itemsPhase: Phase = .idle
    var calendarPhase: Phase = .idle
    var items: [OrbitSchoolItem] = []
    var events: [OrbitSchulmanagerCalendarEvent] = []
    var studentNames: [String] = []
    var itemsLoadedOnce = false
    var calendarLoadedOnce = false

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
        items.flatMap { item in
            (item.tasks ?? []).enumerated().compactMap { index, task -> SchoolHubTask? in
                guard let title = (task.title ?? task.action), !title.isEmpty else { return nil }
                return SchoolHubTask(id: "\(item.id):\(task.key ?? String(index))", title: title, action: task.action, dueAt: task.dueAt, allDay: task.allDay ?? true, importance: task.importance, target: task.target, confidence: task.confidence, reason: task.reason, sourceItemId: item.id)
            }
        }
    }

    var sourceDates: [String: Date] {
        Dictionary(items.compactMap { item in (item.sourceTimestamp ?? item.importedAt).map { (item.id, $0) } }, uniquingKeysWith: { first, _ in first })
    }

    func item(id: String) -> OrbitSchoolItem? { items.first { $0.id == id } }
    func calendarEvent(uid: String) -> OrbitSchulmanagerCalendarEvent? { events.first { $0.uid == uid } }

    func load() async {
        itemsPhase = .loading
        calendarPhase = .loading
        async let itemsResult: Void = loadItems()
        async let calendarResult: Void = loadCalendar()
        async let namesResult: Void = loadNames()
        _ = await (itemsResult, calendarResult, namesResult)
    }

    private func loadItems() async {
        do {
            items = try await MainProductAPI.shared.schoolItems(filter: "all").items
            itemsLoadedOnce = true
            itemsPhase = .loaded
        } catch is CancellationError {
            itemsPhase = itemsLoadedOnce ? .loaded : .idle
        } catch { itemsPhase = .failed }
    }

    private func loadCalendar() async {
        let now = Date()
        do {
            events = try await MainProductAPI.shared.schulmanagerCalendar(
                scope: "all",
                from: now.addingTimeInterval(-30 * 86400),
                to: now.addingTimeInterval(120 * 86400)
            )
            calendarLoadedOnce = true
            calendarPhase = .loaded
        } catch is CancellationError {
            calendarPhase = calendarLoadedOnce ? .loaded : .idle
        } catch { calendarPhase = .failed }
    }

    private func loadNames() async {
        if let profiles = try? await MainProductAPI.shared.familyProfiles() {
            studentNames = profiles.filter(\.isMinor).map(\.displayName)
        }
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
            .foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
            .accessibilityLabel("Довіра: \(evidence.title)")
    }
    private var color: Color {
        switch evidence {
        case .sourceRecord: .green
        case .interpretation: .accentColor
        case .needsVerification: .orange
        }
    }
}

private struct SchoolRelevanceMarker: View {
    let relevance: SchoolEventRelevance
    var body: some View {
        Label(relevance.title, systemImage: relevance.systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
    }
    private var color: Color {
        switch relevance {
        case .ours: .red
        case .likely: .green
        case .uncertain, .unclassified: .orange
        case .unrelated, .staffOnly: .secondary
        }
    }
}

private struct SchoolSectionHeader: View {
    let title: String
    let systemImage: String
    var count: Int?
    var body: some View {
        HStack(spacing: 8) {
            Capsule().fill(Color.accentColor).frame(width: 3, height: 16)
            Image(systemName: systemImage).foregroundStyle(Color.accentColor).imageScale(.small)
            Text(title).font(.headline)
            if let count { Text("\(count)").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 6).padding(.vertical, 1).background(.secondary.opacity(0.15), in: Capsule()) }
        }
        .textCase(nil)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct SchoolNotice: View {
    let text: String
    let systemImage: String
    var body: some View {
        Label(text, systemImage: systemImage).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Hub

struct SchoolHubView: View {
    @State private var store = SchoolHubStore()
    @State private var section: SchoolHubSection = .overview
    @State private var search = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Розділ школи", selection: $section.animation(.easeOut(duration: 0.15))) {
                    ForEach(SchoolHubSection.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, OrbitSpacing.large).padding(.vertical, OrbitSpacing.medium)
                .sensoryFeedback(.selection, trigger: section)
                content
            }
            .background(OrbitColors.canvas)
            .navigationTitle("Школа")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Шукати в завантаженому")
            .task { await store.load() }
        }
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
            digestSection(groups: groups, tomorrowCount: tomorrowEvents.count + tomorrowTasks.count, events: events)
            tomorrowSection(events: tomorrowEvents, tasks: tomorrowTasks, prep: prep)
            attentionSection(groups: groups)
            newSection
            upcomingSection(events: events)
            Section { Button { navigate(.letters) } label: { Label("Листи та повідомлення", systemImage: "envelope") }.frame(minHeight: OrbitSpacing.minTarget)
                Button { navigate(.calendar) } label: { Label("Календар школи", systemImage: "calendar") }.frame(minHeight: OrbitSpacing.minTarget)
                Button { navigate(.tasks) } label: { Label("Усі задачі", systemImage: "checklist") }.frame(minHeight: OrbitSpacing.minTarget)
                NavigationLink { SchoolBrainView() } label: { Label("Запитати про школу", systemImage: "sparkles") }.frame(minHeight: OrbitSpacing.minTarget)
            } header: { SchoolSectionHeader(title: "Розділи", systemImage: "square.grid.2x2") }
        }
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
        let failed = [store.itemsPhase == .failed ? "листи й задачі" : nil, store.calendarPhase == .failed ? "календар" : nil].compactMap { $0 }.joined(separator: ", ")
        return hasData ? "Не вдалося оновити: \(failed). Показано раніше завантажені дані — вони можуть бути застарілими." : "Не вдалося завантажити: \(failed). Відсутність записів нижче не означає, що нічого немає."
    }

    private func digestSection(groups: SchoolTaskGroups, tomorrowCount: Int, events: [SchoolHubEvent]) -> some View {
        let lines = SchoolHubLogic.digest(.init(
            unreadLetters: store.letters.filter(\.unread).count, tomorrowEvents: tomorrowCount,
            overdueTasks: groups.overdue.count, datedTasks: groups.dated.count,
            undatedTasks: groups.undated.count + groups.undatedOlder.count,
            unclassifiedEvents: SchoolHubLogic.counts(events)[.unclassified] ?? 0
        ))
        return Section {
            if lines.isEmpty {
                SchoolNotice(text: store.itemsLoadedOnce ? "У завантажених даних немає нового, що вимагає уваги." : "Дані ще не завантажено.", systemImage: "list.bullet.clipboard")
            } else {
                ForEach(lines, id: \.self) { Text($0).font(.subheadline) }
            }
        } header: { SchoolSectionHeader(title: "Коротко", systemImage: "text.alignleft") } footer: { Text("Складено з завантажених даних без AI.") }
    }

    private func tomorrowSection(events: [SchoolHubEvent], tasks: [SchoolHubTask], prep: [SchoolHubTask]) -> some View {
        Section {
            if events.isEmpty && tasks.isEmpty {
                SchoolNotice(text: store.calendarPhase == .loaded && store.itemsPhase == .loaded ? "У завантажених даних на завтра (\(SchoolHubFormat.long(tomorrow))) подій і задач немає." : "Дані на завтра недоступні — календар або задачі не завантажено.", systemImage: "moon.zzz")
            }
            ForEach(events) { event in
                if let source = store.calendarEvent(uid: event.uid) {
                    NavigationLink { SchoolEventDetailView(event: source) } label: { SchoolEventRow(event: event) }
                }
            }
            ForEach(tasks) { SchoolTaskRow(store: store, task: $0) }
            if !prep.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Підготуватись (за текстами джерел)").font(.subheadline.weight(.semibold))
                    ForEach(prep) { Label($0.action ?? $0.title, systemImage: "circle.dotted").font(.subheadline) }
                }.accessibilityElement(children: .combine)
            }
        } header: { SchoolSectionHeader(title: "Завтра · \(SchoolHubFormat.long(tomorrow))", systemImage: "sunrise") }
    }

    private func attentionSection(groups: SchoolTaskGroups) -> some View {
        let urgent = groups.overdue + groups.undated
        return Section {
            if urgent.isEmpty && groups.undatedOlder.isEmpty {
                SchoolNotice(text: store.itemsPhase == .loaded ? "Відкритих задач без дати чи прострочених у завантажених листах немає." : "Задачі не завантажено.", systemImage: "checkmark.circle")
            }
            ForEach(urgent) { SchoolTaskRow(store: store, task: $0, overdue: groups.overdue.contains($0)) }
            if !groups.undatedOlder.isEmpty {
                DisclosureGroup("Старіші без дати (\(groups.undatedOlder.count)) · лишаються відкритими") {
                    ForEach(groups.undatedOlder) { SchoolTaskRow(store: store, task: $0) }
                }.frame(minHeight: OrbitSpacing.minTarget)
            }
        } header: { SchoolSectionHeader(title: "Потребує уваги", systemImage: "exclamationmark.circle", count: urgent.count + groups.undatedOlder.count) }
    }

    private var newSection: some View {
        let unread = store.items.filter(\.unread).prefix(3)
        return Section {
            if unread.isEmpty { SchoolNotice(text: store.itemsPhase == .loaded ? "Непрочитаних у Orbit немає." : "Листи не завантажено.", systemImage: "envelope.open") }
            ForEach(Array(unread)) { item in
                NavigationLink { SchoolDetailView(item: item) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.titlePlainText?.isEmpty == false ? item.titlePlainText! : (item.title.isEmpty ? (item.type == "letter" ? "Лист" : "Повідомлення") : item.title)).font(.headline).lineLimit(2)
                        Text(item.translationUkrainian ?? item.previewPlainText ?? item.originalGerman).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    }.frame(minHeight: OrbitSpacing.minTarget, alignment: .leading)
                }
            }
        } header: { SchoolSectionHeader(title: "Нове", systemImage: "envelope.badge", count: store.items.filter(\.unread).count) }
    }

    private func upcomingSection(events: [SchoolHubEvent]) -> some View {
        let horizon = SchoolHubLogic.addDays(14, to: today) ?? today
        let upcoming = events.filter { event in
            guard SchoolHubLogic.isDayRelevant(event), let key = SchoolHubLogic.dayKey(for: event.startsAt, allDay: event.allDay) else { return false }
            return key > tomorrow && key <= horizon
        }.sorted { ($0.startsAt ?? "") < ($1.startsAt ?? "") }.prefix(5)
        return Section {
            if upcoming.isEmpty { SchoolNotice(text: store.calendarPhase == .loaded ? "У завантаженому календарі найближчих 14 днів подій немає." : "Календар не завантажено.", systemImage: "calendar") }
            ForEach(Array(upcoming)) { event in
                if let source = store.calendarEvent(uid: event.uid) {
                    NavigationLink { SchoolEventDetailView(event: source) } label: { SchoolEventRow(event: event, showDay: true) }
                }
            }
        } header: { SchoolSectionHeader(title: "Найближчі події", systemImage: "calendar.badge.clock") }
    }
}

// MARK: - Rows

private struct SchoolEventRow: View {
    let event: SchoolHubEvent
    var showDay = false
    var body: some View {
        let relevance = SchoolHubLogic.relevance(of: event)
        VStack(alignment: .leading, spacing: 4) {
            Text(event.title).font(.headline).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                if showDay, let key = SchoolHubLogic.dayKey(for: event.startsAt, allDay: event.allDay) { Text(SchoolHubFormat.long(key)) ; Text("·") }
                Text(SchoolHubFormat.time(event))
                if !event.location.isEmpty { Text("· \(event.location)").lineLimit(1) }
            }.font(.subheadline).foregroundStyle(.secondary)
            SchoolRelevanceMarker(relevance: relevance)
        }
        .frame(minHeight: OrbitSpacing.minTarget, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct SchoolTaskRow: View {
    let store: SchoolHubStore
    let task: SchoolHubTask
    var overdue = false

    var body: some View {
        let item = store.item(id: task.sourceItemId)
        let evidence = SchoolHubLogic.evidence(forTask: task, sourceLoaded: item != nil, activeNames: store.studentNames, sourceText: item?.originalPlainText ?? item?.originalGerman ?? "")
        let row = VStack(alignment: .leading, spacing: 5) {
            Text(task.title).font(.headline).fixedSize(horizontal: false, vertical: true)
            if let action = task.action, action != task.title { Text(action).font(.subheadline).fixedSize(horizontal: false, vertical: true) }
            HStack(spacing: 6) {
                if let due = SchoolHubFormat.due(task) { Label(due, systemImage: overdue ? "clock.badge.exclamationmark" : "calendar").foregroundStyle(overdue ? Color.red : Color.secondary) }
                else { Label("Без дати", systemImage: "calendar.badge.questionmark").foregroundStyle(.secondary) }
                if let target = task.target, !target.isEmpty { Text("· \(target)").foregroundStyle(.secondary) }
            }.font(.caption)
            if let reason = task.reason, !reason.isEmpty { Text(reason).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            HStack(spacing: 6) {
                SchoolEvidenceBadge(evidence: evidence)
                if let item { Label(item.type == "letter" ? "Лист" : "Повідомлення", systemImage: item.type == "letter" ? "envelope" : "message").font(.caption).foregroundStyle(.secondary) }
            }
            if let conflict = SchoolHubLogic.nameConflict(in: (item?.originalPlainText ?? item?.originalGerman ?? "") + " " + task.title, activeNames: store.studentNames) {
                Label("У тексті згадано «\(conflict)» — перевірте, що це про вашу дитину.", systemImage: "person.fill.questionmark").font(.caption).foregroundStyle(.orange)
            }
        }
        .frame(minHeight: OrbitSpacing.minTarget, alignment: .leading)
        if let item { NavigationLink { SchoolDetailView(item: item) } label: { row } } else { row }
    }
}

// MARK: - Tasks

private struct SchoolTaskListView: View {
    let store: SchoolHubStore
    var body: some View {
        let today = SchoolHubLogic.dayKey(of: Date())
        let groups = SchoolHubLogic.groupTasks(store.hubTasks, today: today, sourceDates: store.sourceDates, now: Date())
        List {
            if store.itemsPhase == .failed {
                Section { SchoolNotice(text: store.itemsLoadedOnce ? "Не вдалося оновити задачі — показано раніше завантажене." : "Не вдалося завантажити задачі.", systemImage: "exclamationmark.triangle.fill"); Button("Повторити") { Task { await store.load() } }.frame(minHeight: OrbitSpacing.minTarget) }
            } else if store.itemsPhase == .loading && !store.itemsLoadedOnce {
                Section { ProgressView().frame(maxWidth: .infinity) }
            }
            Section { SchoolNotice(text: "Позначити виконання поки неможливо: Orbit ще не має спільного сховища виконання. Задачі лишаються відкритими.", systemImage: "info.circle") }
            group("З датою", systemImage: "calendar", tasks: groups.dated)
            group("Прострочені", systemImage: "clock.badge.exclamationmark", tasks: groups.overdue, overdue: true)
            group("Без дати", systemImage: "calendar.badge.questionmark", tasks: groups.undated)
            if !groups.undatedOlder.isEmpty {
                Section { DisclosureGroup("Старіші без дати (\(groups.undatedOlder.count)) · лишаються відкритими") { ForEach(groups.undatedOlder) { SchoolTaskRow(store: store, task: $0) } }.frame(minHeight: OrbitSpacing.minTarget) }
            }
            if store.itemsPhase == .loaded && store.hubTasks.isEmpty {
                ContentUnavailableView("Задач у завантажених листах немає", systemImage: "checklist", description: Text("Це лише те, що Orbit уже отримав зі школи."))
            }
        }
        .refreshable { await store.load() }
    }

    @ViewBuilder private func group(_ title: String, systemImage: String, tasks: [SchoolHubTask], overdue: Bool = false) -> some View {
        if !tasks.isEmpty {
            Section { ForEach(tasks) { SchoolTaskRow(store: store, task: $0, overdue: overdue) } } header: { SchoolSectionHeader(title: title, systemImage: systemImage, count: tasks.count) }
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
        List {
            Section {
                weekStrip(week: week, events: filtered)
                Picker("Фільтр подій", selection: $filter) { ForEach(SchoolEventFilter.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
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
            } header: { SchoolSectionHeader(title: SchoolHubFormat.long(selected), systemImage: "list.bullet", count: dayEvents.count) }
            let undated = SchoolHubLogic.undatedEvents(filtered)
            if !undated.isEmpty {
                Section { ForEach(undated) { event in if let source = store.calendarEvent(uid: event.uid) { NavigationLink { SchoolEventDetailView(event: source) } label: { SchoolEventRow(event: event) } } } } header: { SchoolSectionHeader(title: "Без дати", systemImage: "calendar.badge.questionmark", count: undated.count) }
            }
        }
        .refreshable { await store.load() }
    }

    private func weekStrip(week: [String], events: [SchoolHubEvent]) -> some View {
        HStack(spacing: 2) {
            stepButton("chevron.left", label: "Попередній тиждень", days: -7)
            ForEach(week, id: \.self) { day in
                let count = SchoolHubLogic.events(events, on: day).count
                let isSelected = day == selected
                Button { withAnimation(.easeOut(duration: 0.15)) { selected = day } } label: {
                    VStack(spacing: 2) {
                        Text(SchoolHubFormat.weekday(day)).font(.caption2)
                        Text(SchoolHubFormat.dayNumber(day)).font(.callout.weight(.semibold))
                        Circle().fill(count > 0 ? (isSelected ? Color.white : Color.accentColor) : .clear).frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity, minHeight: OrbitSpacing.minTarget)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .background(isSelected ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: OrbitRadius.chip))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(SchoolHubFormat.long(day)), подій: \(count)")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
            stepButton("chevron.right", label: "Наступний тиждень", days: 7)
        }
        .sensoryFeedback(.selection, trigger: selected)
    }

    private func stepButton(_ icon: String, label: String, days: Int) -> some View {
        Button { withAnimation(.easeOut(duration: 0.15)) { selected = SchoolHubLogic.addDays(days, to: selected) ?? selected } } label: {
            Image(systemName: icon).frame(width: 28, height: OrbitSpacing.minTarget)
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
                Section { ForEach(tasks) { SchoolTaskRow(store: store, task: $0) } } header: { SchoolSectionHeader(title: "Задачі", systemImage: "checklist", count: tasks.count) }
            }
        }
    }
}
