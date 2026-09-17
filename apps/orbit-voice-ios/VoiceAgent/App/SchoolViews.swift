import SwiftUI
import Foundation

private struct SchoolCalendarPreview: Identifiable { let id: String; let event: OrbitSchoolEvent }
private func readableSchoolText(_ value: String) -> String {
    guard value.contains("<") else { return value }
    if let data = value.data(using: .utf8), let rich = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil) { return rich.string.replacingOccurrences(of: "\u{00a0}", with: " ").trimmingCharacters(in: .whitespacesAndNewlines) }
    return value.replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive).replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
}
private let schoolDateFormatter: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "uk_UA"); f.dateStyle = .long; f.timeStyle = .none; return f }()

struct SchoolInboxView: View {
    @State private var items: [OrbitSchoolItem] = []; @State private var filter = "all"; @State private var error: String?; @State private var loading = false
    var body: some View {
        NavigationStack { List {
            Picker("Показати", selection: $filter) { Text("Усі").tag("all"); Text("Листи").tag("letters"); Text("Повідомлення").tag("messages"); Text("Нові").tag("unread") }.pickerStyle(.segmented)
            Button { Task { _ = await SchoolNotificationCoordinator.shared.requestAuthorization() } } label: { Label("Увімкнути сповіщення Orbit", systemImage: "bell.badge") }
            if loading { ProgressView().frame(maxWidth: .infinity) }
            if items.isEmpty && !loading { ContentUnavailableView("Школа порожня", systemImage: "graduationcap", description: Text("Нові листи та повідомлення з’являться тут.")) }
            ForEach(items) { item in NavigationLink { SchoolDetailView(item: item) } label: { schoolRow(item) } }
        }.navigationTitle("Школа").refreshable { await load() }.task { await load() }.onChange(of: filter) { _, _ in Task { await load() } }.alert("Школа недоступна", isPresented: .constant(error != nil)) { Button("Повторити") { error = nil; Task { await load() } }; Button("Гаразд", role: .cancel) { error = nil } } message: { Text(error ?? "") } }
    }
    private func schoolRow(_ item: OrbitSchoolItem) -> some View { VStack(alignment: .leading, spacing: 5) { HStack { Image(systemName: item.type == "letter" ? "envelope" : "message"); Text(item.sender.isEmpty ? (item.type == "letter" ? "Лист" : "Повідомлення") : item.sender).font(.subheadline); Spacer(); if item.unread { Circle().fill(.blue).frame(width: 8, height: 8).accessibilityLabel("Непрочитане") } }; Text(item.title.isEmpty ? String(readableSchoolText(item.originalGerman).prefix(80)) : readableSchoolText(item.title)).font(.headline).lineLimit(2); Text(item.sourceTimestamp ?? item.importedAt ?? .now, formatter: schoolDateFormatter).font(.caption).foregroundStyle(.secondary); Text(readableSchoolText(item.originalGerman)).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }.padding(.vertical, 4) }
    private func load() async { loading = true; defer { loading = false }; do { items = try await MainProductAPI.shared.schoolItems(filter: filter).items; error = nil } catch { self.error = "Не вдалося завантажити шкільні матеріали." } }
}

struct SchoolDetailView: View {
    let item: OrbitSchoolItem; @State private var calendarPreview: SchoolCalendarPreview?; @State private var calendarMessage: String?
    var body: some View { List { Section("ОРИГІНАЛ") { Text(readableSchoolText(item.originalGerman)).textSelection(.enabled) }; Section("ПЕРЕКЛАД") { Text(item.translationUkrainian ?? "Переклад ще готується.").textSelection(.enabled) }; Section("ВАЖЛИВО") { Text(item.important ?? "Перевірте оригінал: структурований підсумок ще готується.").textSelection(.enabled) }; if !item.events.isEmpty { Section("ДАТИ / ДЕДЛАЙНИ") { ForEach(item.events) { event in eventRow(event) } } } }.navigationTitle(readableSchoolText(item.title).isEmpty ? "Школа" : readableSchoolText(item.title)).navigationBarTitleDisplayMode(.inline).task { try? await MainProductAPI.shared.markSchoolItemRead(id: item.id) }.sheet(item: $calendarPreview) { preview in NavigationStack { List { Section("Подія") { Text(preview.event.title).font(.headline); if let starts = preview.event.startsAt { Text(dateRange(for: preview.event)); if !preview.event.allDay { Text(starts, style: .time) } }; if let location = preview.event.location { Text(location).foregroundStyle(.secondary) } }; Section { Button("Підтвердити і додати") { Task { await confirm(preview.event) } }.buttonStyle(.borderedProminent); Button("Скасувати", role: .cancel) { calendarPreview = nil } } }.navigationTitle("Перевірте подію").navigationBarTitleDisplayMode(.inline) } }.alert("Календар", isPresented: .constant(calendarMessage != nil)) { Button("Гаразд") { calendarMessage = nil } } message: { Text(calendarMessage ?? "") } }
    private func eventRow(_ event: OrbitSchoolEvent) -> some View { VStack(alignment: .leading, spacing: 6) { Text(event.title).font(.headline); if event.startsAt != nil { Text(dateRange(for: event)); if !event.allDay, let starts = event.startsAt { Text(starts, style: .time) } }; if let location = event.location { Text(location).foregroundStyle(.secondary) }; Button("Додати до календаря") { Task { await preview(event) } }.buttonStyle(.borderedProminent) } }
    private func dateRange(for event: OrbitSchoolEvent) -> String { guard let start = event.startsAt else { return "Дата не визначена" }; let first = schoolDateFormatter.string(from: start); guard let end = event.endsAt, Calendar.current.startOfDay(for: end) != Calendar.current.startOfDay(for: start) else { return first }; return "\(first) – \(schoolDateFormatter.string(from: end))" }
    private func preview(_ event: OrbitSchoolEvent) async { do { let result = try await MainProductAPI.shared.addSchoolEvent(itemID: item.id, event: event, confirm: false); if result.duplicate == true { calendarMessage = "Подію вже додано." } else if result.requiresConfirmation == true { calendarPreview = SchoolCalendarPreview(id: event.key, event: event) } } catch { calendarMessage = "Не вдалося підготувати подію." } }
    private func confirm(_ event: OrbitSchoolEvent) async { do { let result = try await MainProductAPI.shared.addSchoolEvent(itemID: item.id, event: event, confirm: true); calendarPreview = nil; calendarMessage = result.duplicate == true ? "Подію вже додано." : "Подію додано до календаря." } catch { calendarMessage = "Не вдалося додати подію." } }
}
