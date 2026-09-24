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
    @State private var items: [OrbitSchoolItem] = []
    @State private var filter = "all"
    @State private var error: String?
    @State private var loading = false
    @State private var notificationPermission = SchoolNotificationPermission.notDetermined
    @State private var notificationDiagnosticMessage: String?

    init(embeddedInNavigation: Bool = false) { self.embeddedInNavigation = embeddedInNavigation }

    var body: some View {
        Group {
            if embeddedInNavigation { schoolList }
            else { NavigationStack { schoolList } }
        }
    }
    private var schoolList: some View {
        List {
            Section { NavigationLink { SchoolCalendarView() } label: { Label("Календар школи", systemImage: "calendar") }; NavigationLink { SchoolTasksView() } label: { Label("Наступні 10 днів", systemImage: "checklist") } }
            Picker("Показати", selection: $filter) {
                Text("Усі").tag("all"); Text("Листи").tag("letters"); Text("Чати").tag("messages"); Text("Нові").tag("unread")
            }.pickerStyle(.segmented)
            notificationSection
            if loading { ProgressView().frame(maxWidth: .infinity) }
            if items.isEmpty && !loading { ContentUnavailableView("Школа порожня", systemImage: "graduationcap", description: Text("Нові листи та повідомлення з’являться тут.")) }
            ForEach(items) { item in NavigationLink { SchoolDetailView(item: item) } label: { schoolRow(item) } }
        }
        .navigationTitle("Школа")
        .refreshable { await load() }
        .task { await load(); await refreshNotificationPermission() }
        .onAppear { Task { await refreshNotificationPermission() } }
        .onChange(of: filter) { _, _ in Task { await load() } }
        .alert("Школа недоступна", isPresented: .constant(error != nil)) { Button("Повторити") { error = nil; Task { await load() } }; Button("Гаразд", role: .cancel) { error = nil } } message: { Text(error ?? "") }
        .alert("Сповіщення Orbit", isPresented: .constant(notificationDiagnosticMessage != nil)) { Button("Гаразд") { notificationDiagnosticMessage = nil } } message: { Text(notificationDiagnosticMessage ?? "") }
    }
    @ViewBuilder private var notificationSection: some View {
        switch notificationPermission {
        case .authorized, .provisional:
            LabeledContent { Button("Перевірити сповіщення") { Task { await scheduleDiagnosticNotification() } } } label: { Label("Сповіщення Orbit увімкнено", systemImage: "bell.badge.fill") }
        case .notDetermined:
            Button { Task { await requestNotificationPermission() } } label: { Label("Увімкнути сповіщення Orbit", systemImage: "bell.badge") }
        case .denied:
            Label("Сповіщення Orbit вимкнено в Налаштуваннях", systemImage: "bell.slash").foregroundStyle(.secondary)
        case .unavailable:
            Label("Стан сповіщень тимчасово недоступний", systemImage: "bell.slash").foregroundStyle(.secondary)
        }
    }
    private func schoolRow(_ item: OrbitSchoolItem) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack { Image(systemName: item.type == "letter" ? "envelope" : "message"); Text(item.sender.isEmpty ? (item.type == "letter" ? "Лист" : "Повідомлення") : item.sender).font(.subheadline); Spacer(); if item.unread { Circle().fill(.blue).frame(width: 8, height: 8).accessibilityLabel("Непрочитане") } }
            Text(item.titlePlainText?.isEmpty == false ? item.titlePlainText! : (item.title.isEmpty ? String((item.previewPlainText ?? item.originalPlainText ?? item.originalGerman).prefix(80)) : item.title)).font(.headline)
            Text(item.sourceTimestamp ?? item.importedAt ?? .now, format: .dateTime.day().month(.wide).year()).font(.caption).foregroundStyle(.secondary)
            Text(item.previewPlainText ?? item.originalPlainText ?? item.originalGerman).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
        }.padding(.vertical, 4)
    }
    private func load() async { loading = true; defer { loading = false }; do { items = try await MainProductAPI.shared.schoolItems(filter: filter).items; error = nil } catch { self.error = "Не вдалося завантажити шкільні матеріали." } }
    private func refreshNotificationPermission() async { notificationPermission = await SchoolNotificationCoordinator.shared.authorizationStatus() }
    private func requestNotificationPermission() async { notificationPermission = await SchoolNotificationCoordinator.shared.requestAuthorization() }
    private func scheduleDiagnosticNotification() async { notificationDiagnosticMessage = await SchoolNotificationCoordinator.shared.scheduleDiagnostic() ? "Тестове сповіщення з’явиться приблизно через 5 секунд." : "Не вдалося запланувати тестове сповіщення." }
}

struct SchoolCalendarView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var events: [OrbitSchulmanagerCalendarEvent] = []; @State private var scope = "for-us"; @State private var error: String?
    var body: some View { List { if events.isEmpty { ContentUnavailableView("Календар порожній", systemImage: "calendar", description: Text("Нові шкільні події з’являться після синхронізації.")) }; ForEach(events) { event in VStack(alignment: .leading, spacing: 5) { Text(event.title).font(.headline); Text(event.allDay ? "\(event.startsAt ?? "") – \(event.endsAt ?? event.startsAt ?? "")" : (event.startsAt ?? "Дата не визначена")).font(.subheadline); if let relevance = event.relevanceClass, relevance != "UNCERTAIN" { Text(relevance == "DIRECT" ? "Для нашого класу" : relevance == "GRADE" ? "Для 5 класу" : relevance == "SCHOOLWIDE" ? "Для всієї школи" : "Може стосуватися нас").font(.caption).foregroundStyle(.secondary) }; if !event.location.isEmpty { Text(event.location).foregroundStyle(.secondary) }; Button("Додати до сімейного календаря") { Task { await add(event) } }.buttonStyle(.bordered) } } }.navigationTitle("Календар школи").navigationBarBackButtonHidden(true).toolbar { ToolbarItem(placement: .topBarLeading) { Button { dismiss() } label: { Label("Назад", systemImage: "chevron.left") } } }.task { await load() }.alert("Календар школи", isPresented: .constant(error != nil)) { Button("Гаразд") { error = nil } } message: { Text(error ?? "") } }
    private func load() async { do { events = try await MainProductAPI.shared.schulmanagerCalendar(scope: scope) } catch { self.error = "Не вдалося завантажити календар школи." } }
    private func add(_ event: OrbitSchulmanagerCalendarEvent) async { do { let preview = try await MainProductAPI.shared.addSchoolCalendarEvent(uid: event.uid, confirm: false); if preview.duplicate == true { self.error = "Подію вже додано." } else if preview.requiresConfirmation == true { let result = try await MainProductAPI.shared.addSchoolCalendarEvent(uid: event.uid, confirm: true); self.error = result.duplicate == true ? "Подію вже додано." : (result.created ? "Подію додано до календаря." : "Не вдалося додати подію.") } } catch { self.error = "Не вдалося додати подію." } }
}

struct SchoolTasksView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tasks: [OrbitSchoolTask] = []; @State private var error: String?
    var body: some View { List { Section("Треба зробити") { if tasks.isEmpty { ContentUnavailableView("Немає шкільних завдань", systemImage: "checklist", description: Text("Немає дій, запланованих на наступні 10 днів.")) }; ForEach(tasks) { task in NavigationLink { SchoolDetailLoaderView(itemID: task.sourceItemId) } label: { VStack(alignment: .leading, spacing: 4) { Text(task.title).font(.headline); if let dueAt = task.dueAt { Text(dueAt).font(.subheadline) }; Text(task.sourceType == "letter" ? "Лист" : "Повідомлення").font(.caption).foregroundStyle(.secondary) } } } } }.navigationTitle("Наступні 10 днів").navigationBarBackButtonHidden(true).toolbar { ToolbarItem(placement: .topBarLeading) { Button { dismiss() } label: { Label("Назад", systemImage: "chevron.left") } } }.task { do { let response = try await MainProductAPI.shared.schoolTasks(); tasks = response.tasks } catch { self.error = "Не вдалося завантажити завдання." } }.alert("Шкільні завдання", isPresented: .constant(error != nil)) { Button("Гаразд") { error = nil } } message: { Text(error ?? "") } }
}
struct SchoolDetailLoaderView: View { let itemID: String; @State private var item: OrbitSchoolItem?; var body: some View { Group { if let item { SchoolDetailView(item: item) } else { ProgressView() } }.task { item = try? await MainProductAPI.shared.schoolItem(id: itemID) } } }

struct SchoolDetailView: View {
    let item: OrbitSchoolItem
    @State private var calendarMessage: String?
    @State private var pendingCalendarEvent: OrbitSchoolEvent?
    var body: some View {
        List {
            if !displayTitle.isEmpty { Section { Text(displayTitle).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled) } }
            Section("ОРИГІНАЛ") { Text(item.originalPlainText ?? item.originalGerman).textSelection(.enabled) }
            Section("ПЕРЕКЛАД") { Text(item.translationUkrainian ?? "Переклад ще готується.").textSelection(.enabled) }
            Section("ВАЖЛИВО") { Text(item.important ?? "Перевірте оригінал: структурований підсумок ще готується.").textSelection(.enabled) }
            if !item.events.isEmpty { Section("ДАТИ / ДЕДЛАЙНИ") { ForEach(item.events) { event in VStack(alignment: .leading, spacing: 6) { Text(event.title).font(.headline); if event.startsAt != nil { Text(event.allDay ? schoolAllDayRange(event) : schoolTimedDateRange(event)) }; if let location = event.location { Text(location).foregroundStyle(.secondary) }; Button("Додати до календаря") { Task { await add(event) } }.buttonStyle(.borderedProminent) } } } }
        }
        .navigationTitle("Школа")
        .navigationBarTitleDisplayMode(.inline)
        .task { try? await MainProductAPI.shared.markSchoolItemRead(id: item.id) }
        .alert("Календар", isPresented: .constant(calendarMessage != nil)) { Button("Гаразд") { calendarMessage = nil } } message: { Text(calendarMessage ?? "") }
        .alert("Додати до календаря?", isPresented: Binding(get: { pendingCalendarEvent != nil }, set: { if !$0 { pendingCalendarEvent = nil } })) { Button("Додати") { if let event = pendingCalendarEvent { pendingCalendarEvent = nil; Task { await confirm(event) } } }; Button("Скасувати", role: .cancel) { pendingCalendarEvent = nil } } message: { Text(calendarPreviewMessage) }
    }
    private var displayTitle: String { item.titlePlainText?.isEmpty == false ? item.titlePlainText! : item.title }
    private func schoolTimedDateRange(_ event: OrbitSchoolEvent) -> String { guard let start = event.startsAt else { return "Дата не визначена" }; if let end = event.endsAt, end != start { return "\(start.formatted(date: .long, time: .shortened)) – \(end.formatted(date: .long, time: .shortened))" }; return start.formatted(date: .long, time: .shortened) }
    private var calendarPreviewMessage: String { guard let event = pendingCalendarEvent else { return "" }; var lines = [event.title]; if event.startsAt != nil { lines.append(event.allDay ? schoolAllDayRange(event) : schoolTimedDateRange(event)) }; if let location = event.location, !location.isEmpty { lines.append(location) }; return lines.joined(separator: "\n") }
    private func add(_ event: OrbitSchoolEvent) async { do { let preview = try await MainProductAPI.shared.addSchoolEvent(itemID: item.id, event: event, confirm: false); if preview.duplicate == true { calendarMessage = "Подію вже додано." } else if preview.requiresConfirmation == true { pendingCalendarEvent = event } else { calendarMessage = "Не вдалося підготувати подію." } } catch { calendarMessage = "Не вдалося додати подію." } }
    private func confirm(_ event: OrbitSchoolEvent) async { do { let result = try await MainProductAPI.shared.addSchoolEvent(itemID: item.id, event: event, confirm: true); calendarMessage = result.duplicate == true ? "Подію вже додано." : (result.created ? "Подію додано до календаря." : "Не вдалося додати подію.") } catch { calendarMessage = "Не вдалося додати подію." } }
}
