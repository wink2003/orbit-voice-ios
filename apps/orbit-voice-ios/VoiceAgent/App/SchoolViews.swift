import SwiftUI

struct SchoolInboxView: View {
    @State private var items: [OrbitSchoolItem] = []
    @State private var filter = "all"
    @State private var error: String?
    @State private var loading = false
    var body: some View {
        NavigationStack {
            List {
                Picker("Показати", selection: $filter) { Text("Усі").tag("all"); Text("Листи").tag("letters"); Text("Повідомлення").tag("messages"); Text("Непрочитані").tag("unread") }.pickerStyle(.segmented)
                Button { Task { _ = await SchoolNotificationCoordinator.shared.requestAuthorization() } } label: { Label("Увімкнути сповіщення Orbit", systemImage: "bell.badge") }
                if loading { ProgressView().frame(maxWidth: .infinity) }
                if items.isEmpty && !loading { ContentUnavailableView("Школа порожня", systemImage: "graduationcap", description: Text("Нові листи та повідомлення з’являться тут.")) }
                ForEach(items) { item in NavigationLink { SchoolDetailView(item: item) } label: { schoolRow(item) } }
            }
            .navigationTitle("Школа")
            .refreshable { await load() }
            .task { await load() }
            .onChange(of: filter) { _, _ in Task { await load() } }
            .alert("Школа недоступна", isPresented: .constant(error != nil)) { Button("Повторити") { error = nil; Task { await load() } }; Button("Гаразд", role: .cancel) { error = nil } } message: { Text(error ?? "") }
        }
    }
    private func schoolRow(_ item: OrbitSchoolItem) -> some View { VStack(alignment: .leading, spacing: 5) { HStack { Image(systemName: item.type == "letter" ? "envelope" : "message"); Text(item.sender.isEmpty ? (item.type == "letter" ? "Лист" : "Повідомлення") : item.sender).font(.subheadline); Spacer(); if item.unread { Circle().fill(.blue).frame(width: 8, height: 8).accessibilityLabel("Непрочитане") } }; Text(item.title.isEmpty ? String(item.originalGerman.prefix(80)) : item.title).font(.headline); Text(item.sourceTimestamp ?? item.importedAt ?? .now, style: .date).font(.caption).foregroundStyle(.secondary); Text(item.originalGerman).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }.padding(.vertical, 4) }
    private func load() async { loading = true; defer { loading = false }; do { items = try await MainProductAPI.shared.schoolItems(filter: filter).items; error = nil } catch { self.error = "Не вдалося завантажити шкільні матеріали." } }
}

struct SchoolDetailView: View {
    let item: OrbitSchoolItem
    @State private var calendarMessage: String?
    @State private var pendingCalendarEvent: OrbitSchoolEvent?
    var body: some View {
        List {
            Section("ОРИГІНАЛ") { Text(item.originalGerman).textSelection(.enabled) }
            Section("ПЕРЕКЛАД") { Text(item.translationUkrainian ?? "Переклад ще готується.").textSelection(.enabled) }
            Section("ВАЖЛИВО") { Text(item.important ?? "Перевірте оригінал: структурований підсумок ще готується.").textSelection(.enabled) }
            if !item.events.isEmpty { Section("ДАТИ / ДЕДЛАЙНИ") { ForEach(item.events) { event in VStack(alignment: .leading) { Text(event.title).font(.headline); if let starts = event.startsAt { Text(starts, style: .date); if !event.allDay { Text(starts, style: .time) } }; if let location = event.location { Text(location).foregroundStyle(.secondary) }; Button("Додати до календаря") { Task { await add(event) } }.buttonStyle(.borderedProminent) } } } }
        }.navigationTitle(item.title.isEmpty ? "Школа" : item.title).navigationBarTitleDisplayMode(.inline).task { try? await MainProductAPI.shared.markSchoolItemRead(id: item.id) }.alert("Календар", isPresented: .constant(calendarMessage != nil)) { Button("Гаразд") { calendarMessage = nil } } message: { Text(calendarMessage ?? "") }.alert("Додати до календаря?", isPresented: Binding(get: { pendingCalendarEvent != nil }, set: { if !$0 { pendingCalendarEvent = nil } })) { Button("Додати") { if let event = pendingCalendarEvent { pendingCalendarEvent = nil; Task { await confirm(event) } } }; Button("Скасувати", role: .cancel) { pendingCalendarEvent = nil } } message: { Text(calendarPreviewMessage) }
    }
    private var calendarPreviewMessage: String {
        guard let event = pendingCalendarEvent else { return "" }
        var lines = [event.title]
        if let starts = event.startsAt {
            let start = starts.formatted(date: .abbreviated, time: event.allDay ? .omitted : .shortened)
            if let ends = event.endsAt, ends != starts {
                lines.append("\(start) — \(ends.formatted(date: .abbreviated, time: event.allDay ? .omitted : .shortened))")
            } else {
                lines.append(start)
            }
        }
        if let location = event.location, !location.isEmpty { lines.append(location) }
        return lines.joined(separator: "\n")
    }
    private func add(_ event: OrbitSchoolEvent) async {
        do {
            let preview = try await MainProductAPI.shared.addSchoolEvent(itemID: item.id, event: event, confirm: false)
            if preview.duplicate == true {
                calendarMessage = "Подію вже додано."
            } else if preview.requiresConfirmation == true {
                pendingCalendarEvent = event
            } else {
                calendarMessage = "Не вдалося підготувати подію."
            }
        } catch {
            calendarMessage = "Не вдалося додати подію."
        }
    }
    private func confirm(_ event: OrbitSchoolEvent) async {
        do {
            let result = try await MainProductAPI.shared.addSchoolEvent(itemID: item.id, event: event, confirm: true)
            calendarMessage = result.duplicate == true ? "Подію вже додано." : (result.created ? "Подію додано до календаря." : "Не вдалося додати подію.")
        } catch {
            calendarMessage = "Не вдалося додати подію."
        }
    }
}
