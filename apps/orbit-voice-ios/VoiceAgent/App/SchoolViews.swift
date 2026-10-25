import SwiftUI

private let schoolUkrainianCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}()
private let schoolUkrainianMonthFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = schoolUkrainianCalendar
    formatter.locale = Locale(identifier: "uk_UA")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "MMMM"
    return formatter
}()

private func schoolUkrainianDate(_ date: Date) -> String {
    let parts = schoolUkrainianCalendar.dateComponents([.day, .month, .year], from: date)
    guard let day = parts.day, let month = parts.month, let year = parts.year else { return "Дата не визначена" }
    return "\(day) \(schoolUkrainianMonthFormatter.monthSymbols[month - 1]) \(year)"
}
private func schoolLocalizedDate(_ value: String) -> String {
    OrbitSchoolCivilDate.formatted(value)
}
private func schoolLocalizedInstant(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "uk_UA")
    formatter.timeZone = SchoolHubLogic.schoolTimeZone
    formatter.dateFormat = "EEE, d MMM, HH:mm"
    return formatter.string(from: date)
}
private func schoolAllDayRange(_ event: OrbitSchoolEvent) -> String {
    guard let start = event.startsAt else { return "Дата не визначена" }
    guard let end = event.endsAt else { return schoolUkrainianDate(start) }
    let first = schoolUkrainianCalendar.dateComponents([.day, .month, .year], from: start)
    let last = schoolUkrainianCalendar.dateComponents([.day, .month, .year], from: end)
    guard let startDay = first.day, let endDay = last.day, let month = first.month, let year = first.year else { return schoolUkrainianDate(start) }
    if first.year == last.year, first.month == last.month, startDay != endDay { return "\(startDay)–\(endDay) \(schoolUkrainianMonthFormatter.monthSymbols[month - 1]) \(year)" }
    if startDay == endDay, first.month == last.month, first.year == last.year { return schoolUkrainianDate(start) }
    return "\(schoolUkrainianDate(start)) – \(schoolUkrainianDate(end))"
}

struct SchoolInboxView: View {
    private let embeddedInNavigation: Bool
    private let hubMode: Bool
    @State private var items: [OrbitSchoolItem] = []
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var inheritedColorScheme
    @State private var appearanceOverride: ColorScheme?
    @State private var chip: InboxChip = .all
    @State private var showingSearch = false
    @State private var taskResponse: OrbitSchoolTasksResponse?
    @State private var query = ""
    @State private var error: String?
    @State private var loading = false
    @State private var notificationPermission = SchoolNotificationPermission.notDetermined
    @State private var notificationDiagnosticMessage: String?
    #if DEBUG
    private let fixture: Routes05SchoolFixture?
    #endif

    #if DEBUG
    init(embeddedInNavigation: Bool = false, hubMode: Bool = false, fixture: Routes05SchoolFixture? = nil) {
        self.embeddedInNavigation = embeddedInNavigation
        self.hubMode = hubMode
        self.fixture = fixture
        _items = State(initialValue: fixture?.items ?? [])
    }
    #else
    init(embeddedInNavigation: Bool = false, hubMode: Bool = false) {
        self.embeddedInNavigation = embeddedInNavigation
        self.hubMode = hubMode
    }
    #endif

    var body: some View {
        Group {
            if embeddedInNavigation { schoolList }
            else { NavigationStack { schoolList } }
        }
    }
    private enum InboxChip: String, CaseIterable, Identifiable {
        case all, letters, chats, unread
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: "Всі"
            case .letters: "Листи"
            case .chats: "Чати"
            case .unread: "Непрочитані"
            }
        }
    }

    // The original 09_inbox.html composition, rendered as native SwiftUI.
    // Navigation remains owned by SchoolHubView; no new stack or dock.
    private var schoolList: some View {
        VStack(spacing: 0) {
            inboxMast
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 9) {
                        Button { dismiss() } label: {
                            Image(systemName: "arrow.left")
                                .font(.system(size: 18, weight: .semibold))
                                .frame(width: 40, height: 40)
                                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Routes05Tokens.ink, lineWidth: 1.5))
                        }
                        .accessibilityLabel("Назад до школи")
                        .frame(minWidth: 44, minHeight: 44)
                        Text("Вхідні").font(.system(size: 17, weight: .black, design: .rounded))
                        Spacer(minLength: 6)
                        Text("0 / 05").font(.system(size: 10, weight: .black, design: .monospaced))
                    }
                    .padding(.top, 14)
                    .padding(.bottom, 15)

                    HStack(spacing: 8) {
                        Text("SCHULMANAGER / READ ONLY")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .tracking(1.3)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Text("⌁ \(Date.now.formatted(.dateTime.year()))")
                            .font(.system(size: 10, design: .monospaced))
                    }
                    .padding(.vertical, 12)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Routes05Tokens.ink).frame(height: 1.5)
                    }

                    HStack(alignment: .center, spacing: 12) {
                        Text("Вхідні\nзі школи.")
                            .font(.system(size: 35, weight: .black, design: .rounded))
                            .tracking(-1.8)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 6)
                        Text(String(format: "%02d", min(items.filter(\.unread).count, 99)))
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundStyle(Routes05Tokens.accentInk)
                            .frame(width: 60, height: 60)
                            .background(Routes05Tokens.blue, in: Circle())
                            .overlay(Circle().stroke(Routes05Tokens.ink, lineWidth: 2))
                            .accessibilityLabel("Непрочитаних: \(items.filter(\.unread).count)")
                    }
                    .padding(.top, 15).padding(.bottom, 13)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(InboxChip.allCases) { option in
                                Button { chip = option } label: {
                                    Text(option.title)
                                        .font(.system(size: 11, weight: .heavy))
                                        .lineLimit(1)
                                        .foregroundStyle(chip == option ? Routes05Tokens.canvas : Routes05Tokens.ink)
                                        .padding(.horizontal, 11)
                                        .frame(minHeight: 34)
                                        .background(chip == option ? Routes05Tokens.ink : Routes05Tokens.surface, in: Capsule())
                                        .overlay(Capsule().stroke(chip == option ? Routes05Tokens.ink : Routes05Tokens.rule, lineWidth: 1.5))
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(chip == option ? .isSelected : [])
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .accessibilityLabel("Фільтри вхідних")

                    if showingSearch {
                        HStack(spacing: 9) {
                            Image(systemName: "magnifyingglass").foregroundStyle(Routes05Tokens.secondary)
                            TextField("Пошук у вхідних", text: $query)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.search)
                            Button {
                                query = ""
                                showingSearch = false
                            } label: { Image(systemName: "xmark.circle.fill") }
                                .accessibilityLabel("Закрити пошук")
                        }
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(Routes05Tokens.surface)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Routes05Tokens.rule, lineWidth: 1))
                        .padding(.top, 10)
                    }

                    if loading {
                        ProgressView("Завантаження вхідних…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                    }
                    if visibleItems.isEmpty && !loading {
                        Routes05StateRow(
                            text: query.isEmpty ? "Для цього профілю й фільтра немає доступних матеріалів." : "Нічого не знайдено — змініть запит або фільтр.",
                            tint: Routes05Tokens.blue
                        )
                        .padding(.top, 20)
                    }
                    LazyVStack(spacing: 0) {
                        ForEach(visibleItems.indices, id: \.self) { index in
                            let item = visibleItems[index]
                            NavigationLink { SchoolDetailView(item: item) } label: {
                                schoolRow(item, index: index)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 18)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("ВАЖЛИВО")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .tracking(1.4)
                        Text("Оригінальні повідомлення лише читаються. Orbit не відповідає за вас і не змінює Schulmanager.")
                            .font(.system(size: 12))
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Routes05Tokens.surface)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Routes05Tokens.ink, lineWidth: 1.5))
                    .padding(.top, 17)

                    if notificationPermission == .denied {
                        notificationSection.font(.footnote).padding(.top, 12)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await load() }
        }
        .background(Routes05Tokens.canvas.ignoresSafeArea())
        .foregroundStyle(Routes05Tokens.ink)
        .safeAreaPadding(.bottom, 16)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .preferredColorScheme(appearanceOverride)
        .onAppear { Task { await load(); await refreshNotificationPermission() } }
        .alert("Школа недоступна", isPresented: .constant(error != nil)) {
            Button("Повторити") { error = nil; Task { await load() } }
            Button("Гаразд", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }

    private var inboxMast: some View {
        HStack(spacing: 7) {
            ZStack {
                Circle().stroke(Routes05Tokens.ink, lineWidth: 2)
                Circle().fill(Routes05Tokens.mint).frame(width: 8, height: 8)
            }
            .frame(width: 27, height: 27)
            Text("orbit")
                .font(.system(size: 20, weight: .black, design: .rounded)).tracking(-1.2)
            Text("/ ROUTES")
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .tracking(1.1).padding(.leading, 4)
            Spacer(minLength: 4)
            Text("SCHOOL / 05")
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .tracking(0.5).lineLimit(1).minimumScaleFactor(0.85)
            Button {
                appearanceOverride = (appearanceOverride ?? inheritedColorScheme) == .dark ? .light : .dark
            } label: {
                Image(systemName: "circle.lefthalf.filled").font(.system(size: 15))
                    .frame(width: 35, height: 35)
            }
            .accessibilityLabel("Перемкнути тему Вхідних")
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Routes05Tokens.ink, lineWidth: 1.2))
            Menu {
                Button("Пошук", systemImage: "magnifyingglass") { showingSearch = true }
                Button("Всі", systemImage: "tray") { chip = .all }
                Button("Непрочитані", systemImage: "envelope.badge") { chip = .unread }
                Text(actionSummaryText)
            } label: {
                Image(systemName: "list.bullet").font(.system(size: 15))
                    .frame(width: 35, height: 35)
            }
            .accessibilityLabel("Дії та фільтри Вхідних")
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Routes05Tokens.ink, lineWidth: 1.2))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .frame(minHeight: 49)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Routes05Tokens.ink).frame(height: 1.5)
        }
    }
    private var itemSnapshots: [SchoolInboxItemSnapshot] {
        items.map { item in
            SchoolInboxItemSnapshot(
                id: item.id,
                type: item.type,
                title: item.titlePlainText?.isEmpty == false ? item.titlePlainText! : item.title,
                sender: item.sender,
                preview: item.translationUkrainian ?? item.previewPlainText ?? item.originalPlainText ?? item.originalGerman,
                searchText: [
                    item.title,
                    item.titlePlainText,
                    item.sender,
                    item.previewPlainText,
                    item.originalPlainText,
                    item.originalGerman,
                    item.translationUkrainian
                ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n"),
                unread: item.unread,
                date: item.sourceTimestamp ?? item.importedAt
            )
        }
    }
    private var actionSummary: SchoolInboxActionSummary {
        let tasks = (taskResponse?.tasks ?? []).map { SchoolInboxTaskSnapshot(sourceItemId: $0.sourceItemId, status: $0.status ?? "open") }
        let complete = taskResponse?.complete == true && taskResponse?.truncated != true && taskResponse?.coverage == "all"
        return SchoolHubLogic.inboxActionSummary(itemIDs: Set(items.map(\.id)), tasks: tasks, coverageComplete: complete)
    }
    private var actionSummaryText: String {
        guard taskResponse != nil else { return "Дії тимчасово недоступні." }
        if let count = actionSummary.count { return "Потребують дії: \(count) \(count == 1 ? "розмова" : "розмови")" }
        return "Кількість дій уточнюється: дані ще неповні."
    }
    private var visibleItems: [OrbitSchoolItem] {
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let type: SchoolInboxTypeFilter = switch chip {
        case .letters: .letters
        case .chats: .messages
        case .all, .unread: .all
        }
        let status: SchoolInboxFilter = chip == .unread ? .unread : .all
        return SchoolHubLogic.filterInboxItemIDs(itemSnapshots, filter: status, typeFilter: type, query: query, actionSummary: actionSummary).compactMap { byID[$0] }
    }
    @ViewBuilder private var notificationSection: some View {
        switch notificationPermission {
        case .denied:
            Label("Сповіщення Orbit вимкнено в Налаштуваннях", systemImage: "bell.slash").foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }
    private func schoolRow(_ item: OrbitSchoolItem, index: Int) -> some View {
        let sender = item.sender.isEmpty ? (item.type == "letter" ? "Лист" : "Повідомлення") : item.sender
        let title = item.titlePlainText?.isEmpty == false ? item.titlePlainText! : (item.title.isEmpty ? String((item.previewPlainText ?? item.originalPlainText ?? item.originalGerman).prefix(80)) : item.title)
        let tint: Color = switch index % 4 {
        case 0: Routes05Tokens.yellow
        case 1: Routes05Tokens.mint
        case 2: Routes05Tokens.lilac
        default: Routes05Tokens.orange
        }
        return HStack(spacing: 12) {
            Image(systemName: item.type == "letter" ? "envelope.fill" : "text.bubble.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Routes05Tokens.accentInk)
                .frame(width: 36, height: 36)
                .background(tint, in: Circle())
                .overlay(Circle().stroke(Routes05Tokens.ink, lineWidth: 1.4))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(Routes05Tokens.ink)
                    .lineLimit(2)
                Text("\(sender) · \(inboxDateLabel(item.sourceTimestamp ?? item.importedAt))")
                    .font(.system(size: 10))
                    .foregroundStyle(Routes05Tokens.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            if item.unread {
                Circle().fill(Routes05Tokens.ink).frame(width: 9, height: 9)
            } else {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .black))
            }
        }
        .frame(minHeight: 59)
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) { Rectangle().fill(Routes05Tokens.rule).frame(height: 1) }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(sender). \(inboxPreview(for: item))")
        .accessibilityValue([
            item.unread ? "Непрочитано" : nil,
            taskCount(for: item).map { "\($0) відкритих справ" },
            item.attachments.isEmpty ? nil : "\(item.attachments.count) вкладень"
        ].compactMap { $0 }.joined(separator: ", "))
    }

    private func inboxDateLabel(_ date: Date?) -> String {
        guard let date else { return "дата невідома" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = SchoolHubLogic.schoolTimeZone
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "uk_UA")
        formatter.timeZone = SchoolHubLogic.schoolTimeZone
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
            return "сьогодні \(formatter.string(from: date))"
        }
        formatter.dateFormat = "d MMMM"
        return formatter.string(from: date)
    }
    private func inboxPreview(for item: OrbitSchoolItem) -> String {
        let translation = item.translationUkrainian?.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = item.important?.trimmingCharacters(in: .whitespacesAndNewlines)
        return [translation, summary, item.previewPlainText, item.originalPlainText, item.originalGerman]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "Без попереднього перегляду"
    }
    private func taskCount(for item: OrbitSchoolItem) -> Int? {
        guard taskResponse?.complete == true, taskResponse?.truncated != true else { return nil }
        return taskResponse?.tasks.filter { $0.sourceItemId == item.id && $0.status != "completed" }.count
    }
    private func load() async {
        #if DEBUG
        if fixture != nil { return }
        #endif
        loading = true
        defer { loading = false }
        do {
            async let loadedItems = MainProductAPI.shared.schoolItems(filter: "all")
            async let loadedTasks = MainProductAPI.shared.schoolTasks(coverage: "all")
            items = try await loadedItems.items
            taskResponse = try? await loadedTasks
            error = nil
        } catch { self.error = "Не вдалося завантажити шкільні матеріали." }
    }
    private func refreshNotificationPermission() async { notificationPermission = await SchoolNotificationCoordinator.shared.authorizationStatus() }
    private func requestNotificationPermission() async { notificationPermission = await SchoolNotificationCoordinator.shared.requestAuthorization() }
    private func scheduleDiagnosticNotification() async { notificationDiagnosticMessage = await SchoolNotificationCoordinator.shared.scheduleDiagnostic() ? "Тестове сповіщення з’явиться приблизно через 5 секунд." : "Не вдалося запланувати тестове сповіщення." }
}

struct SchoolCalendarView: View {
    @State private var events: [OrbitSchulmanagerCalendarEvent] = []
    @State private var scope = "for-us"
    @State private var error: String?
    @State private var loaded = false
    @State private var pendingEvent: OrbitSchulmanagerCalendarEvent?
    var body: some View {
        List {
            Picker("Показати", selection: $scope) { Text("Для нас").tag("for-us"); Text("Вся школа").tag("all") }.pickerStyle(.segmented)
            if events.isEmpty && loaded { ContentUnavailableView("Шкільних подій не знайдено", systemImage: "calendar", description: Text("Це події, які Orbit уже отримав зі школи. Час останньої синхронізації тут не показується.")) }
            ForEach(events) { event in
                VStack(alignment: .leading, spacing: 7) {
                    Text(event.title).font(.headline)
                    if let explanation = calendarExplanation(event) { Text("(\(explanation))").font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                    Text(event.allDay ? OrbitSchoolCivilDate.inclusiveRange(start: event.startsAt, end: event.endsAt) : (event.startsAt.map(schoolLocalizedDate) ?? "Дата не визначена")).font(.subheadline)
                    if let badge = calendarBadge(event) { Text(badge.label).font(.caption.weight(.semibold)).foregroundStyle(badge.color).padding(.horizontal, 8).padding(.vertical, 4).background(badge.color.opacity(0.16), in: Capsule()).overlay(Capsule().stroke(badge.color.opacity(0.45))) }
                    if !event.location.isEmpty { Text(event.location).foregroundStyle(.secondary) }
                    Button("Запропонувати додати до сімейного календаря") { Task { await propose(event) } }.buttonStyle(.borderedProminent).frame(minHeight: 44)
                }
            }
        }.navigationTitle("Календар школи").task { await load() }.onChange(of: scope) { _, _ in Task { await load() } }.alert("Календар школи", isPresented: .constant(error != nil)) { Button("Гаразд") { error = nil } } message: { Text(error ?? "") }
        .confirmationDialog("Додати подію до сімейного календаря Orbit?", isPresented: Binding(get: { pendingEvent != nil }, set: { if !$0 { pendingEvent = nil } }), titleVisibility: .visible, presenting: pendingEvent) { event in
            Button("Додати «\(event.title)»") { Task { await confirm(event) } }
            Button("Скасувати", role: .cancel) { pendingEvent = nil }
        } message: { _ in Text("Подію буде створено лише в сімейному календарі Orbit, не в зовнішніх календарях.") }
    }
    private func calendarBadge(_ event: OrbitSchulmanagerCalendarEvent) -> (label: String, color: Color)? {
        if event.audienceClass == "STAFF_ONLY" { return ("Для працівників", .secondary) }
        guard event.relevanceClass != "UNRELATED" else { return nil }
        if ["DIRECT", "GRADE", "SCHOOLWIDE"].contains(event.relevanceClass ?? "") { return ("Для нас", .red) }
        if event.audienceClass == "FAMILY_RELEVANT" || event.audienceClass == "FAMILY_INFORMATIONAL" { return ("Можливо для нас", .green) }
        return nil
    }
    private func calendarExplanation(_ event: OrbitSchulmanagerCalendarEvent) -> String? {
        guard let value = event.relevanceReason?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
    private func load() async { do { events = try await MainProductAPI.shared.schulmanagerCalendar(scope: scope); loaded = true } catch { self.error = "Не вдалося завантажити календар школи." } }
    private func propose(_ event: OrbitSchulmanagerCalendarEvent) async {
        do {
            let preview = try await MainProductAPI.shared.addSchoolCalendarEvent(uid: event.uid, confirm: false)
            if preview.duplicate == true { error = "Цю подію вже додано." }
            else if preview.requiresConfirmation == true { pendingEvent = event }
            else { error = "Не вдалося підготувати додавання події." }
        } catch { self.error = "Не вдалося підготувати додавання події." }
    }
    private func confirm(_ event: OrbitSchulmanagerCalendarEvent) async {
        pendingEvent = nil
        do {
            let result = try await MainProductAPI.shared.addSchoolCalendarEvent(uid: event.uid, confirm: true)
            error = result.duplicate == true ? "Цю подію вже додано." : (result.created ? "Подію додано до сімейного календаря." : "Не вдалося додати подію.")
        } catch { self.error = "Не вдалося додати подію." }
    }
}

struct SchoolTasksView: View {
#if DEBUG
    private let fixture: Routes05SchoolFixture?
#endif
    @State private var briefing: OrbitSchoolBriefingResponse?
    @State private var windowFrom = ""
    @State private var windowTo = ""
    @State private var error: String?
    @State private var loading = false

    init() {
#if DEBUG
        self.fixture = nil
#endif
    }

#if DEBUG
    init(fixture: Routes05SchoolFixture) {
        self.fixture = fixture
        let item = OrbitSchoolBriefingItem(date: "2026-10-24", title: fixture.tasks.first?.title ?? "Підготовка до тесту", detail: fixture.tasks.first?.action ?? "Перевірити дату в джерелі", sourceRefs: [OrbitSchoolBriefingSource(id: fixture.items.first?.id ?? "routes05-letter", type: "letter")])
        _briefing = State(initialValue: OrbitSchoolBriefingResponse(from: "2026-10-24", to: "2026-10-31", timeZone: "Europe/Berlin", dated: [item], attention: []))
    }
#endif

    var body: some View {
        List {
            Section {
                Routes05ContextHeader(section: "discovery", eyebrow: "BRIEFING / SOURCE AWARE", title: "Коротко.\nПо суті.", detail: "Огляд з посиланнями на фактичні шкільні джерела.", accent: Routes05Tokens.orange)
            }
            if loading { ProgressView().frame(maxWidth: .infinity) }
            if let briefing {
                Section { Text("\(localizedDate(briefing.from)) — \(localizedDate(briefing.to, subtractingDays: 1))").font(.subheadline).foregroundStyle(.secondary) }
                ForEach(briefing.dated) { item in
                    Section(localizedDate(item.date ?? briefing.from)) { briefingItem(item) }
                }
                Section("Потребує уваги") {
                    if briefing.attention.isEmpty { Text("Немає окремих дій без визначеної дати.").foregroundStyle(.secondary) }
                    ForEach(briefing.attention) { item in briefingItem(item) }
                }
            } else if !loading { ContentUnavailableView("Огляд недоступний", systemImage: "calendar.badge.exclamationmark") }
        }
        .navigationTitle("")
        .task {
#if DEBUG
            if fixture == nil { await load() }
#else
            await load()
#endif
        }
        .refreshable { await load() }
        .alert("Шкільний огляд", isPresented: SchoolBrainRequestState.alertBinding(error: $error)) { Button("Повторити") { Task { await load() } }; Button("Гаразд", role: .cancel) { error = nil } } message: { Text(error ?? "") }
    }

    @ViewBuilder private func sourceLinks(for message: OrbitSchoolBrainMessage) -> some View {
        if !message.sourceRefs.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(Array(message.sourceRefs.enumerated()), id: \.offset) { _, ref in if let id = ref["id"], let type = ref["type"], ["letter", "message"].contains(type) { NavigationLink { SchoolDetailLoaderView(itemID: id) } label: { Label(type == "letter" ? "Лист" : "Повідомлення", systemImage: type == "letter" ? "envelope" : "message") }.buttonStyle(.bordered) } } } }
        }
    }

    private func load() async {
        loading = true; defer { loading = false }
        do {
            briefing = try await MainProductAPI.shared.schoolBriefing(); error = nil
        } catch is CancellationError { } catch { self.error = "Не вдалося підготувати огляд школи." }
    }

    @ViewBuilder private func briefingItem(_ item: OrbitSchoolBriefingItem) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(item.title).font(.headline)
            if !item.detail.isEmpty { Text(item.detail).fixedSize(horizontal: false, vertical: true) }
            if !item.sourceRefs.isEmpty { ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(item.sourceRefs, id: \.self) { source in if source.type == "calendar" { NavigationLink { SchoolCalendarView() } label: { Label("Календар", systemImage: "calendar") }.buttonStyle(.bordered) } else { NavigationLink { SchoolDetailLoaderView(itemID: source.id) } label: { Label(source.type == "message" ? "Повідомлення" : "Лист", systemImage: source.type == "message" ? "message" : "envelope") }.buttonStyle(.bordered) } } } } }
        }
    }

    private func localizedDate(_ value: String, subtractingDays: Int = 0) -> String {
        let parts = value.split(separator: "-").compactMap { Int($0) }; guard parts.count == 3, let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return value }
        let adjusted = Calendar(identifier: .gregorian).date(byAdding: .day, value: -subtractingDays, to: date) ?? date
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "uk_UA"); formatter.timeZone = TimeZone(identifier: "Europe/Berlin"); formatter.dateFormat = "d MMMM, EEEE"; return formatter.string(from: adjusted)
    }
}
struct SchoolDetailLoaderView: View {
    let itemID: String
    @State private var item: OrbitSchoolItem?
    @State private var failed = false

    var body: some View {
        Group {
            if let item {
                SchoolDetailView(item: item)
            } else if failed {
                ContentUnavailableView("Лист недоступний", systemImage: "exclamationmark.triangle", description: Text("Не вдалося відкрити цей матеріал. Перевірте з’єднання й спробуйте ще раз."))
                    .overlay(alignment: .bottom) {
                        Button("Повторити") { Task { await load() } }
                            .buttonStyle(.borderedProminent)
                            .padding(.bottom, 28)
                    }
            } else {
                ProgressView("Відкриваємо лист…")
            }
        }
        .task { await load() }
    }

    private func load() async {
        failed = false
        do {
            item = try await MainProductAPI.shared.schoolItem(id: itemID)
        } catch is CancellationError {
        } catch {
            failed = true
        }
    }
}

struct SchoolDetailView: View {
    let item: OrbitSchoolItem
    @Environment(\.dismiss) private var dismiss
    @State private var calendarMessage: String?
    @State private var pendingCalendarEvent: OrbitSchoolEvent?
    @State private var showOriginal = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Routes05ContextHeader(
                    section: "school",
                    eyebrow: "SOURCE ORIGINAL / DE",
                    title: item.type == "letter" ? "Лист / джерело" : "Повідомлення / джерело",
                    detail: "Оригінал, переклад і Orbit-інтерпретація залишаються окремими.",
                    accent: Routes05Tokens.blue
                )
                if !displayTitle.isEmpty { Text(displayTitle).font(.title2.weight(.semibold)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled) }
                Text([item.sender.isEmpty ? nil : item.sender, item.sourceTimestamp.map { $0.formatted(date: .abbreviated, time: .omitted) }].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                if let tasks = item.tasks, !tasks.isEmpty {
                    detailHeader("Що потрібно")
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(tasks.enumerated()), id: \.offset) { _, task in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "list.bullet.circle")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 19, height: 19)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.title ?? task.action ?? "Справа").font(.callout.weight(.medium))
                                    if let action = task.action, action != task.title { Text(action).font(.caption).foregroundStyle(.secondary) }
                                    Text(task.dueAt.map { $0.count == 10 ? OrbitSchoolCivilDate.formatted($0) : (OrbitSchoolDateDecoding.date(from: $0).map(schoolLocalizedInstant) ?? $0) } ?? "Без дати · лишається відкритою")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 9)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(task.title ?? task.action ?? "Справа"). Виконання ще не підтримується.")
                            if tasks.last?.key != task.key { Divider() }
                        }
                    }
                    .padding(.horizontal, 12)
                    .background(Routes05Tokens.surface)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Routes05Tokens.ink, lineWidth: 1))
                } else {
                    detailHeader("Що потрібно")
                    Text("У цьому листі немає справ для батьків.").font(.footnote).foregroundStyle(.secondary)
                }
                detailHeader("Текст листа")
                Picker("Мова", selection: $showOriginal) { Text("Переклад").tag(false); Text("Оригінал (DE)").tag(true) }
                    .pickerStyle(.segmented).padding(.bottom, 8)
                let body = showOriginal ? (item.originalPlainText ?? item.originalGerman) : (item.translationUkrainian ?? "Переклад ще готується.")
                if showOriginal {
                    Text(verbatim: body)
                        .font(.body)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(SchoolTranslatedBody.paragraphs(from: body).enumerated()), id: \.offset) { _, paragraph in
                            Text(verbatim: paragraph)
                                .font(.body)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                                .textSelection(.enabled)
                        }
                    }
                }
                detailHeader("Короткий підсумок")
                Text(item.important ?? "Підсумок відсутній — перевірте оригінал листа.")
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
                Label("Підсумок Orbit (ШІ), не слова школи. Звіряйте з оригіналом.", systemImage: "sparkles")
                    .font(.caption).foregroundStyle(.secondary).padding(.top, 6)
                if !item.attachments.isEmpty {
                    detailHeader("Вкладення")
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(item.attachments.enumerated()), id: \.offset) { _, file in attachmentRow(file) }
                    }
                    .background(Routes05Tokens.surface)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Routes05Tokens.ink, lineWidth: 1))
                }
                detailHeader("Джерело")
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.source == "schulmanager" ? "Schulmanager · лише читання" : item.source).font(.footnote)
                    if !item.sender.isEmpty { Text("Відправник: \(item.sender)").font(.caption).foregroundStyle(.secondary) }
                    Text(item.unread ? "Стан в Orbit: непрочитано" : "Стан в Orbit: прочитано").font(.caption).foregroundStyle(.secondary)
                }
                if !item.events.isEmpty {
                    detailHeader("Дати / дедлайни")
                    ForEach(item.events) { event in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(event.title).font(.callout.weight(.medium))
                            if event.startsAt != nil { Text(event.allDay ? schoolAllDayRange(event) : schoolTimedDateRange(event)).font(.caption) }
                            if let location = event.location { Text(location).font(.caption).foregroundStyle(.secondary) }
                            Button("Додати до календаря") { Task { await add(event) } }.buttonStyle(.bordered)
                        }.padding(.vertical, 5)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 24)
        }
        .background(Routes05Tokens.canvas)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaPadding(.bottom, 16)
        .task { try? await MainProductAPI.shared.markSchoolItemRead(id: item.id) }
        .alert("Календар", isPresented: .constant(calendarMessage != nil)) { Button("Гаразд") { calendarMessage = nil } } message: { Text(calendarMessage ?? "") }
        .alert("Додати до календаря?", isPresented: Binding(get: { pendingCalendarEvent != nil }, set: { if !$0 { pendingCalendarEvent = nil } })) { Button("Додати") { if let event = pendingCalendarEvent { pendingCalendarEvent = nil; Task { await confirm(event) } } }; Button("Скасувати", role: .cancel) { pendingCalendarEvent = nil } } message: { Text(calendarPreviewMessage) }
    }
    private var displayTitle: String { item.titlePlainText?.isEmpty == false ? item.titlePlainText! : item.title }
    @ViewBuilder private func attachmentRow(_ file: OrbitSchoolAttachment) -> some View {
        let rawURL = file.url ?? file.downloadURL
        let safeURL = rawURL.flatMap { value -> URL? in
            guard let url = URL(string: value), url.scheme?.lowercased() == "https" else { return nil }
            return url
        }
        if let safeURL {
            Link(destination: safeURL) {
                attachmentLabel(file).foregroundStyle(.primary)
            }
        } else {
            attachmentLabel(file)
        }
        Divider().padding(.leading, 34)
    }
    private func attachmentLabel(_ file: OrbitSchoolAttachment) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "paperclip").foregroundStyle(.secondary).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.filename).font(.callout).lineLimit(2)
                if let contentType = file.contentType, !contentType.isEmpty { Text(contentType).font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer()
            if (file.url ?? file.downloadURL) != nil { Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary) }
        }
        .padding(.vertical, 10).contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(file.filename)
        .accessibilityHint((file.url ?? file.downloadURL) == nil ? "Метадані вкладення" : "Відкрити вкладення")
    }
    private func detailHeader(_ title: String) -> some View {
        Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            .tracking(0.6).padding(.top, 20).padding(.bottom, 6)
            .accessibilityAddTraits(.isHeader)
    }
    private func schoolTimedDateRange(_ event: OrbitSchoolEvent) -> String { guard let start = event.startsAt else { return "Дата не визначена" }; if let end = event.endsAt, end != start { return "\(start.formatted(date: .long, time: .shortened)) – \(end.formatted(date: .long, time: .shortened))" }; return start.formatted(date: .long, time: .shortened) }
    private var calendarPreviewMessage: String { guard let event = pendingCalendarEvent else { return "" }; var lines = [event.title]; if event.startsAt != nil { lines.append(event.allDay ? schoolAllDayRange(event) : schoolTimedDateRange(event)) }; if let location = event.location, !location.isEmpty { lines.append(location) }; return lines.joined(separator: "\n") }
    private func add(_ event: OrbitSchoolEvent) async { do { let preview = try await MainProductAPI.shared.addSchoolEvent(itemID: item.id, event: event, confirm: false); if preview.duplicate == true { calendarMessage = "Подію вже додано." } else if preview.requiresConfirmation == true { pendingCalendarEvent = event } else { calendarMessage = "Не вдалося підготувати подію." } } catch { calendarMessage = "Не вдалося додати подію." } }
    private func confirm(_ event: OrbitSchoolEvent) async { do { let result = try await MainProductAPI.shared.addSchoolEvent(itemID: item.id, event: event, confirm: true); calendarMessage = result.duplicate == true ? "Подію вже додано." : (result.created ? "Подію додано до календаря." : "Не вдалося додати подію.") } catch { calendarMessage = "Не вдалося додати подію." } }
}
