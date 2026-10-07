import SwiftUI

struct OrbitTodayView: View {
    @EnvironmentObject private var authentication: OrbitAuthentication
    let isSelected: Bool
    let open: (OrbitMainTab) -> Void

    @State private var calendar: OrbitSourceState<[OrbitCalendarEvent]> = .loading
    @State private var school: OrbitSourceState<OrbitSchoolItemsResponse> = .loading
    @State private var briefing: OrbitSourceState<OrbitSchoolBriefingResponse> = .loading
    @State private var loadedAt: Date?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: OrbitSpacing.large) {
                    header
                    quickActions
                    calendarCard
                    schoolCard
                    briefingCard
                    if let label = OrbitFreshness.label(from: loadedAt) {
                        Text("Оновлено \(label)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(OrbitSpacing.large)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Сьогодні")
            .refreshable { await load() }
        }
        .task(id: isSelected) { if isSelected { await load() } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(OrbitTodayLogic.greeting(hour: Foundation.Calendar.current.component(.hour, from: Date()), name: authentication.displayName))
                .font(.title2.weight(.semibold))
            Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.subheadline).foregroundStyle(.secondary)
                .environment(\.locale, Locale(identifier: "uk_UA"))
        }
        .accessibilityElement(children: .combine)
    }

    private var quickActions: some View {
        HStack(spacing: OrbitSpacing.medium) {
            quick("Запитати Orbit", "message", .chats)
            quick("Школа", "graduationcap", .school)
            quick("Календар", "calendar", .calendar)
        }
    }

    private func quick(_ title: String, _ icon: String, _ tab: OrbitMainTab) -> some View {
        Button { open(tab) } label: {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.title3)
                Text(title).font(.footnote.weight(.medium)).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: OrbitSpacing.minTarget)
            .padding(.vertical, OrbitSpacing.medium)
            .background(OrbitColors.card, in: RoundedRectangle(cornerRadius: OrbitRadius.card, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var calendarCard: some View {
        card("Сьогодні в календарі", icon: "calendar", destination: .calendar) {
            switch calendar {
            case .loading: ProgressView()
            case .empty: Text("На сьогодні у сімейному календарі подій немає. Зовнішні календарі тут не враховано.").foregroundStyle(.secondary)
            case .unavailable: Text("Календар недоступний для цього профілю.").foregroundStyle(.secondary)
            case let .failed(message): failure(message)
            case let .loaded(events, stale):
                if stale { staleNote }
                ForEach(events.prefix(5)) { event in
                    HStack {
                        Text(event.title).font(.subheadline)
                        Spacer()
                        Text(event.allDay ? "Весь день" : event.startsAt.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var schoolCard: some View {
        card("Школа", icon: "graduationcap", destination: .school) {
            switch school {
            case .loading: ProgressView()
            case .empty: Text("Шкільних матеріалів поки немає.").foregroundStyle(.secondary)
            case .unavailable: Text("Шкільні дані недоступні для цього профілю.").foregroundStyle(.secondary)
            case let .failed(message): failure(message)
            case let .loaded(value, stale):
                if stale { staleNote }
                Text(OrbitTodayLogic.unreadLabel(value.unreadCount)).font(.subheadline)
            }
        }
    }

    private var briefingCard: some View {
        card("Потребує уваги", icon: "exclamationmark.bubble", destination: .school) {
            switch briefing {
            case .loading: ProgressView()
            case .empty: Text("Окремих шкільних дій на найближчі дні немає.").foregroundStyle(.secondary)
            case .unavailable: Text("Огляд школи недоступний для цього профілю.").foregroundStyle(.secondary)
            case let .failed(message): failure(message)
            case let .loaded(value, stale):
                if stale { staleNote }
                ForEach(Array((value.attention + value.dated).prefix(4))) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.subheadline.weight(.medium))
                        if !item.detail.isEmpty { Text(item.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                    }
                }
            }
        }
    }

    private var staleNote: some View {
        Label("Не вдалося оновити — показано попередні дані", systemImage: "clock.badge.exclamationmark").font(.caption).foregroundStyle(.orange)
    }

    private func failure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message).font(.subheadline).foregroundStyle(.secondary)
            Button("Повторити") { Task { await load() } }.buttonStyle(.bordered)
        }
    }

    private func card<Content: View>(_ title: String, icon: String, destination: OrbitMainTab, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: OrbitSpacing.medium) {
            HStack {
                Label(title, systemImage: icon).font(.headline)
                Spacer()
                Button { open(destination) } label: { Image(systemName: "chevron.right").frame(minWidth: OrbitSpacing.minTarget, minHeight: OrbitSpacing.minTarget) }
                    .accessibilityLabel("Відкрити \(title)")
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OrbitSpacing.large)
        .background(OrbitColors.card, in: RoundedRectangle(cornerRadius: OrbitRadius.card, style: .continuous))
    }

    private func isUnavailable(_ error: Error) -> Bool { error is OrbitHTTPFailure }

    private func load() async {
        let cal = Foundation.Calendar.current
        let dayStart = cal.startOfDay(for: Date())
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) ?? Date()
        let e = await fetch { try await MainProductAPI.shared.calendarEvents(from: dayStart, to: dayEnd, classifyUnavailable: true) }
        let i = await fetch { try await MainProductAPI.shared.schoolItems(classifyUnavailable: true) }
        let b = await fetch { try await MainProductAPI.shared.schoolBriefing(classifyUnavailable: true) }
        let today = Date()
        calendar = OrbitSourceStateBuilder.resolve(result: e.map { $0.filter { OrbitTodayLogic.overlapsDay(start: $0.startsAt, end: $0.endsAt, day: today) } }, isEmpty: { $0.isEmpty }, previous: calendar, isUnavailable: isUnavailable)
        school = OrbitSourceStateBuilder.resolve(result: i, isEmpty: { $0.items.isEmpty && $0.unreadCount == 0 }, previous: school, isUnavailable: isUnavailable)
        briefing = OrbitSourceStateBuilder.resolve(result: b, isEmpty: { $0.attention.isEmpty && $0.dated.isEmpty }, previous: briefing, isUnavailable: isUnavailable)
        loadedAt = today
    }

    private func fetch<T>(_ work: @escaping () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await work()) } catch { return .failure(error) }
    }
}
