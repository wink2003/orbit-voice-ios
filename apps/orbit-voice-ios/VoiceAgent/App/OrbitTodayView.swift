import SwiftUI

/// Nova Today: a compact, source-backed family rhythm. This view intentionally
/// does not own task completion or any consequential action.
struct OrbitTodayView: View {
    let open: (OrbitMainTab) -> Void
    let displayName: String?
    let fixture: NovaTodayFixture?

    @State private var calendar: OrbitSourceState<[OrbitCalendarEvent]> = .loading
    @State private var school: OrbitSourceState<OrbitSchoolItemsResponse> = .loading
    @State private var tasks: OrbitSourceState<OrbitSchoolTasksResponse> = .loading
    @State private var loadedAt: Date?

    init(open: @escaping (OrbitMainTab) -> Void, displayName: String? = nil, fixture: NovaTodayFixture? = nil) {
        self.open = open
        self.displayName = displayName
        self.fixture = fixture
    }

    private var today: Date { Date() }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    compactHeader
                    focusBand
                    glance
                    rhythm
                    schoolSignal
                    preparation
                    freshness
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(NovaTodayTokens.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await load() }
            .task { await load() }
        }
    }

    private var compactHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("ORBIT FAMILY")
                    .font(.caption.weight(.bold))
                    .tracking(2.2)
                    .foregroundStyle(NovaTodayTokens.indigo)
                Text(today, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .environment(\.locale, Locale(identifier: "uk_UA"))
                Text(OrbitTodayLogic.greeting(
                    hour: Calendar.current.component(.hour, from: today),
                    name: displayName?.split(separator: " ").first.map(String.init)
                ))
                .font(.system(.title2, design: .rounded).weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            NavigationLink { OrbitVoiceSheet() } label: {
                Image(systemName: "waveform")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(NovaTodayTokens.indigo, in: Circle())
            }
            .accessibilityLabel("Почати голосову розмову")
        }
        .accessibilityElement(children: .combine)
    }

    private var focusBand: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("DAY IN FOCUS")
                        .font(.caption2.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(.white.opacity(0.76))
                    Text(focusTitle)
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Image(systemName: focusIcon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.16), in: Circle())
            }
            Text(focusDetail)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.84))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Запитати Orbit") { open(.orbit) }
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(NovaTodayTokens.indigo)
                    .frame(minHeight: 40)
                    .padding(.horizontal, 13)
                    .background(.white, in: Capsule())
                NavigationLink { OrbitVoiceSheet() } label: {
                    Image(systemName: "waveform")
                        .frame(width: 40, height: 40)
                        .foregroundStyle(.white)
                        .background(.white.opacity(0.16), in: Circle())
                }
                .accessibilityLabel("Голос до Orbit")
            }
        }
        .padding(17)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [NovaTodayTokens.night, NovaTodayTokens.indigo, NovaTodayTokens.coral],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay(alignment: .bottomTrailing) {
            Circle()
                .stroke(.white.opacity(0.16), lineWidth: 18)
                .frame(width: 130, height: 130)
                .offset(x: 42, y: 45)
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var glance: some View {
        VStack(alignment: .leading, spacing: 10) {
            NovaTodaySectionHeader(eyebrow: "AT A GLANCE", title: "Only what is useful") { EmptyView() }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 9) {
                    NovaGlanceItem(icon: "graduationcap", tint: NovaTodayTokens.teal, title: schoolGlanceTitle, detail: "Школа") { open(.school) }
                    NovaGlanceItem(icon: "checkmark.circle", tint: NovaTodayTokens.coral, title: taskGlanceTitle, detail: "Підготовка") { open(.school) }
                    NavigationLink { OrbitCalendarView() } label: {
                        NovaGlanceLabel(icon: "calendar", tint: NovaTodayTokens.indigo, title: "Ритм сім’ї", detail: "Календар")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var rhythm: some View {
        VStack(alignment: .leading, spacing: 10) {
            NovaTodaySectionHeader(eyebrow: "FAMILY RHYTHM", title: "Найближче") {
                NavigationLink("Календар") { OrbitCalendarView() }
            }
            NovaTimelineSurface {
                switch calendar {
                case .loading: NovaLoadingRows()
                case .unavailable: NovaStateRow(icon: "lock.slash", text: "Календар недоступний для цього профілю.")
                case let .failed(message): NovaFailureRow(message: message, retry: retry)
                case .empty: NovaStateRow(icon: "calendar", text: "На сьогодні подій немає.")
                case let .loaded(events, stale):
                    if stale { NovaStaleLabel() }
                    let visible = events.filter { OrbitTodayLogic.overlapsDay(start: $0.startsAt, end: $0.endsAt, day: today) }.sorted { $0.startsAt < $1.startsAt }
                    if visible.isEmpty { NovaStateRow(icon: "calendar", text: "На сьогодні подій немає.") }
                    else { ForEach(Array(visible.prefix(4))) { event in NovaTimelineRow(event: event) } }
                }
            }
        }
    }

    private var schoolSignal: some View {
        VStack(alignment: .leading, spacing: 10) {
            NovaTodaySectionHeader(eyebrow: "SCHOOL · SOURCE", title: "Потрібно знати") {
                Button("Відкрити") { open(.school) }
            }
            switch school {
            case .loading: NovaSourceSurface(tint: NovaTodayTokens.teal) { NovaLoadingRows() }
            case .unavailable: NovaSourceSurface(tint: NovaTodayTokens.teal) { NovaStateRow(icon: "lock.slash", text: "Шкільні дані недоступні для цього профілю.") }
            case let .failed(message): NovaSourceSurface(tint: NovaTodayTokens.teal) { NovaFailureRow(message: message, retry: retry) }
            case .empty: NovaSourceSurface(tint: NovaTodayTokens.teal) { NovaStateRow(icon: "envelope", text: "Нових шкільних матеріалів немає.") }
            case let .loaded(value, stale):
                if let item = value.items.first(where: { $0.unread }) ?? value.items.first {
                    NavigationLink { SchoolDetailView(item: item) } label: { NovaSchoolSource(item: item, stale: stale, unreadCount: value.unreadCount) }.buttonStyle(.plain)
                } else {
                    NovaSourceSurface(tint: NovaTodayTokens.teal) { NovaStateRow(icon: "checkmark.circle", text: "Наразі немає нових шкільних матеріалів.") }
                }
            }
        }
    }

    private var preparation: some View {
        VStack(alignment: .leading, spacing: 10) {
            NovaTodaySectionHeader(eyebrow: "PREPARE", title: "Справи з джерел") {
                Button("Школа") { open(.school) }
            }
            switch tasks {
            case .loading: NovaSourceSurface(tint: NovaTodayTokens.coral) { NovaLoadingRows() }
            case .unavailable: NovaSourceSurface(tint: NovaTodayTokens.coral) { NovaStateRow(icon: "lock.slash", text: "Справи школи недоступні для цього профілю.") }
            case let .failed(message): NovaSourceSurface(tint: NovaTodayTokens.coral) { NovaFailureRow(message: message, retry: retry) }
            case .empty: NovaSourceSurface(tint: NovaTodayTokens.coral) { NovaStateRow(icon: "checkmark.circle", text: "Відкритих справ із завантажених джерел немає.") }
            case let .loaded(value, stale):
                NovaSourceSurface(tint: NovaTodayTokens.coral) {
                    if stale { NovaStaleLabel() }
                    let visible = dueTasks(from: value.tasks)
                    if visible.isEmpty { NovaStateRow(icon: "checkmark.circle", text: "Немає справ, релевантних сьогодні.") }
                    else { ForEach(Array(visible.prefix(3))) { task in NovaPreparationRow(task: task, source: school.value?.items.first { $0.id == task.sourceItemId }, open: open) } }
                }
            }
        }
    }

    private var freshness: some View {
        Group {
            if let label = OrbitFreshness.label(from: loadedAt) {
                Label("Дані оновлено (label)", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private var focusTitle: String {
        if let event = nextEvent { return event.title }
        if unreadCount > 0 { return "Шкільні оновлення чекають" }
        return "День у фокусі"
    }
    private var focusDetail: String {
        if let event = nextEvent { return event.allDay ? "Подія сьогодні · весь день" : event.startsAt.formatted(date: .omitted, time: .shortened) }
        if unreadCount > 0 { return OrbitTodayLogic.unreadLabel(unreadCount) }
        return "Показано лише дані з доступних авторизованих джерел."
    }
    private var focusIcon: String { nextEvent == nil ? "sparkles" : "calendar" }
    private var nextEvent: OrbitCalendarEvent? {
        guard case let .loaded(events, _) = calendar else { return nil }
        return events.filter { OrbitTodayLogic.overlapsDay(start: $0.startsAt, end: $0.endsAt, day: today) }.sorted { $0.startsAt < $1.startsAt }.first
    }
    private var unreadCount: Int { school.value?.unreadCount ?? 0 }
    private var schoolGlanceTitle: String { unreadCount == 0 ? "Немає нового" : "\(unreadCount) нових" }
    private var taskGlanceTitle: String {
        guard case let .loaded(value, _) = tasks else { return "Перевірити" }
        return "\(dueTasks(from: value.tasks).count) відкритих"
    }
    private func dueTasks(from input: [OrbitSchoolTask]) -> [OrbitSchoolTask] {
        let todayKey = SchoolHubLogic.dayKey(of: today)
        return input.filter { guard let due = SchoolHubLogic.dayKey(for: $0.dueAt, allDay: $0.allDay) else { return false }; return due <= todayKey }.sorted { ($0.dueAt ?? "") < ($1.dueAt ?? "") }
    }
    private func retry() { Task { await load() } }
    private func load() async {
        if let fixture {
            calendar = .loaded(fixture.calendar, stale: false)
            school = .loaded(fixture.school, stale: false)
            tasks = .loaded(fixture.tasks, stale: false)
            loadedAt = fixture.loadedAt
            return
        }
        let start = Calendar.current.startOfDay(for: today)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? today
        async let calendarResult = fetch { try await MainProductAPI.shared.calendarEvents(from: start, to: end, classifyUnavailable: true) }
        async let schoolResult = fetch { try await MainProductAPI.shared.schoolItems(classifyUnavailable: true) }
        async let taskResult = fetch { try await MainProductAPI.shared.schoolTasks() }
        let results = await (calendarResult, schoolResult, taskResult)
        calendar = OrbitSourceStateBuilder.resolve(result: results.0, isEmpty: { $0.isEmpty }, previous: calendar, isUnavailable: isUnavailable)
        school = OrbitSourceStateBuilder.resolve(result: results.1, isEmpty: { $0.items.isEmpty && $0.unreadCount == 0 }, previous: school, isUnavailable: isUnavailable)
        tasks = OrbitSourceStateBuilder.resolve(result: results.2, isEmpty: { $0.tasks.isEmpty }, previous: tasks, isUnavailable: isUnavailable)
        loadedAt = Date()
    }
    private func isUnavailable(_ error: Error) -> Bool { error is OrbitHTTPFailure }
    private func fetch<T>(_ work: @escaping () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await work()) } catch { return .failure(error) }
    }
}

struct NovaTodayFixture {
    let calendar: [OrbitCalendarEvent]
    let school: OrbitSchoolItemsResponse
    let tasks: OrbitSchoolTasksResponse
    let loadedAt: Date

#if DEBUG
    static let demo: NovaTodayFixture = {
        let now = Date()
        let end = Calendar.current.date(byAdding: .hour, value: 1, to: now) ?? now
        let event = OrbitCalendarEvent(
            id: "nova-fixture-event", familyId: "fixture-family", ownerPersonId: "fixture-person",
            title: "Abholung · Lina", notes: "Synthetic fixture", startsAt: now, endsAt: end,
            allDay: false, sourceType: "family", sourceIdentifier: nil, sourceName: "Familienkalender",
            sourceColor: nil, createdAt: now, updatedAt: now
        )
        let item = OrbitSchoolItem(
            id: "nova-fixture-letter", type: "letter", source: "demo", externalId: "fixture-letter",
            title: "Elternabend · wichtige Informationen", sender: "Grundschule am Park",
            originalGerman: "Dies ist eine synthetische Vorschau und keine Schulnachricht.",
            originalPlainText: "Dies ist eine synthetische Vorschau und keine Schulnachricht.",
            previewPlainText: "Synthetische Vorschau: Original und Übersetzung bleiben getrennt.",
            titlePlainText: "Elternabend · wichtige Informationen", translationUkrainian: "Синтетичний попередній перегляд.",
            important: "DEMO DATA · Це не справжній обов’язок.", sourceTimestamp: now, importedAt: now,
            orbitReadAt: nil, unread: true, attachments: [], events: [], threadId: nil, subscriptionId: nil, tasks: nil
        )
        let task = OrbitSchoolTask(
            key: "prepare", title: "Перевірити інформацію в листі", action: "Відкрити оригінал",
            dueAt: ISO8601DateFormatter().string(from: now), endsAt: nil, allDay: false,
            importance: "normal", target: nil, confidence: 1, reason: "Synthetic fixture",
            location: nil, sourceItemId: item.id, sourceType: "demo", sourceExternalId: item.externalId
        )
        return NovaTodayFixture(
            calendar: [event], school: OrbitSchoolItemsResponse(items: [item], unreadCount: 1),
            tasks: OrbitSchoolTasksResponse(from: "demo", to: "demo", tasks: [task], importantEvents: []), loadedAt: now
        )
    }()
#endif
}

enum NovaTodayTokens {
    static let indigo = Color(red: 0.28, green: 0.30, blue: 0.82)
    static let teal = Color(red: 0.03, green: 0.52, blue: 0.50)
    static let coral = Color(red: 0.84, green: 0.35, blue: 0.24)
    static let night = Color(red: 0.10, green: 0.13, blue: 0.28)
    static let canvas = Color(uiColor: UIColor { traits in traits.userInterfaceStyle == .dark ? UIColor(red: 0.045, green: 0.05, blue: 0.07, alpha: 1) : UIColor(red: 0.965, green: 0.968, blue: 0.982, alpha: 1) })
    static let surface = Color(uiColor: .systemBackground)
}

private struct NovaTodaySectionHeader<Accessory: View>: View {
    let eyebrow: String
    let title: String
    let accessory: () -> Accessory
    init(eyebrow: String, title: String, @ViewBuilder accessory: @escaping () -> Accessory) { self.eyebrow = eyebrow; self.title = title; self.accessory = accessory }
    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) { Text(eyebrow).font(.caption2.weight(.bold)).tracking(1.4).foregroundStyle(.secondary); Text(title).font(.title3.weight(.bold)) }
            Spacer(minLength: 8)
            accessory().font(.footnote.weight(.semibold)).foregroundStyle(NovaTodayTokens.indigo).frame(minHeight: 44)
        }
    }
}

private struct NovaGlanceItem: View {
    let icon: String; let tint: Color; let title: String; let detail: String; let action: () -> Void
    var body: some View { Button(action: action) { NovaGlanceLabel(icon: icon, tint: tint, title: title, detail: detail) }.buttonStyle(.plain) }
}

private struct NovaGlanceLabel: View {
    let icon: String; let tint: Color; let title: String; let detail: String
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon).font(.subheadline.weight(.semibold)).foregroundStyle(tint).frame(width: 34, height: 34).background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 2) { Text(title).font(.subheadline.weight(.semibold)).lineLimit(1); Text(detail).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(11).frame(minWidth: 160, minHeight: 64, alignment: .leading)
        .background(NovaTodayTokens.surface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(.primary.opacity(0.08), lineWidth: 1) }
    }
}

private struct NovaTimelineSurface<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View { VStack(alignment: .leading, spacing: 0) { content }.padding(.vertical, 4).background(NovaTodayTokens.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous)).overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.primary.opacity(0.08), lineWidth: 1) } }
}

private struct NovaSourceSurface<Content: View>: View {
    let tint: Color; let content: Content
    init(tint: Color, @ViewBuilder content: () -> Content) { self.tint = tint; self.content = content() }
    var body: some View { content.padding(15).frame(maxWidth: .infinity, alignment: .leading).background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous)).overlay(alignment: .leading) { Rectangle().fill(tint).frame(width: 4).clipShape(Capsule()).padding(.vertical, 15) }.overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(tint.opacity(0.18), lineWidth: 1) } }
}

private struct NovaTimelineRow: View {
    let event: OrbitCalendarEvent
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 4) { Text(event.allDay ? "ALL" : event.startsAt.formatted(date: .omitted, time: .shortened)).font(.caption2.weight(.bold).monospacedDigit()).foregroundStyle(NovaTodayTokens.indigo); Circle().fill(NovaTodayTokens.indigo).frame(width: 7, height: 7) }.frame(width: 52)
            VStack(alignment: .leading, spacing: 3) { Text(event.title).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true); if let source = event.sourceName, !source.isEmpty { Text(source).font(.caption).foregroundStyle(.secondary) } }
            Spacer(minLength: 0)
        }.frame(minHeight: 52, alignment: .center).padding(.horizontal, 14).accessibilityElement(children: .combine)
    }
}

private struct NovaSchoolSource: View {
    let item: OrbitSchoolItem; let stale: Bool; let unreadCount: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Label(item.type == "letter" ? "ORIGINAL SOURCE" : "SCHOOL MESSAGE", systemImage: item.type == "letter" ? "envelope" : "bubble.left").font(.caption2.weight(.bold)).tracking(1.1).foregroundStyle(NovaTodayTokens.teal); Spacer(); if item.unread { Text("UNREAD").font(.caption2.weight(.bold)).foregroundStyle(NovaTodayTokens.coral) } }
            Text(item.titlePlainText?.isEmpty == false ? item.titlePlainText! : item.title).font(.headline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            Text(item.important ?? item.previewPlainText ?? item.sender).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
            HStack(spacing: 8) { if !item.sender.isEmpty { Text(item.sender) }; if stale { Text("· застаріло") }; if unreadCount > 1 { Text("· \(unreadCount) нових") } }.font(.caption).foregroundStyle(.secondary)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(NovaTodayTokens.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous)).overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(NovaTodayTokens.teal.opacity(0.24), lineWidth: 1) }
    }
}

private struct NovaPreparationRow: View {
    let task: OrbitSchoolTask; let source: OrbitSchoolItem?; let open: (OrbitMainTab) -> Void
    var body: some View { Group { if let source { NavigationLink { SchoolDetailView(item: source) } label: { row } } else { Button { open(.school) } label: { row } } }.buttonStyle(.plain) }
    private var row: some View {
        HStack(alignment: .top, spacing: 11) { Circle().stroke(NovaTodayTokens.coral, lineWidth: 2).frame(width: 22, height: 22).padding(.top, 1); VStack(alignment: .leading, spacing: 3) { Text(task.title).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true); Text(taskDate).font(.caption).foregroundStyle(.secondary) }; Spacer(minLength: 0); Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary) }.frame(minHeight: 44, alignment: .center).accessibilityElement(children: .combine).accessibilityLabel("Відкрита шкільна справа: \(task.title). \(taskDate)")
    }
    private var taskDate: String { guard let due = task.dueAt, let date = OrbitSchoolDateDecoding.date(from: due) else { return "Термін не вказано" }; return "Термін: " + date.formatted(date: .abbreviated, time: .omitted) }
}

private struct NovaLoadingRows: View {
    var body: some View { VStack(alignment: .leading, spacing: 10) { RoundedRectangle(cornerRadius: 5).fill(.secondary.opacity(0.14)).frame(height: 13); RoundedRectangle(cornerRadius: 5).fill(.secondary.opacity(0.10)).frame(width: 190, height: 13) }.redacted(reason: .placeholder).frame(minHeight: 44, alignment: .leading) }
}
private struct NovaStateRow: View { let icon: String; let text: String; var body: some View { Label(text, systemImage: icon).font(.subheadline).foregroundStyle(.secondary).frame(minHeight: 44, alignment: .leading) } }
private struct NovaFailureRow: View { let message: String; let retry: () -> Void; var body: some View { VStack(alignment: .leading, spacing: 8) { Text(message).font(.subheadline).foregroundStyle(.secondary); Button("Повторити", action: retry).buttonStyle(.bordered) } } }
private struct NovaStaleLabel: View { var body: some View { Label("Не вдалося оновити — показано попередні дані", systemImage: "clock.badge.exclamationmark").font(.caption).foregroundStyle(.orange) } }
