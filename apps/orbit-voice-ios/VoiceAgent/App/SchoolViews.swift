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
            Section { NavigationLink { SchoolBrainView() } label: { Label("Запитати про школу", systemImage: "sparkles") }; NavigationLink { SchoolCalendarView() } label: { Label("Календар школи", systemImage: "calendar") }; NavigationLink { SchoolTasksView() } label: { Label("Наступні 10 днів", systemImage: "checklist") } }
            Picker("Показати", selection: $filter) {
                Text("Усі").tag("all"); Text("Листи").tag("letters"); Text("Чати").tag("messages"); Text("Нові").tag("unread")
            }.pickerStyle(.segmented)
            notificationSection
            if loading { ProgressView().frame(maxWidth: .infinity) }
            if items.isEmpty && !loading { ContentUnavailableView("Шкільних матеріалів не знайдено", systemImage: "graduationcap", description: Text("Для цього профілю або фільтра немає отриманих листів чи повідомлень. Час останньої синхронізації тут не показується.")) }
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

struct SchoolBrainView: View {
    @State private var messages: [OrbitSchoolBrainMessage] = []
    @State private var draft = ""
    @State private var loading = false
    @State private var error: String?
    @State private var requestGeneration = 0
    private let starters = ["Що нового?", "Що нам треба зробити?", "Що важливого цього тижня?", "Що стосується 5F?"]
    var body: some View {
        VStack(spacing: 0) {
            if messages.isEmpty { ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(starters, id: \.self) { value in Button(value) { draft = value } .buttonStyle(.bordered) } }.padding() } }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { message in
                            VStack(alignment: .leading, spacing: 6) { Text(message.role == "user" ? "Ви" : "Orbit School Brain").font(.caption).foregroundStyle(.secondary); Text(message.content).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(10).background(message.role == "user" ? Color.blue.opacity(0.12) : Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12)); if message.role == "assistant", !message.sourceRefs.isEmpty { VStack(alignment: .leading, spacing: 4) { Text("Джерела").font(.caption.weight(.semibold)).foregroundStyle(.secondary); ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(Array(message.sourceRefs.enumerated()), id: \.offset) { _, ref in if let id = ref["id"], let type = ref["type"], ["letter", "message"].contains(type) { NavigationLink { SchoolDetailLoaderView(itemID: id) } label: { Label(type == "letter" ? "Лист" : "Повідомлення", systemImage: type == "letter" ? "envelope" : "message") }.buttonStyle(.bordered) } } } } } }
                            }.id(message.id)
                        }
                    }.padding()
                }
                .onChange(of: messages.count) { _, _ in scrollToLatest(using: proxy) }
                .onAppear { scrollToLatest(using: proxy) }
            }
            HStack(alignment: .bottom) { TextField("Запитайте про школу…", text: $draft, axis: .vertical).textFieldStyle(.roundedBorder); Button { Task { await send() } } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }.disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || loading) }.padding()
        }.navigationTitle("Запитати про школу").task { await load() }.alert("School Brain", isPresented: SchoolBrainRequestState.alertBinding(error: $error)) { Button("Гаразд") { error = nil } } message: { Text(error ?? "") }
    }
    private func scrollToLatest(using proxy: ScrollViewProxy) { guard let latest = messages.last else { return }; DispatchQueue.main.async { withAnimation { proxy.scrollTo(latest.id, anchor: .bottom) } } }
    private func load() async { do { messages = try await MainProductAPI.shared.schoolBrainConversation().messages } catch { self.error = "Не вдалося завантажити розмову." } }
    private func send() async { let value = draft.trimmingCharacters(in: .whitespacesAndNewlines); guard !value.isEmpty, !loading else { return }; draft = ""; requestGeneration += 1; let generation = requestGeneration; SchoolBrainRequestState.beginRequest(error: &error); loading = true; defer { if generation == requestGeneration { loading = false } }; do { let reply = try await MainProductAPI.shared.askSchool(value); guard generation == requestGeneration else { return }; messages.append(OrbitSchoolBrainMessage(id: UUID().uuidString, role: "user", content: value, sourceRefs: [], createdAt: .now)); messages.append(reply); SchoolBrainRequestState.completedSuccessfully(error: &error) } catch is CancellationError { return } catch { guard generation == requestGeneration else { return }; self.error = "Не вдалося отримати відповідь School Brain." } }
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
