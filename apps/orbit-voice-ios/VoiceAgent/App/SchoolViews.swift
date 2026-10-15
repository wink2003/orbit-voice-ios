import Foundation
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

fileprivate struct SchoolInboxFixture: Decodable {
    let items: [OrbitSchoolItem]
    let taskResponse: OrbitSchoolTasksResponse
}

struct SchoolInboxView: View {
    private let embeddedInNavigation: Bool
    private let hubMode: Bool
    private let fixture: SchoolInboxFixture?
    @State private var items: [OrbitSchoolItem] = []
    @State private var filter: SchoolInboxFilter = .all
    @State private var typeFilter: SchoolInboxTypeFilter = .all
    @State private var taskResponse: OrbitSchoolTasksResponse?
    @State private var query = ""
    @State private var error: String?
    @State private var loading = false
    @State private var notificationPermission = SchoolNotificationPermission.notDetermined
    @State private var notificationDiagnosticMessage: String?

    init(embeddedInNavigation: Bool = false, hubMode: Bool = false) {
        self.embeddedInNavigation = embeddedInNavigation
        self.hubMode = hubMode
        self.fixture = nil
        _items = State(initialValue: [])
        _taskResponse = State(initialValue: nil)
    }

    fileprivate init(embeddedInNavigation: Bool = false, hubMode: Bool = false, fixture: SchoolInboxFixture?) {
        self.embeddedInNavigation = embeddedInNavigation
        self.hubMode = hubMode
        self.fixture = fixture
        _items = State(initialValue: fixture?.items ?? [])
        _taskResponse = State(initialValue: fixture?.taskResponse)
    }

    var body: some View {
        Group {
            if embeddedInNavigation { schoolList }
            else { NavigationStack { schoolList } }
        }
    }
    private var schoolList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                inboxFilters
                Text(actionSummaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if loading { ProgressView().frame(maxWidth: .infinity).padding(.vertical, 12) }
                if visibleItems.isEmpty && !loading {
                    ContentUnavailableView(
                        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Шкільних матеріалів не знайдено" : "Нічого не знайдено",
                        systemImage: query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "graduationcap" : "magnifyingglass",
                        description: Text(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Для цього профілю або фільтра немає отриманих листів чи повідомлень." : "Спробуйте інший запит або фільтр.")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                }
                LazyVStack(spacing: 0) {
                    ForEach(visibleItems) { item in
                        NavigationLink { SchoolDetailView(item: item) } label: { schoolRow(item) }
                            .buttonStyle(.plain)
                        if item.id != visibleItems.last?.id {
                            Divider().padding(.leading, 48)
                        }
                    }
                }
                if notificationPermission == .denied {
                    notificationSection.font(.footnote).padding(.top, 8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .background(OrbitColors.canvas)
        .novaDockAwareScrollContent()
        .navigationTitle("Вхідні")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Шукати листи й повідомлення")
        .refreshable {
            guard fixture == nil else { return }
            await load()
        }
        .onAppear {
            guard fixture == nil else { return }
            Task { await load(); await refreshNotificationPermission() }
        }
        .alert("Школа недоступна", isPresented: .constant(error != nil)) { Button("Повторити") { error = nil; Task { await load() } }; Button("Гаразд", role: .cancel) { error = nil } } message: { Text(error ?? "") }
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
        if let count = actionSummary.count {
            let tasks = openTaskCount
            let itemLabel = ukrainianCountLabel(count, one: "матеріал", few: "матеріали", many: "матеріалів")
            let taskLabel = ukrainianCountLabel(tasks, one: "відкрита справа", few: "відкриті справи", many: "відкритих справ")
            return "Дії: \(count) \(itemLabel) · \(tasks) \(taskLabel)"
        }
        return "Кількість дій уточнюється: дані ще неповні."
    }
    private func ukrainianCountLabel(_ value: Int, one: String, few: String, many: String) -> String {
        let mod100 = abs(value) % 100
        let mod10 = abs(value) % 10
        if mod100 >= 11 && mod100 <= 14 { return many }
        if mod10 == 1 { return one }
        if mod10 >= 2 && mod10 <= 4 { return few }
        return many
    }
    private var openTaskCount: Int {
        guard taskResponse?.complete == true, taskResponse?.truncated != true else { return 0 }
        let inboxIDs = Set(items.map(\.id))
        return taskResponse?.tasks.filter { inboxIDs.contains($0.sourceItemId) && $0.status != "completed" }.count ?? 0
    }
    private var visibleItems: [OrbitSchoolItem] {
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        return SchoolHubLogic.filterInboxItemIDs(itemSnapshots, filter: filter, typeFilter: typeFilter, query: query, actionSummary: actionSummary).compactMap { byID[$0] }
    }
    @ViewBuilder private var notificationSection: some View {
        switch notificationPermission {
        case .denied:
            Label("Сповіщення Orbit вимкнено в Налаштуваннях", systemImage: "bell.slash").foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }
    private var inboxFilters: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Вхідні", selection: $filter) {
                ForEach(SchoolInboxFilter.allCases) { option in Text(option.title).tag(option) }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Фільтр вхідних")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SchoolInboxTypeFilter.allCases) { option in
                        Button {
                            typeFilter = option
                        } label: {
                            Text(option.title)
                                .font(.footnote.weight(typeFilter == option ? .semibold : .regular))
                                .foregroundStyle(typeFilter == option ? Color.accentColor : .secondary)
                                .lineLimit(1)
                                .padding(.horizontal, 11)
                                .frame(minHeight: 34)
                                .background(typeFilter == option ? Color.accentColor.opacity(0.12) : Color.clear, in: Capsule())
                                .overlay { Capsule().stroke(typeFilter == option ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.18)) }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Тип: \(option.title)")
                        .accessibilityAddTraits(typeFilter == option ? .isSelected : [])
                    }
                }
                .padding(.vertical, 1)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Тип матеріалу")
        }
    }
    private func schoolRow(_ item: OrbitSchoolItem) -> some View {
        let sender = item.sender.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = item.titlePlainText?.isEmpty == false ? item.titlePlainText! : (item.title.isEmpty ? String((item.previewPlainText ?? item.originalPlainText ?? item.originalGerman).prefix(80)) : item.title)
        let preview = inboxPreview(for: item)
        return HStack(alignment: .top, spacing: 11) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: item.type == "letter" ? "envelope.fill" : "message.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(item.type == "letter" ? Color.orange : Color.accentColor)
                    .frame(width: 30, height: 30)
                    .background((item.type == "letter" ? Color.orange : Color.accentColor).opacity(0.12), in: Circle())
                if item.unread {
                    Circle().fill(Color.accentColor).frame(width: 8, height: 8).overlay(Circle().stroke(OrbitColors.canvas, lineWidth: 2)).offset(x: 2, y: -2)
                }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title).font(.callout.weight(item.unread ? .semibold : .regular)).lineLimit(2)
                    Spacer(minLength: 4)
                    if let date = item.sourceTimestamp ?? item.importedAt { Text(date, format: .dateTime.day().month(.abbreviated)).font(.caption2.weight(.medium)).foregroundStyle(.secondary).fixedSize() }
                }
                Text(preview).font(.footnote).foregroundStyle(.secondary).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 9) {
                    if !sender.isEmpty { Text(sender).lineLimit(1) }
                    if let count = taskCount(for: item), count > 0 { Label("\(count)", systemImage: "checklist") }
                    if !item.attachments.isEmpty { Label("\(item.attachments.count)", systemImage: "paperclip") }
                    if item.unread { Text("Нове") }
                }
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 2)
        .background(item.unread ? Color.accentColor.opacity(0.055) : Color.clear)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(preview)")
        .accessibilityValue([item.unread ? "Непрочитано" : nil, taskCount(for: item).map { "\($0) відкритих справ" }, item.attachments.isEmpty ? nil : "\(item.attachments.count) вкладень"].compactMap { $0 }.joined(separator: ", "))
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
    private func load() async { loading = true; defer { loading = false }; do { async let loadedItems = MainProductAPI.shared.schoolItems(filter: "all"); async let loadedTasks = MainProductAPI.shared.schoolTasks(coverage: "all"); items = try await loadedItems.items; taskResponse = try? await loadedTasks; error = nil } catch { self.error = "Не вдалося завантажити шкільні матеріали." } }
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
    @State private var briefing: OrbitSchoolBriefingResponse?
    @State private var windowFrom = ""
    @State private var windowTo = ""
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        List {
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
        .navigationTitle("Наступні 10 днів")
        .task { await load() }
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
    private let marksItemRead: Bool
    private let initiallyShowActions: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var calendarMessage: String?
    @State private var pendingCalendarEvent: OrbitSchoolEvent?
    @State private var showOriginal = false

    init(item: OrbitSchoolItem, marksItemRead: Bool = true, initiallyShowActions: Bool = false) {
        self.item = item
        self.marksItemRead = marksItemRead
        self.initiallyShowActions = initiallyShowActions
    }
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                if !displayTitle.isEmpty {
                    Text(displayTitle)
                        .font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                detailMetadata
                detailHeader("Текст листа")
                Picker("Мова тексту", selection: $showOriginal) { Text("Переклад").tag(false); Text("Оригінал (DE)").tag(true) }
                    .pickerStyle(.segmented)
                    .padding(.bottom, 10)
                    .accessibilityLabel("Мова тексту листа")
                Text(showOriginal ? (item.originalPlainText ?? item.originalGerman) : (item.translationUkrainian ?? "Переклад ще готується."))
                    .font(.body)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                detailHeader("Короткий підсумок")
                Text(item.important ?? "Підсумок відсутній — перевірте оригінал листа.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Label("Підсумок Orbit (ШІ), не слова школи. Звіряйте з оригіналом.", systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
                if !item.attachments.isEmpty {
                    detailHeader("Вкладення")
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(item.attachments.enumerated()), id: \.offset) { index, file in
                            attachmentRow(file)
                            if index < item.attachments.count - 1 { Divider().padding(.leading, 42) }
                        }
                    }
                }
                if !item.events.isEmpty {
                    detailHeader("Дати / дедлайни")
                    eventRows
                }
                detailHeader("Що потрібно")
                taskRows
                detailHeader("Джерело")
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.source == "schulmanager" ? "Schulmanager · лише читання" : item.source).font(.footnote)
                    Text(item.unread ? "Стан в Orbit: непрочитано" : "Стан в Orbit: прочитано").font(.caption).foregroundStyle(.secondary)
                }
                    Color.clear
                        .frame(height: 1)
                        .id("school-detail-actions")
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 12)
            }
            .novaDockAwareScrollContent()
            .onAppear {
                guard initiallyShowActions else { return }
                DispatchQueue.main.async {
                    proxy.scrollTo("school-detail-actions", anchor: .bottom)
                }
            }
        }
        .background(OrbitColors.canvas)
        .navigationTitle(item.type == "letter" ? "Лист" : "Повідомлення")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard marksItemRead else { return }
            try? await MainProductAPI.shared.markSchoolItemRead(id: item.id)
        }
        .alert("Календар", isPresented: .constant(calendarMessage != nil)) { Button("Гаразд") { calendarMessage = nil } } message: { Text(calendarMessage ?? "") }
        .alert("Додати до календаря?", isPresented: Binding(get: { pendingCalendarEvent != nil }, set: { if !$0 { pendingCalendarEvent = nil } })) { Button("Додати") { if let event = pendingCalendarEvent { pendingCalendarEvent = nil; Task { await confirm(event) } } }; Button("Скасувати", role: .cancel) { pendingCalendarEvent = nil } } message: { Text(calendarPreviewMessage) }
    }
    private var displayTitle: String { item.titlePlainText?.isEmpty == false ? item.titlePlainText! : item.title }
    private var detailMetadata: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if !item.sender.isEmpty {
                Label(item.sender, systemImage: item.type == "letter" ? "envelope" : "message")
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let date = item.sourceTimestamp ?? item.importedAt {
                Text(date, format: .dateTime.day().month(.abbreviated).year())
                    .fixedSize()
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.top, 5)
    }
    private func attachmentLabel(_ file: OrbitSchoolAttachment) -> some View {
        HStack(spacing: 10) {
            Image(systemName: attachmentSymbol(for: file))
                .font(.title3)
                .foregroundStyle(file.contentType?.lowercased() == "application/pdf" ? .red : .secondary)
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.filename)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(attachmentTypeLabel(for: file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(file.filename)
        .accessibilityValue(attachmentTypeLabel(for: file))
        .accessibilityHint("Метадані вкладення")
    }
    private func attachmentRow(_ file: OrbitSchoolAttachment) -> some View {
        attachmentLabel(file)
    }
    private func attachmentSymbol(for file: OrbitSchoolAttachment) -> String {
        let contentType = file.contentType?.lowercased() ?? ""
        if contentType == "application/pdf" { return "doc.fill" }
        if contentType.hasPrefix("image/") { return "photo" }
        return "doc"
    }
    private func attachmentTypeLabel(for file: OrbitSchoolAttachment) -> String {
        let contentType = file.contentType?.lowercased() ?? ""
        if contentType == "application/pdf" { return "PDF-документ" }
        if contentType.hasPrefix("image/") { return "Зображення" }
        if contentType.hasPrefix("text/") { return "Текстовий документ" }
        return contentType.isEmpty ? "Файл зі школи" : "Документ"
    }
    @ViewBuilder private var taskRows: some View {
        if let tasks = item.tasks, !tasks.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(tasks.enumerated()), id: \.offset) { index, task in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checklist")
                            .foregroundStyle(.secondary)
                            .frame(width: 20, height: 20)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.title ?? task.action ?? "Справа").font(.callout.weight(.medium))
                            if let action = task.action, action != task.title { Text(action).font(.caption).foregroundStyle(.secondary) }
                            Text(task.dueAt.map { $0.count == 10 ? OrbitSchoolCivilDate.formatted($0) : (OrbitSchoolDateDecoding.date(from: $0).map(schoolLocalizedInstant) ?? $0) } ?? "Без дати · лишається відкритою")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(task.title ?? task.action ?? "Справа"). Виконання ще не підтримується.")
                    if index < tasks.count - 1 { Divider().padding(.leading, 30) }
                }
            }
        } else {
            Text("У цьому листі немає справ для батьків.").font(.footnote).foregroundStyle(.secondary)
        }
    }
    private var eventRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(item.events.enumerated()), id: \.element.id) { index, event in
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title).font(.callout.weight(.medium))
                    if event.startsAt != nil { Text(event.allDay ? schoolAllDayRange(event) : schoolTimedDateRange(event)).font(.caption).foregroundStyle(.secondary) }
                    if let location = event.location, !location.isEmpty { Label(location, systemImage: "mappin.and.ellipse").font(.caption).foregroundStyle(.secondary) }
                    Button("Додати до календаря") { Task { await add(event) } }
                        .buttonStyle(.bordered)
                        .frame(minHeight: 36)
                }
                .padding(.vertical, 8)
                if index < item.events.count - 1 { Divider() }
            }
        }
    }
    private func detailHeader(_ title: String) -> some View {
        Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            .tracking(0.5).padding(.top, 18).padding(.bottom, 6)
            .accessibilityAddTraits(.isHeader)
    }
    private func schoolTimedDateRange(_ event: OrbitSchoolEvent) -> String {
        guard let start = event.startsAt else { return "Дата не визначена" }
        if let end = event.endsAt, end != start { return "\(schoolLocalizedInstant(start)) – \(schoolLocalizedInstant(end))" }
        return schoolLocalizedInstant(start)
    }
    private var calendarPreviewMessage: String { guard let event = pendingCalendarEvent else { return "" }; var lines = [event.title]; if event.startsAt != nil { lines.append(event.allDay ? schoolAllDayRange(event) : schoolTimedDateRange(event)) }; if let location = event.location, !location.isEmpty { lines.append(location) }; return lines.joined(separator: "\n") }
    private func add(_ event: OrbitSchoolEvent) async { do { let preview = try await MainProductAPI.shared.addSchoolEvent(itemID: item.id, event: event, confirm: false); if preview.duplicate == true { calendarMessage = "Подію вже додано." } else if preview.requiresConfirmation == true { pendingCalendarEvent = event } else { calendarMessage = "Не вдалося підготувати подію." } } catch { calendarMessage = "Не вдалося додати подію." } }
    private func confirm(_ event: OrbitSchoolEvent) async { do { let result = try await MainProductAPI.shared.addSchoolEvent(itemID: item.id, event: event, confirm: true); calendarMessage = result.duplicate == true ? "Подію вже додано." : (result.created ? "Подію додано до календаря." : "Не вдалося додати подію.") } catch { calendarMessage = "Не вдалося додати подію." } }
}

#if DEBUG
struct SchoolUXFixtureScreen: View {
    enum Screen { case inbox, detail, detailActions }
    let screen: Screen

    var body: some View {
        NavigationStack {
            switch screen {
            case .inbox:
                SchoolInboxView(embeddedInNavigation: true, hubMode: true, fixture: SchoolUXFixtureData.inbox)
            case .detail:
                SchoolDetailView(item: SchoolUXFixtureData.inbox.items[0], marksItemRead: false)
            case .detailActions:
                SchoolDetailView(item: SchoolUXFixtureData.inbox.items[0], marksItemRead: false, initiallyShowActions: true)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "circle.hexagongrid.fill")
                Text("Orbit")
                    .font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(.ultraThinMaterial)
            .accessibilityHidden(true)
        }
        .environment(\.novaDockHeight, 58)
    }
}

private enum SchoolUXFixtureData {
    static let inbox: SchoolInboxFixture = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try! decoder.decode(SchoolInboxFixture.self, from: Data(json.utf8))
    }()

    private static let json = """
    {
      "items": [
        {
          "id": "fixture-letter-1", "type": "letter", "source": "schulmanager", "externalId": "2541320",
          "title": "Exkursion zum Justizzentrum des Land- und Amtsgerichts Köln am 19.11.2026",
          "sender": "Schulmanager", "originalGerman": "Die Klasse besucht am 19. November das Justizzentrum Köln. Bitte beachten Sie die Einverständniserklärung.",
          "originalPlainText": "Die Klasse besucht am 19. November das Justizzentrum Köln. Bitte beachten Sie die Einverständniserklärung.",
          "previewPlainText": "Bitte beachten Sie die Einverständniserklärung für die Exkursion.",
          "titlePlainText": "Exkursion zum Justizzentrum des Land- und Amtsgerichts Köln am 19.11.2026",
          "translationUkrainian": "Клас відвідає Центр юстиції в Кельні 19 листопада. Будь ласка, зверніть увагу на форму згоди.",
          "important": "Потрібно переглянути інформацію про екскурсію та форму згоди до поїздки.",
          "sourceTimestamp": "2026-10-15T09:00:00Z", "importedAt": "2026-10-15T09:01:00Z", "orbitReadAt": null, "unread": true,
          "attachments": [{"id": "attachment-fixture-1", "filename": "JOL-15_Protagonistenvereinbarung_Film_und_Foto.pdf", "contentType": "application/pdf", "inline": false}],
          "events": [{"key": "fixture-event-1", "title": "Екскурсія до Центру юстиції", "startsAt": "2026-11-19T08:30:00Z", "endsAt": "2026-11-19T13:30:00Z", "allDay": false, "location": "Köln"}],
          "threadId": null, "subscriptionId": null,
          "tasks": [{"key": "fixture-task-1", "title": "Переглянути форму згоди", "action": "Перевірити інформацію перед поїздкою", "dueAt": "2026-11-17", "allDay": true, "importance": "high", "target": null, "confidence": 0.9, "reason": "У листі є прохання до батьків."}]
        },
        {
          "id": "fixture-message-2", "type": "message", "source": "schulmanager", "externalId": "fixture-2",
          "title": "Material für den Unterricht", "sender": "Класний керівник", "originalGerman": "Bitte bringen Sie die Materialien am Montag mit.",
          "originalPlainText": "Bitte bringen Sie die Materialien am Montag mit.", "previewPlainText": "Bitte bringen Sie die Materialien am Montag mit.",
          "titlePlainText": "Material für den Unterricht", "translationUkrainian": "Будь ласка, принесіть матеріали в понеділок.",
          "important": null, "sourceTimestamp": "2026-10-14T12:00:00Z", "importedAt": "2026-10-14T12:01:00Z", "orbitReadAt": "2026-10-14T12:05:00Z", "unread": false,
          "attachments": [], "events": [], "threadId": null, "subscriptionId": null, "tasks": []
        },
        {
          "id": "fixture-letter-3", "type": "letter", "source": "schulmanager", "externalId": "fixture-3",
          "title": "Elternabend", "sender": "Schulmanager", "originalGerman": "Der Elternabend findet nächste Woche statt.",
          "originalPlainText": "Der Elternabend findet nächste Woche statt.", "previewPlainText": "Der Elternabend findet nächste Woche statt.",
          "titlePlainText": "Elternabend", "translationUkrainian": "Батьківські збори відбудуться наступного тижня.",
          "important": "Дата та час у календарі нижче.", "sourceTimestamp": "2026-10-13T08:00:00Z", "importedAt": "2026-10-13T08:01:00Z", "orbitReadAt": null, "unread": true,
          "attachments": [], "events": [], "threadId": null, "subscriptionId": null, "tasks": []
        }
      ],
      "taskResponse": {
        "from": "2026-10-01", "to": "2026-11-30", "coverage": "all", "truncated": false, "complete": true, "completionState": "complete",
        "tasks": [{"key": "fixture-task-1", "stableIdentity": true, "title": "Переглянути форму згоди", "action": "Перевірити інформацію", "dueAt": "2026-11-17", "endsAt": null, "allDay": true, "importance": "high", "target": null, "confidence": 0.9, "reason": "У листі є прохання до батьків.", "location": null, "sourceItemId": "fixture-letter-1", "sourceType": "letter", "sourceExternalId": "2541320", "bucket": null, "status": "open", "completedAt": null, "actionTaskId": null, "calendarEventId": null}],
        "importantEvents": []
      }
    }
    """
}

#endif
