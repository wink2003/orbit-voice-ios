import SwiftUI

/// Native Nova Today. All displayed content comes from existing authorized read APIs.
struct OrbitTodayView: View {
    @EnvironmentObject private var authentication: OrbitAuthentication
    let open: (OrbitMainTab) -> Void

    @State private var calendar: OrbitSourceState<[OrbitCalendarEvent]> = .loading
    @State private var school: OrbitSourceState<OrbitSchoolItemsResponse> = .loading
    @State private var tasks: OrbitSourceState<OrbitSchoolTasksResponse> = .loading
    @State private var loadedAt: Date?

    private var day: Date { Date() }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: NovaToday.sectionGap) {
                    header
                    summary
                    agenda
                    schoolSection
                    quickActions
                    freshness
                }
                .padding(.horizontal, NovaToday.pagePadding)
                .padding(.top, 8)
                .padding(.bottom, 36)
            }
            .safeAreaPadding(.bottom, 18)
            .background(NovaToday.canvas.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Сьогодні").font(.headline.weight(.bold))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { OrbitVoiceSheet() } label: {
                        Image(systemName: "waveform")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(NovaToday.indigo, in: Circle())
                    }
                    .accessibilityLabel("Почати голосову розмову")
                }
            }
            .refreshable { await load() }
            .task { await load() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("ORBIT FAMILY")
                .font(.caption.weight(.bold))
                .tracking(2.1)
                .foregroundStyle(NovaToday.indigo)
            Text(OrbitTodayLogic.greeting(
                hour: Calendar.current.component(.hour, from: day),
                name: authentication.displayName?.split(separator: " ").first.map(String.init)
            ))
            .font(.system(.largeTitle, design: .rounded).weight(.bold))
            Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .environment(\.locale, Locale(identifier: "uk_UA"))
        }
        .accessibilityElement(children: .combine)
    }

    private var summary: some View {
        NovaSurface(tint: summaryTint) {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: attentionCount == 0 ? "checkmark.seal.fill" : "sparkles")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(summaryTint)
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text(attentionCount == 0 ? "День виглядає спокійно" : "Є кілька речей для уваги")
                        .font(.headline)
                    Text(attentionCount == 0
                         ? "Показано лише дані з доступних авторизованих джерел."
                         : attentionLabel(attentionCount))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var agenda: some View {
        VStack(alignment: .leading, spacing: 10) {
            NovaSectionHeader(eyebrow: "РИТМ ДНЯ", title: "Найближче", actionTitle: "Календар") {
                open(.orbit)
            }
            NovaSurface(tint: NovaToday.indigo) {
                switch calendar {
                case .loading:
                    NovaLoadingRows()
                case .unavailable:
                    NovaUnavailable(text: "Календар недоступний для цього профілю.")
                case let .failed(message):
                    NovaFailure(message: message, retry: retry)
                case .empty:
                    NovaEmpty(icon: "calendar", text: "На сьогодні подій немає.")
                case let .loaded(events, stale):
                    if stale { NovaStaleLabel() }
                    let visible = events
                        .filter { OrbitTodayLogic.overlapsDay(start: $0.startsAt, end: $0.endsAt, day: day) }
                        .sorted { $0.startsAt < $1.startsAt }
                    if visible.isEmpty {
                        NovaEmpty(icon: "calendar", text: "На сьогодні подій немає.")
                    } else {
                        ForEach(Array(visible.prefix(4))) { event in
                            NovaEventRow(event: event)
                        }
                    }
                }
            }
        }
    }

    private var schoolSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            NovaSectionHeader(eyebrow: "ШКОЛА", title: "Потрібно знати", actionTitle: "Відкрити") {
                open(.school)
            }
            NovaSurface(tint: NovaToday.teal) {
                switch school {
                case .loading:
                    NovaLoadingRows()
                case .unavailable:
                    NovaUnavailable(text: "Шкільні дані недоступні для цього профілю.")
                case let .failed(message):
                    NovaFailure(message: message, retry: retry)
                case .empty:
                    NovaEmpty(icon: "graduationcap", text: "Нових шкільних матеріалів немає.")
                case let .loaded(value, stale):
                    if stale { NovaStaleLabel() }
                    let unread = value.items.filter(\.unread)
                    if unread.isEmpty && dueTasks.isEmpty {
                        NovaEmpty(icon: "checkmark.circle", text: "Наразі немає нових шкільних справ.")
                    } else {
                        ForEach(Array(unread.prefix(2))) { item in
                            NavigationLink { SchoolDetailView(item: item) } label: {
                                NovaSchoolRow(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                        ForEach(Array(dueTasks.prefix(2))) { task in
                            NovaTaskRow(task: task, source: value.items.first { $0.id == task.sourceItemId }, open: open)
                        }
                    }
                }
            }
        }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ШВИДКИЙ ДОСТУП")
                .font(.caption.weight(.bold))
                .tracking(1.5)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                NovaAction(title: "Запитати Orbit", icon: "sparkles", tint: NovaToday.indigo) { open(.orbit) }
                NavigationLink { OrbitCalendarView() } label: {
                    NovaActionLabel(title: "Календар", icon: "calendar", tint: NovaToday.coral)
                }
                .buttonStyle(.plain)
                NovaAction(title: "Школа", icon: "graduationcap", tint: NovaToday.teal) { open(.school) }
            }
        }
    }

    private var freshness: some View {
        Group {
            if let label = OrbitFreshness.label(from: loadedAt) {
                Label("Дані оновлено \(label)", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private var attentionCount: Int {
        (school.value?.unreadCount ?? 0) + dueTasks.count
    }

    private var summaryTint: Color {
        attentionCount == 0 ? .green : NovaToday.coral
    }

    private var dueTasks: [OrbitSchoolTask] {
        guard let value = tasks.value else { return [] }
        let todayKey = SchoolHubLogic.dayKey(of: day)
        return value.tasks
            .filter {
                guard let due = SchoolHubLogic.dayKey(for: $0.dueAt, allDay: $0.allDay) else { return false }
                return due <= todayKey
            }
            .sorted { ($0.dueAt ?? "") < ($1.dueAt ?? "") }
    }

    private func attentionLabel(_ count: Int) -> String {
        if count == 1 { return "1 елемент із доступного контексту може потребувати уваги." }
        return "\(count) елементи із доступного контексту можуть потребувати уваги."
    }

    private func retry() {
        Task { await load() }
    }

    private func load() async {
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? day
        async let calendarResult = fetch {
            try await MainProductAPI.shared.calendarEvents(from: start, to: end, classifyUnavailable: true)
        }
        async let schoolResult = fetch {
            try await MainProductAPI.shared.schoolItems(classifyUnavailable: true)
        }
        async let taskResult = fetch {
            try await MainProductAPI.shared.schoolTasks()
        }
        let results = await (calendarResult, schoolResult, taskResult)
        calendar = OrbitSourceStateBuilder.resolve(result: results.0, isEmpty: { $0.isEmpty }, previous: calendar, isUnavailable: isUnavailable)
        school = OrbitSourceStateBuilder.resolve(result: results.1, isEmpty: { $0.items.isEmpty && $0.unreadCount == 0 }, previous: school, isUnavailable: isUnavailable)
        tasks = OrbitSourceStateBuilder.resolve(result: results.2, isEmpty: { $0.tasks.isEmpty }, previous: tasks, isUnavailable: isUnavailable)
        loadedAt = Date()
    }

    private func isUnavailable(_ error: Error) -> Bool {
        error is OrbitHTTPFailure
    }

    private func fetch<T>(_ work: @escaping () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await work()) }
        catch { return .failure(error) }
    }
}
private enum NovaToday {
    static let indigo = Color(red: 0.28, green: 0.30, blue: 0.82)
    static let teal = Color(red: 0.03, green: 0.52, blue: 0.50)
    static let coral = Color(red: 0.84, green: 0.35, blue: 0.24)
    static let canvas = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.045, green: 0.05, blue: 0.07, alpha: 1)
            : UIColor(red: 0.965, green: 0.968, blue: 0.982, alpha: 1)
    })
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let pagePadding: CGFloat = 16
    static let sectionGap: CGFloat = 22
    static let radius: CGFloat = 20
}

private struct NovaSurface<Content: View>: View {
    let tint: Color
    let content: Content

    init(tint: Color, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NovaToday.surface, in: RoundedRectangle(cornerRadius: NovaToday.radius, style: .continuous))
            .overlay(alignment: .leading) {
                Capsule().fill(tint).frame(width: 4).padding(.vertical, 16)
            }
            .overlay {
                RoundedRectangle(cornerRadius: NovaToday.radius, style: .continuous)
                    .stroke(.primary.opacity(0.07), lineWidth: 1)
            }
    }
}

private struct NovaSectionHeader: View {
    let eyebrow: String
    let title: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 3) {
                Text(eyebrow).font(.caption2.weight(.bold)).tracking(1.3).foregroundStyle(.secondary)
                Text(title).font(.title3.weight(.bold))
            }
            Spacer(minLength: 8)
            Button(actionTitle, action: action)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(NovaToday.indigo)
                .frame(minHeight: 44)
        }
    }
}

private struct NovaEventRow: View {
    let event: OrbitCalendarEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 3) {
                Text(event.allDay ? "ALL" : event.startsAt.formatted(date: .omitted, time: .shortened))
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(NovaToday.indigo)
                    .multilineTextAlignment(.center)
                Circle().fill(NovaToday.indigo).frame(width: 6, height: 6)
            }
            .frame(width: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                if let source = event.sourceName, !source.isEmpty {
                    Text(source).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44, alignment: .center)
        .accessibilityElement(children: .combine)
    }
}

private struct NovaSchoolRow: View {
    let item: OrbitSchoolItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.type == "letter" ? "envelope.fill" : "bubble.left.fill")
                .foregroundStyle(NovaToday.teal)
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.titlePlainText?.isEmpty == false ? item.titlePlainText! : item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(item.sender.isEmpty ? "Шкільне оновлення" : item.sender)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Circle().fill(NovaToday.teal).frame(width: 8, height: 8).padding(.top, 5)
        }
        .frame(minHeight: 44, alignment: .center)
        .accessibilityElement(children: .combine)
    }
}

private struct NovaTaskRow: View {
    let task: OrbitSchoolTask
    let source: OrbitSchoolItem?
    let open: (OrbitMainTab) -> Void

    var body: some View {
        Group {
            if let source {
                NavigationLink { SchoolDetailView(item: source) } label: { row }
            } else {
                Button { open(.school) } label: { row }
            }
        }
        .buttonStyle(.plain)
    }

    private var row: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "circle")
                .font(.title3)
                .foregroundStyle(NovaToday.coral)
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(taskDate).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
        }
        .frame(minHeight: 44, alignment: .center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Відкрита шкільна справа: \(task.title). \(taskDate)")
    }

    private var taskDate: String {
        guard let due = task.dueAt, let date = OrbitSchoolDateDecoding.date(from: due) else {
            return "Термін не вказано"
        }
        return "Термін: " + date.formatted(date: .abbreviated, time: .omitted)
    }
}

private struct NovaAction: View {
    let title: String
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            NovaActionLabel(title: title, icon: icon, tint: tint)
        }
        .buttonStyle(.plain)
    }
}

private struct NovaActionLabel: View {
    let title: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: icon).font(.headline.weight(.semibold)).foregroundStyle(tint)
            Text(title).font(.caption.weight(.semibold)).multilineTextAlignment(.center).lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 70)
        .padding(.horizontal, 5)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .contentShape(Rectangle())
    }
}

private struct NovaLoadingRows: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            RoundedRectangle(cornerRadius: 5).fill(.secondary.opacity(0.14)).frame(height: 13)
            RoundedRectangle(cornerRadius: 5).fill(.secondary.opacity(0.10)).frame(width: 190, height: 13)
        }
        .redacted(reason: .placeholder)
        .frame(minHeight: 44, alignment: .leading)
    }
}

private struct NovaEmpty: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(minHeight: 44, alignment: .leading)
    }
}

private struct NovaUnavailable: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "lock.slash")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(minHeight: 44, alignment: .leading)
    }
}

private struct NovaFailure: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message).font(.subheadline).foregroundStyle(.secondary)
            Button("Повторити", action: retry).buttonStyle(.bordered)
        }
    }
}

private struct NovaStaleLabel: View {
    var body: some View {
        Label("Не вдалося оновити — показано попередні дані", systemImage: "clock.badge.exclamationmark")
            .font(.caption)
            .foregroundStyle(.orange)
    }
}
