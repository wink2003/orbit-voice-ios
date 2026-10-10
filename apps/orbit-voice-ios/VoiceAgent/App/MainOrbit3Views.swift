import SwiftUI

// Main Orbit 3.0 presentation layer. The views use the existing authenticated
// API and domain models; they do not introduce a second data or action path.

private enum Orbit3Theme {
    static let orbit = Color(red: 0.34, green: 0.35, blue: 0.88)
    static let school = Color(red: 0.05, green: 0.52, blue: 0.51)
    static let warm = Color(red: 0.82, green: 0.46, blue: 0.14)
    static let canvas = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.055, green: 0.06, blue: 0.08, alpha: 1)
            : UIColor(red: 0.965, green: 0.969, blue: 0.984, alpha: 1)
    })
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let radius: CGFloat = 20
}

private struct Orbit3Card<Content: View>: View {
    let tint: Color
    let content: Content

    init(tint: Color = Orbit3Theme.orbit, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Orbit3Theme.radius, style: .continuous))
            .overlay(alignment: .leading) {
                Capsule().fill(tint).frame(width: 3).padding(.vertical, 15)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Orbit3Theme.radius, style: .continuous)
                    .stroke(.primary.opacity(0.07), lineWidth: 1)
            }
    }
}

private struct Orbit3SectionTitle: View {
    let title: String
    let detail: String
    var action: (() -> Void)?
    var actionTitle: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.title3.weight(.bold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let action, let actionTitle {
                Button(actionTitle, action: action)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Orbit3Theme.orbit)
                    .frame(minHeight: 44)
            }
        }
    }
}

private struct Orbit3Pill: View {
    let title: String
    let tint: Color

    init(_ title: String, tint: Color = Orbit3Theme.orbit) {
        self.title = title
        self.tint = tint
    }

    var body: some View {
        Text(title)
            .font(.caption2.weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

struct MainOrbit3HomeView: View {
    let open: (OrbitMainTab) -> Void

    @EnvironmentObject private var authentication: OrbitAuthentication
    @State private var messages: [OrbitFamilyMessage] = []
    @State private var familyEvents: [OrbitCalendarEvent] = []
    @State private var schoolItems: [OrbitSchoolItem] = []
    @State private var schoolTasks: [OrbitSchoolTask] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showCalendar = false

    private var unreadCount: Int { schoolItems.filter(\.unread).count }
    private var attentionTasks: [OrbitSchoolTask] { schoolTasks.filter { task in
        guard let date = taskDate(task.dueAt) else { return false }
        return date < Calendar.current.startOfDay(for: .now.addingTimeInterval(86400))
    }.sorted { (taskDate($0.dueAt) ?? .distantFuture) < (taskDate($1.dueAt) ?? .distantFuture) } }
    private var todayEvents: [OrbitCalendarEvent] { familyEvents.filter { Calendar.current.isDateInToday($0.startsAt) }.sorted { $0.startsAt < $1.startsAt } }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    identityHeader
                    briefingCard
                    attentionSection
                    todaySection
                    askSection
                    familySignal
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(Orbit3Theme.canvas.ignoresSafeArea())
            .navigationTitle("Orbit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { OrbitMoreView() } label: {
                        Image(systemName: "slider.horizontal.3")
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Налаштування і більше")
                }
            }
            .navigationDestination(isPresented: $showCalendar) {
                OrbitCalendarView()
            }
            .task { await load() }
            .refreshable { await load() }
            .alert("Дані Orbit недоступні", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("Гаразд") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Спробуйте оновити ще раз.")
            }
        }
    }

    private var identityHeader: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ORBIT FAMILY").font(.caption.weight(.bold)).tracking(2.2).foregroundStyle(Orbit3Theme.orbit)
                Text(greeting).font(.largeTitle.weight(.bold)).tracking(-0.5)
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .environment(\.locale, Locale(identifier: "uk_UA"))
            }
            Spacer()
            NavigationLink { OrbitVoiceSheet() } label: {
                Image(systemName: "waveform")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(Orbit3Theme.orbit.gradient, in: Circle())
                    .shadow(color: Orbit3Theme.orbit.opacity(0.28), radius: 12, y: 6)
            }
            .accessibilityLabel("Почати голосову розмову")
        }
        .accessibilityElement(children: .combine)
    }

    private var briefingCard: some View {
        Orbit3Card(tint: attentionCount == 0 ? .green : Orbit3Theme.warm) {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: attentionCount == 0 ? "checkmark.seal.fill" : "sparkles")
                    .font(.title2)
                    .foregroundStyle(attentionCount == 0 ? .green : Orbit3Theme.warm)
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 5) {
                    Text(attentionCount == 0 ? "Простір для важливого" : "Ось що важливо")
                        .font(.headline)
                    Text(briefingText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var attentionCount: Int { attentionTasks.count + unreadCount }
    private var briefingText: String {
        if attentionCount == 0 { return "Немає відкритих шкільних справ або непрочитаних оновлень у доступних джерелах." }
        return "\(attentionCount) елементів із вашого доступного контексту можуть потребувати уваги."
    }

    @ViewBuilder private var attentionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Orbit3SectionTitle(title: "Потребує уваги", detail: "Пріоритети з авторизованих шкільних даних", action: { open(.school) }, actionTitle: "Школа")
            if isLoading && attentionCount == 0 {
                Orbit3Card(tint: Orbit3Theme.warm) { Orbit3LoadingRows() }
            } else if attentionCount == 0 {
                Orbit3Card(tint: .green) {
                    Label("Наразі все спокійно", systemImage: "checkmark.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                }
            } else {
                ForEach(Array(attentionTasks.prefix(2))) { task in
                    NavigationLink { SchoolInboxView() } label: {
                        Orbit3AttentionRow(icon: "checklist", title: task.title, detail: dueText(task.dueAt), tint: Orbit3Theme.warm)
                    }.buttonStyle(.plain)
                }
                ForEach(Array(schoolItems.filter(\.unread).prefix(2))) { item in
                    NavigationLink { SchoolDetailView(item: item) } label: {
                        Orbit3AttentionRow(icon: item.type == "letter" ? "envelope" : "bubble.left", title: schoolTitle(item), detail: item.sender.isEmpty ? "Нове шкільне оновлення" : item.sender, tint: Orbit3Theme.school)
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder private var todaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Orbit3SectionTitle(title: "Сьогодні", detail: "Сімейний календар і швидкий доступ", action: { showCalendar = true }, actionTitle: "Календар")
            Orbit3Card(tint: Orbit3Theme.orbit) {
                if todayEvents.isEmpty && !isLoading {
                    Label("Сімейний календар сьогодні порожній", systemImage: "calendar")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else if todayEvents.isEmpty {
                    Orbit3LoadingRows()
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(todayEvents.prefix(4))) { event in
                            HStack(spacing: 10) {
                                Text(event.startsAt.formatted(date: .omitted, time: .shortened))
                                    .font(.caption.weight(.bold)).foregroundStyle(Orbit3Theme.orbit).frame(width: 50, alignment: .leading)
                                Text(event.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 8)
                            if event.id != todayEvents.prefix(4).last?.id { Divider().padding(.leading, 60) }
                        }
                    }
                }
            }
        }
    }

    private var askSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Orbit3SectionTitle(title: "Запитати Orbit", detail: "Ваші дані залишаються у звичних безпечних межах")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 9) {
                    NavigationLink { OrbitChatsView(contactPrompt: "Що мені потрібно зробити сьогодні?") } label: { Orbit3Prompt(title: "Мій день", icon: "sparkles") }
                    NavigationLink { OrbitChatsView(contactPrompt: "Що нового зі школи?") } label: { Orbit3Prompt(title: "Шкільні новини", icon: "graduationcap") }
                    NavigationLink { OrbitVoiceSheet() } label: { Orbit3Prompt(title: "Голос", icon: "waveform") }
                }
            }
        }
    }

    private var familySignal: some View {
        NavigationLink { MainOrbit3FamilyView() } label: {
            Orbit3Card(tint: .purple) {
                HStack(spacing: 12) {
                    Image(systemName: "person.3.fill").font(.title3).foregroundStyle(.purple).frame(width: 32)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Сімейний контекст").font(.headline)
                        Text(messages.isEmpty ? "Профілі, спільні повідомлення і приватність — в одному місці." : "Остання сімейна активність доступна у спільному просторі.")
                            .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let name = authentication.displayName?.split(separator: " ").first.map(String.init)
        let base = hour < 12 ? "Доброго ранку" : hour < 18 ? "Добрий день" : "Добрий вечір"
        return name.map { "\(base), \($0)" } ?? base
    }

    private func schoolTitle(_ item: OrbitSchoolItem) -> String { item.titlePlainText?.isEmpty == false ? item.titlePlainText! : item.title }
    private func taskDate(_ value: String?) -> Date? { value.flatMap { OrbitSchoolDateDecoding.date(from: $0) } }
    private func dueText(_ value: String?) -> String { guard let date = taskDate(value) else { return "Термін не вказано" }; return "До \(date.formatted(date: .abbreviated, time: .omitted))" }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        async let messagesResult = MainProductAPI.shared.familyMessages(limit: 4)
        async let calendar = MainProductAPI.shared.calendarEvents(from: .now, to: Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now, classifyUnavailable: true)
        async let items = MainProductAPI.shared.schoolItems(classifyUnavailable: true)
        async let tasks = MainProductAPI.shared.schoolTasks()
        do {
            messages = try await messagesResult
            familyEvents = try await calendar
            schoolItems = try await items.items
            schoolTasks = try await tasks.tasks
        } catch {
            errorMessage = "Деякі дані Orbit тимчасово недоступні. Доступні розділи залишаються відкритими."
            _ = try? await messagesResult
            _ = try? await calendar
            _ = try? await items
            _ = try? await tasks
        }
    }
}

private struct Orbit3AttentionRow: View {
    let icon: String
    let title: String
    let detail: String
    let tint: Color

    var body: some View {
        Orbit3Card(tint: tint) {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(tint).frame(width: 25)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline.weight(.semibold)).lineLimit(2)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
            }
        }
    }
}

private struct Orbit3Prompt: View {
    let title: String
    let icon: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Orbit3Theme.orbit)
            .padding(.horizontal, 13)
            .frame(minHeight: 44)
            .background(Orbit3Theme.orbit.opacity(0.1), in: Capsule())
    }
}

private struct Orbit3LoadingRows: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 4).fill(.secondary.opacity(0.14)).frame(height: 12)
            RoundedRectangle(cornerRadius: 4).fill(.secondary.opacity(0.10)).frame(width: 190, height: 12)
        }
        .redacted(reason: .placeholder)
    }
}

struct MainOrbit3FamilyView: View {
    @State private var profiles: [OrbitFamilyProfile] = []
    @State private var messages: [OrbitFamilyMessage] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("СІМЕЙНИЙ ПРОСТІР").font(.caption.weight(.bold)).tracking(1.8).foregroundStyle(.purple)
                        Text("Разом, але приватно").font(.largeTitle.weight(.bold)).tracking(-0.4)
                        Text("Контекст родини, спільні повідомлення і межі доступу в одному спокійному місці.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Orbit3Card(tint: .purple) {
                        VStack(alignment: .leading, spacing: 14) {
                            Orbit3SectionTitle(title: "Профілі родини", detail: "Доступ визначається сервером")
                            if profiles.isEmpty && isLoading { Orbit3LoadingRows() }
                            else if profiles.isEmpty { Text("Профілі ще не доступні.").foregroundStyle(.secondary) }
                            else {
                                ForEach(profiles) { profile in
                                    HStack(spacing: 12) {
                                        Text(initials(profile.displayName)).font(.headline).foregroundStyle(.white).frame(width: 40, height: 40).background(profile.isMinor ? Orbit3Theme.school : .purple, in: Circle())
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(profile.displayName).font(.headline)
                                            Text(profile.isMinor ? "Дитина" : "Член родини").font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }
                                    .accessibilityElement(children: .combine)
                                }
                            }
                        }
                    }
                    NavigationLink { FamilyMessengerView() } label: {
                        Orbit3Card(tint: Orbit3Theme.orbit) {
                            Label("Родинний чат", systemImage: "bubble.left.and.bubble.right.fill")
                                .font(.headline).foregroundStyle(.primary)
                            Text(messages.isEmpty ? "Почніть спільну розмову" : "Відкрити останні повідомлення")
                                .font(.subheadline).foregroundStyle(.secondary).padding(.top, 2)
                        }
                    }.buttonStyle(.plain)
                    HStack(spacing: 10) {
                        familyLink("Календар", "calendar", OrbitCalendarView())
                        familyLink("Пам’ять", "brain.head.profile", MemoryCenterView())
                    }
                    Orbit3Card(tint: .secondary) {
                        Label("Приватність за замовчуванням", systemImage: "lock.shield.fill").font(.subheadline.weight(.semibold))
                        Text("Особисті дані показуються лише в межах авторизованого профілю та сімейного доступу.")
                            .font(.caption).foregroundStyle(.secondary).padding(.top, 3)
                    }
                }
                .padding(16)
            }
            .background(Orbit3Theme.canvas.ignoresSafeArea())
            .navigationTitle("Сім’я")
            .navigationBarTitleDisplayMode(.inline)
            .task { await load() }
            .refreshable { await load() }
            .alert("Сімейні дані недоступні", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("Гаразд") { errorMessage = nil }
            } message: { Text(errorMessage ?? "Спробуйте оновити ще раз.") }
        }
    }

    private func familyLink<Destination: View>(_ title: String, _ icon: String, _ destination: Destination) -> some View {
        NavigationLink { destination } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon).font(.title3).foregroundStyle(.purple)
                Text(title).font(.footnote.weight(.semibold)).foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
            .padding(13)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func initials(_ name: String) -> String { String(name.split(separator: " ").prefix(2).compactMap(\.first)).uppercased() }

    private func load() async {
        isLoading = true; defer { isLoading = false }
        do {
            async let loadedProfiles = MainProductAPI.shared.familyProfiles()
            async let loadedMessages = MainProductAPI.shared.familyMessages(limit: 3)
            profiles = try await loadedProfiles
            messages = try await loadedMessages
        } catch {
            errorMessage = "Не вдалося завантажити сімейний простір."
        }
    }
}

#Preview("Main Orbit 3 · Home") {
    MainOrbit3HomeView(open: { _ in })
        .environmentObject(OrbitAuthentication())
}

#Preview("Main Orbit 3 · Family") {
    MainOrbit3FamilyView()
}

#Preview("Main Orbit 3 · School") {
    SchoolHubView()
}

#Preview("Main Orbit 3 · School inbox") {
    SchoolInboxView()
}

#Preview("Main Orbit 3 · School detail") {
    SchoolDetailLoaderView(itemID: "preview")
}

#Preview("Main Orbit 3 · Orbit chat") {
    OrbitChatsView()
}

#Preview("Main Orbit 3 · Calendar") {
    OrbitCalendarView()
}
