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
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                    Routes05Mast(section: "core") { open(.orbit) }
                    routesHeader
                    routesNextUp
                    routesSchedule
                    routesTasks
                    routesMessages
                        freshness
                        Color.clear.frame(height: 1).id("routes05-bottom")
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .safeAreaPadding(.bottom, 96)
                .onAppear {
                    guard Routes05DebugCapture.scrollToBottom else { return }
                    DispatchQueue.main.async { proxy.scrollTo("routes05-bottom", anchor: .bottom) }
                }
            }
            .background(Routes05Tokens.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await load() }
            .task { await load() }
        }
    }

    private var routesHeader: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 8) {
                Text(today.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased())
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(Routes05Tokens.secondary)
                Text("Ваш день.\nБез шуму.")
                    .font(.system(.largeTitle, design: .rounded).weight(.black))
                    .tracking(-1.8)
                    .lineSpacing(-4)
                Text("Один маршрут для всього, що має значення.")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Routes05Tokens.secondary)
                    .lineLimit(2)
            }
            Text("↗")
                .font(.system(size: 29, weight: .black))
                .foregroundStyle(Routes05Tokens.accentInk)
                .frame(width: 59, height: 59)
                .background(Routes05Tokens.mint, in: Circle())
                .overlay(Circle().stroke(Routes05Tokens.ink, lineWidth: 2))
        }
        .padding(.horizontal, 16)
        .environment(\.locale, Locale(identifier: "uk_UA"))
    }

    private var routesNextUp: some View {
        Routes05Hero(accent: Routes05Tokens.yellow) {
            VStack(alignment: .leading, spacing: 10) {
                Text("NEXT UP / SCHOOL")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .tracking(1.4)
                Text(unreadCount > 0 ? "Дві новини\nзі школи" : "Шкільний маршрут")
                    .font(.system(.title, design: .rounded).weight(.black))
                    .tracking(-1.1)
                    .fixedSize(horizontal: false, vertical: true)
                Text(unreadCount > 0 ? "Доступні нові повідомлення зі Schulmanager." : "Нових повідомлень зі школи немає.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Routes05Tokens.accentInk.opacity(0.78))
                Button("ПЕРЕГЛЯНУТИ →") { open(.school) }
                    .font(.caption.weight(.black))
                    .foregroundStyle(Routes05Tokens.accentInk)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 36)
                    .background(Routes05Tokens.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            }
        }
    }

    private var routesSchedule: some View {
        VStack(alignment: .leading, spacing: 8) {
            Routes05SectionHeader("Далі за планом", action: "Увесь день") { open(.calendar) }
            switch calendar {
            case .loading: Routes05StateRow(text: "Завантажуємо календар…", tint: Routes05Tokens.blue)
            case .unavailable: Routes05StateRow(text: "Календар недоступний для цього профілю.", tint: Routes05Tokens.blue)
            case let .failed(message): Routes05StateRow(text: message, tint: Routes05Tokens.orange)
            case .empty: Routes05StateRow(text: "Подій у доступному календарі немає.", tint: Routes05Tokens.blue)
            case let .loaded(events, _):
                let visible = events.filter { OrbitTodayLogic.overlapsDay(start: $0.startsAt, end: $0.endsAt, day: today) }.sorted { $0.startsAt < $1.startsAt }
                if visible.isEmpty { Routes05StateRow(text: "Подій на сьогодні немає.", tint: Routes05Tokens.blue) }
                else {
                    ForEach(Array(visible.prefix(4))) { event in
                        Routes05IndexedRow(index: Routes05DisplayFormat.compactTime(event.startsAt), tint: Routes05Tokens.blue, indexWidth: 68) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.title).font(.subheadline.weight(.bold)).lineLimit(2)
                                Text(event.allDay ? "Весь день" : Routes05DisplayFormat.compactTime(event.startsAt))
                                    .font(.caption).foregroundStyle(Routes05Tokens.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var routesTasks: some View {
        VStack(alignment: .leading, spacing: 8) {
            Routes05SectionHeader("Маленькі справи", action: "Переглянути") { open(.school) }
            let count: Int = {
                guard case let .loaded(value, _) = tasks else { return 0 }
                return value.tasks.filter { $0.status != "completed" }.count
            }()
            Button { open(.school) } label: {
                HStack(spacing: 0) {
                    Text(String(format: "%02d", count))
                        .font(.system(size: 42, weight: .black, design: .rounded))
                        .frame(width: 88).frame(maxHeight: .infinity)
                        .foregroundStyle(Routes05Tokens.accentInk)
                        .background(Routes05Tokens.orange)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(count == 0 ? "На сьогодні" : "Відкриті справи").font(.headline.weight(.black))
                        Text(count == 0 ? "Усе під контролем" : "Потребують уваги").font(.caption).foregroundStyle(Routes05Tokens.secondary)
                        Text(count == 0 ? "0 / завершено" : "\(count) / у роботі")
                            .font(.caption.weight(.bold)).padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Routes05Tokens.mint, in: RoundedRectangle(cornerRadius: 2))
                    }
                    .padding(12)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 94, alignment: .leading)
                .background(Routes05Tokens.surface)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Routes05Tokens.ink, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
    }

    private var routesMessages: some View {
        VStack(alignment: .leading, spacing: 8) {
            Routes05SectionHeader("На зв’язку", action: "Вхідні") { open(.school) }
            switch school {
            case .loading: Routes05StateRow(text: "Завантажуємо вхідні…", tint: Routes05Tokens.mint)
            case .unavailable: Routes05StateRow(text: "Шкільні дані недоступні для цього профілю.", tint: Routes05Tokens.mint)
            case let .failed(message): Routes05StateRow(text: message, tint: Routes05Tokens.orange)
            case .empty: Routes05StateRow(text: "Нових шкільних матеріалів немає.", tint: Routes05Tokens.mint)
            case let .loaded(value, _):
                if let item = value.items.first(where: { $0.unread }) ?? value.items.first {
                    NavigationLink { SchoolDetailView(item: item) } label: {
                        Routes05Ticket(tint: Routes05Tokens.mint) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title.isEmpty ? "Повідомлення зі школи" : item.title).font(.subheadline.weight(.bold)).lineLimit(2)
                                Text(item.sender.isEmpty ? "Schulmanager · read only" : item.sender).font(.caption).foregroundStyle(Routes05Tokens.secondary)
                            }
                        }
                    }.buttonStyle(.plain)
                } else { Routes05StateRow(text: "Нових шкільних матеріалів немає.", tint: Routes05Tokens.mint) }
            }
        }
        .padding(.horizontal, 16)
    }

    private var compactHeader: some View {
        Routes05Chapter(
            today.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased(),
            title: "Ваш день.",
            detail: OrbitTodayLogic.greeting(hour: Calendar.current.component(.hour, from: today), name: displayName?.split(separator: " ").first.map(String.init)),
            accent: Routes05Tokens.mint
        )
        .environment(\.locale, Locale(identifier: "uk_UA"))
    }

    private var focusBand: some View {
        Routes05Hero(accent: Routes05Tokens.yellow) {
            VStack(alignment: .leading, spacing: 11) {
                Text("NEXT UP / ROUTE 01").font(.system(size: 10, weight: .black, design: .monospaced)).tracking(1.5)
                Text(focusTitle).font(.system(.title, design: .rounded).weight(.black)).tracking(-1.3).fixedSize(horizontal: false, vertical: true)
                Text(focusDetail).font(.subheadline).foregroundStyle(Routes05Tokens.ink.opacity(0.72))
                Button("Запитати Orbit →") { open(.orbit) }
                    .font(.footnote.weight(.black)).foregroundStyle(.white).padding(.horizontal, 10).frame(minHeight: 36).background(Routes05Tokens.blue).cornerRadius(2)
            }
        }
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
                    let visible = taskPreview(from: value.tasks)
                    if visible.isEmpty { NovaStateRow(icon: "checkmark.circle", text: "Немає справ, релевантних сьогодні.") }
                    else { ForEach(Array(visible.prefix(3))) { task in NovaPreparationRow(task: task, source: school.value?.items.first { $0.id == task.sourceItemId }, open: open) } }
                }
            }
        }
    }

    private var freshness: some View {
        Group {
            if let label = OrbitFreshness.label(from: loadedAt) {
                Label("Дані оновлено \(label)", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .center)
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
        return "\(openTasks(from: value.tasks).count) відкритих"
    }
    private func openTasks(from input: [OrbitSchoolTask]) -> [OrbitSchoolTask] {
        input.filter { $0.status != "completed" }
    }
    private func taskPreview(from input: [OrbitSchoolTask]) -> [OrbitSchoolTask] {
        let todayKey = SchoolHubLogic.dayKey(of: today)
        let open = openTasks(from: input)
        return open.sorted { lhs, rhs in
            let left = SchoolHubLogic.dayKey(for: lhs.dueAt, allDay: lhs.allDay)
            let right = SchoolHubLogic.dayKey(for: rhs.dueAt, allDay: rhs.allDay)
            let leftRank = left.map { $0 <= todayKey ? "0\($0)" : "1\($0)" } ?? "2"
            let rightRank = right.map { $0 <= todayKey ? "0\($0)" : "1\($0)" } ?? "2"
            return leftRank != rightRank ? leftRank < rightRank : lhs.id < rhs.id
        }
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
        async let taskResult = fetch { try await MainProductAPI.shared.schoolTasks(coverage: "all") }
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
            key: "prepare", stableIdentity: true, title: "Перевірити інформацію в листі", action: "Відкрити оригінал",
            dueAt: ISO8601DateFormatter().string(from: now), endsAt: nil, allDay: false,
            importance: "normal", target: nil, confidence: 1, reason: "Synthetic fixture",
            location: nil, sourceItemId: item.id, sourceType: "demo", sourceExternalId: item.externalId,
            bucket: nil, status: nil, completedAt: nil, actionTaskId: nil, calendarEventId: nil
        )
        return NovaTodayFixture(
            calendar: [event], school: OrbitSchoolItemsResponse(items: [item], unreadCount: 1),
            tasks: OrbitSchoolTasksResponse(from: "demo", to: "demo", coverage: "all", truncated: false, complete: true, completionState: nil, tasks: [task], importantEvents: []), loadedAt: now
        )
    }()
#endif
}

enum NovaTodayTokens {
    static let indigo = Routes05Tokens.blue
    static let teal = Routes05Tokens.mint
    static let coral = Routes05Tokens.orange
    static let night = Color(red: 0.10, green: 0.13, blue: 0.28)
    static let canvas = Routes05Tokens.canvas
    static let surface = Routes05Tokens.surface
}

/// Shared Nova presentation primitives. They intentionally contain no data or
/// action policy, so every destination keeps its existing authorized store.
struct NovaSurface<Content: View>: View {
    let tint: Color
    let content: Content

    init(tint: Color = NovaTodayTokens.indigo, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NovaTodayTokens.surface, in: RoundedRectangle(cornerRadius: 4))
            .overlay(alignment: .leading) {
                Capsule().fill(tint).frame(width: 4).padding(.vertical, 15)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(tint.opacity(0.18), lineWidth: 1)
            }
    }
}

struct NovaScreenHeading: View {
    let eyebrow: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(eyebrow).font(.caption.weight(.bold)).tracking(1.5).foregroundStyle(NovaTodayTokens.indigo)
            Text(title).font(.system(.largeTitle, design: .rounded).weight(.bold)).tracking(-0.6)
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A compact, shared entry treatment for contextual Nova destinations.
/// It deliberately contains no data or navigation state, so Calendar, Memory,
/// Contacts and Settings can retain their proven models and authorization paths.
struct NovaDestinationHeader: View {
    let eyebrow: String
    let title: String
    let detail: String
    let tint: Color
    let symbol: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.headline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)
                .background(tint.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(eyebrow)
                    .font(.caption2.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(NovaTodayTokens.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .stroke(Routes05Tokens.ink, lineWidth: 1.2)
        }
        .accessibilityElement(children: .combine)
    }
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
        HStack(alignment: .top, spacing: 11) { Circle().stroke(NovaTodayTokens.coral, lineWidth: 2).frame(width: 22, height: 22).padding(.top, 1); VStack(alignment: .leading, spacing: 3) { Text(task.title).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true); Text("\(taskDate) · \(sourceLabel)").font(.caption).foregroundStyle(.secondary) }; Spacer(minLength: 0); Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary) }.frame(minHeight: 44, alignment: .center).accessibilityElement(children: .combine).accessibilityLabel("Відкрита шкільна справа: \(task.title). \(taskDate). \(sourceLabel)")
    }
    private var taskDate: String { guard let due = task.dueAt, let date = OrbitSchoolDateDecoding.date(from: due) else { return "Термін не вказано" }; return "Термін: " + date.formatted(date: .abbreviated, time: .omitted) }
    private var sourceLabel: String { switch task.sourceType.lowercased() { case "letter", "schulmanager_letter": "Schulmanager · Лист"; case "message", "schulmanager_message": "Schulmanager · Повідомлення"; case "calendar", "schulmanager_calendar": "Schulmanager · Календар"; default: "Schulmanager · Джерело" } }
}

private struct NovaLoadingRows: View {
    var body: some View { VStack(alignment: .leading, spacing: 10) { RoundedRectangle(cornerRadius: 5).fill(.secondary.opacity(0.14)).frame(height: 13); RoundedRectangle(cornerRadius: 5).fill(.secondary.opacity(0.10)).frame(width: 190, height: 13) }.redacted(reason: .placeholder).frame(minHeight: 44, alignment: .leading) }
}
private struct NovaStateRow: View { let icon: String; let text: String; var body: some View { Label(text, systemImage: icon).font(.subheadline).foregroundStyle(.secondary).frame(minHeight: 44, alignment: .leading) } }
private struct NovaFailureRow: View { let message: String; let retry: () -> Void; var body: some View { VStack(alignment: .leading, spacing: 8) { Text(message).font(.subheadline).foregroundStyle(.secondary); Button("Повторити", action: retry).buttonStyle(.bordered) } } }
private struct NovaStaleLabel: View { var body: some View { Label("Не вдалося оновити — показано попередні дані", systemImage: "clock.badge.exclamationmark").font(.caption).foregroundStyle(.orange) } }
