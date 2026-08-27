import Foundation
import SwiftUI

struct OrbitDashboardView: View {
    @State private var state = DashboardState()
    @State private var isLoading = true
    @State private var lastUpdated: Date?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    header
                    nowSection
                    familySection
                    activitySection
                    memorySection
                    integrationsSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .safeAreaPadding(.bottom, 16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await load() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Оновити дашборд")
                    .disabled(isLoading)
                }
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(greetingWithProfile)
                .font(.title2.weight(.bold))
            if let lastUpdated {
                Text("Оновлено \(dashboardTime(lastUpdated))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var nowSection: some View {
        DashboardSection(title: "Зараз", subtitle: "Те, що потребує вашої уваги") {
            if isLoading && !state.hasContent {
                DashboardSkeleton(rows: 2)
            } else if state.nowItems.isEmpty {
                calmEmpty("Наразі все спокійно", detail: "Orbit не бачить дій, які очікують на вас.", icon: "checkmark.circle")
            } else {
                ForEach(state.nowItems) { item in
                    DashboardNavigationRow(destination: item.destination) {
                        Label(item.title, systemImage: item.icon)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(item.tint)
                        Text(item.detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
    }

    @ViewBuilder private var familySection: some View {
        DashboardSection(title: "Сім’я", subtitle: "Контекст родини, доступний цьому профілю") {
            if isLoading && state.profiles.isEmpty {
                DashboardSkeleton(rows: 1)
            } else if state.profiles.isEmpty {
                calmEmpty("Профілі ще не доступні", detail: "Коли Orbit отримає сімейний контекст, він з’явиться тут.", icon: "person.3")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(state.profiles) { profile in
                            NavigationLink {
                                FamilyHubView()
                            } label: {
                                familyCard(profile)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func familyCard(_ profile: OrbitFamilyProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(initials(profile.displayName))
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(profile.isMinor ? Color.teal : Color.indigo, in: Circle())
            Text(profile.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(profileContext(profile))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(width: 154, alignment: .leading)
        .frame(minHeight: 132, alignment: .leading)
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Відкрити сімейний контекст")
    }

    @ViewBuilder private var activitySection: some View {
        DashboardSection(title: "Остання активність", subtitle: "Події з доступних розмов, пам’яті та родини") {
            if isLoading && state.activities.isEmpty {
                DashboardSkeleton(rows: 3)
            } else if state.activities.isEmpty {
                calmEmpty("Поки що немає активності", detail: "Коли Orbit отримає нові події, вони з’являться в цій стрічці.", icon: "clock.arrow.circlepath")
            } else {
                ForEach(state.activities.prefix(6)) { activity in
                    DashboardNavigationRow(destination: activity.destination) {
                        HStack(alignment: .top, spacing: 11) {
                            Image(systemName: activity.icon)
                                .foregroundStyle(activity.tint)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(activity.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                    Spacer(minLength: 8)
                                    Text(dashboardRelativeTime(activity.date)).font(.caption2).foregroundStyle(.tertiary)
                                }
                                Text(activity.detail).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                }
            }
        }
    }

    private var memorySection: some View {
        DashboardSection(title: "Пам’ять", subtitle: "Актуальний контекст Orbit") {
            if isLoading && state.memoryLoadState != .loaded {
                DashboardSkeleton(rows: 2)
            } else if state.memoryLoadState == .failed {
                NavigationLink { MemoryCenterView() } label: {
                    calmEmpty("Пам’ять тимчасово недоступна", detail: "Відкрийте Центр пам’яті або повторіть оновлення пізніше.", icon: "exclamationmark.triangle")
                }
                .buttonStyle(.plain)
            } else if state.memories.isEmpty {
                NavigationLink { MemoryCenterView() } label: {
                    calmEmpty("Пам’ять ще порожня", detail: "Відкрийте Центр пам’яті, щоб переглянути або знайти контекст.", icon: "brain.head.profile")
                }
                .buttonStyle(.plain)
            } else {
                ForEach(state.memories.prefix(3)) { memory in
                    NavigationLink { MemoryCenterView() } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(memory.subjectName).font(.caption.weight(.semibold)).foregroundStyle(.tint)
                            Text(memory.valueText).font(.subheadline).foregroundStyle(.primary).lineLimit(2)
                            Text(memoryCategory(memory)).font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
                NavigationLink { MemoryCenterView() } label: {
                    Label("Відкрити Центр пам’яті", systemImage: "arrow.right")
                        .font(.footnote.weight(.semibold))
                }
            }
        }
    }

    @ViewBuilder private var integrationsSection: some View {
        DashboardSection(title: "Інтеграції", subtitle: "Лише реальний поточний стан") {
            if isLoading && state.integration == nil && state.calendarConnections == nil {
                DashboardSkeleton(rows: 2)
            } else {
                if let integration = state.integration {
                    NavigationLink { OrbitToolsView() } label: {
                        integrationRow(title: dashboardWhatsAppStatus(integration.whatsapp), icon: "message.fill", tint: dashboardWhatsAppTint(integration.whatsapp))
                    }
                    .buttonStyle(.plain)
                }
                if let connections = state.calendarConnections {
                    NavigationLink { OrbitCalendarView() } label: {
                        integrationRow(title: calendarConnectionText(connections), icon: "calendar", tint: connections.contains(where: { $0.status != "verified" }) ? .orange : .blue)
                    }
                    .buttonStyle(.plain)
                }
                if state.integration == nil && state.calendarConnections == nil {
                    calmEmpty("Стан інтеграцій недоступний", detail: "Відкрийте Інструменти, щоб повторити перевірку.", icon: "exclamationmark.triangle")
                }
            }
        }
    }

    private func integrationRow(title: String, icon: String, tint: Color) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 5)
    }

    private func calmEmpty(_ title: String, detail: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                Text(detail).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12: return "Доброго ранку"
        case 12..<18: return "Добрий день"
        default: return "Добрий вечір"
        }
    }

    private var greetingWithProfile: String {
        guard let name = state.profile?.displayName.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return greeting }
        return "\(greeting), \(name)"
    }

    private func dashboardTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func dashboardRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "uk_UA")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: .now)
    }

    private func profileContext(_ profile: OrbitFamilyProfile) -> String {
        if let event = state.events.first(where: { $0.ownerPersonId == profile.personId && $0.endsAt >= .now }) {
            return event.title
        }
        if state.memories.contains(where: { $0.subjectName.localizedCaseInsensitiveContains(profile.displayName) }) {
            return "Є актуальна пам’ять"
        }
        return profile.isMinor ? "Профіль дитини" : "Член родини"
    }

    private func initials(_ name: String) -> String {
        String(name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()).uppercased()
    }

    private func memoryCategory(_ memory: OrbitMemoryAssertion) -> String {
        memory.predicate.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func calendarConnectionText(_ connections: [OrbitCalendarConnection]) -> String {
        guard !connections.isEmpty else { return "Календар — не підключено" }
        let failed = connections.filter { $0.status != "verified" }.count
        return failed == 0 ? "Календар — підключено" : "Календар — потребує уваги"
    }

    private func load() async {
        isLoading = true
        async let chatsResult = capture { try await OrbitChatAPI.shared.chats() }
        async let profilesResult = capture { try await MainProductAPI.shared.familyProfiles() }
        async let familyMessagesResult = capture { try await MainProductAPI.shared.familyMessages(limit: 8) }
        async let eventsResult = capture { try await MainProductAPI.shared.calendarEvents() }
        async let memoryResult = capture { try await MainProductAPI.shared.memoryCenter(limit: 8) }
        async let importsResult = capture { try await MainProductAPI.shared.memoryImports(limit: 5) }
        async let integrationResult = capture { try await MainProductAPI.shared.integrationStatus() }
        async let calendarConnectionsResult = capture { try await MainProductAPI.shared.calendarConnections() }

        var next = DashboardState()
        if case let .success(value) = await profilesResult { next.profiles = value }
        if case let .success(value) = await familyMessagesResult { next.familyMessages = value }
        if case let .success(value) = await eventsResult { next.events = value }
        if case let .success(value) = await memoryResult {
            next.memories = value.assertions
            next.memoryLoadState = .loaded
        } else {
            next.memoryLoadState = .failed
        }
        if case let .success(value) = await importsResult { next.imports = value }
        if case let .success(value) = await integrationResult { next.integration = value }
        if case let .success(value) = await calendarConnectionsResult { next.calendarConnections = value }

        if case let .success(value) = await chatsResult {
            next.profile = value.profile
            next.chats = value.chats
            let recentChats = value.chats.compactMap { chat -> DashboardActivity? in
                guard let date = chat.updatedAt, let message = chat.lastMessage, !message.isEmpty else { return nil }
                return DashboardActivity(date: date, title: chat.title, detail: message, icon: chat.kind == "family" ? "person.3.fill" : "message.fill", tint: .indigo, destination: .chat)
            }
            next.activities.append(contentsOf: recentChats)
            for chat in value.chats {
                let result = await capture { try await OrbitChatAPI.shared.messages(in: chat, limit: 12) }
                if case let .success(messages) = result {
                    next.pendingActions.append(contentsOf: messages.compactMap(DashboardPendingAction.init))
                }
            }
        }

        next.activities.append(contentsOf: next.familyMessages.map {
            DashboardActivity(date: $0.createdAt, title: $0.senderDisplayName, detail: $0.content, icon: "person.3.fill", tint: .teal, destination: .family)
        })
        next.activities.append(contentsOf: next.memories.compactMap { memory in
            guard let date = memory.recordedAt ?? memory.observedAt else { return nil }
            return DashboardActivity(date: date, title: "Пам’ять", detail: "\(memory.subjectName) · \(memoryCategory(memory))", icon: "brain.head.profile", tint: .purple, destination: .memory)
        })
        next.activities.append(contentsOf: next.imports.map {
            DashboardActivity(date: $0.completedAt ?? $0.startedAt, title: "Імпорт пам’яті", detail: dashboardImportSummary($0), icon: "tray.full", tint: .orange, destination: .memory)
        })
        next.activities.sort { $0.date > $1.date }
        next.pendingActions = Array(Dictionary(grouping: next.pendingActions, by: \.id).compactMap { $0.value.first })
        state = next
        lastUpdated = .now
        isLoading = false
    }

    private func capture<T>(_ operation: @escaping () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await operation()) }
        catch { return .failure(error) }
    }
}

private struct DashboardSection<Content: View>: View {
    let title: String
    let subtitle: String?
    let content: Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title; self.subtitle = subtitle; self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3.weight(.bold))
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            VStack(alignment: .leading, spacing: 10) { content }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

private struct DashboardSkeleton: View {
    let rows: Int
    var body: some View {
        VStack(spacing: 10) {
            ForEach(0..<rows, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.14)).frame(height: 16)
            }
        }
        .redacted(reason: .placeholder)
        .accessibilityLabel("Завантаження")
    }
}

private enum DashboardDestination { case chat, family, memory }

private struct DashboardNavigationRow<Content: View>: View {
    let destination: DashboardDestination
    let content: Content

    init(destination: DashboardDestination, @ViewBuilder content: () -> Content) {
        self.destination = destination
        self.content = content()
    }
    var body: some View {
        Group {
            switch destination {
            case .chat: NavigationLink { OrbitChatsView() } label: { rowContent }
            case .family: NavigationLink { FamilyHubView() } label: { rowContent }
            case .memory: NavigationLink { MemoryCenterView() } label: { rowContent }
            }
        }
        .buttonStyle(.plain)
    }
    private var rowContent: some View { content.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 3) }
}

private struct DashboardState {
    var profile: OrbitProfile?
    var profiles: [OrbitFamilyProfile] = []
    var chats: [OrbitConversation] = []
    var familyMessages: [OrbitFamilyMessage] = []
    var events: [OrbitCalendarEvent] = []
    var memories: [OrbitMemoryAssertion] = []
    var memoryLoadState: DashboardLoadState = .idle
    var imports: [OrbitMemoryImportBatch] = []
    var integration: OrbitIntegrationStatus?
    var calendarConnections: [OrbitCalendarConnection]?
    var activities: [DashboardActivity] = []
    var pendingActions: [DashboardPendingAction] = []

    var hasContent: Bool { !profiles.isEmpty || !chats.isEmpty || !familyMessages.isEmpty || !events.isEmpty || !memories.isEmpty }

    var nowItems: [DashboardNowItem] {
        var items = pendingActions.map {
            DashboardNowItem(
                id: "action-\($0.id)",
                title: "Потрібне підтвердження",
                detail: "\($0.channelTitle) → \($0.recipient)\n«\($0.message)»",
                icon: $0.channelIcon,
                tint: .orange,
                destination: .chat
            )
        }
        if let event = events.filter({ $0.startsAt >= .now }).sorted(by: { $0.startsAt < $1.startsAt }).first {
            items.append(DashboardNowItem(id: "event-\(event.id)", title: event.title, detail: dashboardEventTime(event), icon: "calendar", tint: .blue, destination: .family))
        }
        if let batch = imports.first(where: { $0.needsReview > 0 || ($0.status != "completed" && $0.status != "failed") }) {
            items.append(DashboardNowItem(id: "import-\(batch.id)", title: "Імпорт пам’яті", detail: dashboardImportSummary(batch), icon: "tray.full", tint: .orange, destination: .memory))
        }
        return items
    }
}

private enum DashboardLoadState: Equatable { case idle, loaded, failed }

private struct DashboardNowItem: Identifiable {
    let id: String; let title: String; let detail: String; let icon: String; let tint: Color; let destination: DashboardDestination
}

private struct DashboardActivity: Identifiable {
    let date: Date; let title: String; let detail: String; let icon: String; let tint: Color; let destination: DashboardDestination
    var id: String { "\(date.timeIntervalSince1970)-\(title)-\(detail)" }
}

private struct DashboardPendingAction: Identifiable {
    let id: String; let recipient: String; let message: String; let channel: String?
    init?(_ message: OrbitChatMessage) {
        guard let confirmation = message.actionConfirmation, confirmation.status == "proposed", confirmation.needsConfirmation else { return nil }
        id = confirmation.actionId; recipient = confirmation.recipient; self.message = confirmation.message; channel = confirmation.channel
    }
    var channelTitle: String { channel == "telegram" ? "Telegram" : channel == "whatsapp" ? "WhatsApp" : "Дія Orbit" }
    var channelIcon: String { channel == "telegram" ? "paperplane.fill" : channel == "whatsapp" ? "message.fill" : "checkmark.shield" }
}

private func dashboardWhatsAppStatus(_ status: OrbitWhatsAppIntegrationStatus) -> String {
    if status.state == "linked" || status.outboundProviderAccepted {
        return "WhatsApp — підключено, надсилання потребує підтвердження"
    }
    if status.inboundVerified { return "WhatsApp — вхідні повідомлення перевірені" }
    switch status.state {
    case "configured": return "WhatsApp — налаштовано"
    case "link_required": return "WhatsApp — потрібно підключити пристрій"
    case "connecting": return "WhatsApp — підключається"
    case "unavailable": return "WhatsApp — тимчасово недоступний"
    default: return "WhatsApp — потребує налаштування"
    }
}

private func dashboardWhatsAppTint(_ status: OrbitWhatsAppIntegrationStatus) -> Color {
    if status.state == "linked" || status.outboundProviderAccepted || status.inboundVerified { return .green }
    switch status.state {
    case "configured": return .blue
    case "not_configured": return .secondary
    default: return .orange
    }
}

private func dashboardImportSummary(_ batch: OrbitMemoryImportBatch) -> String {
    if batch.needsReview > 0 { return "Потребує перевірки: \(batch.needsReview)" }
    if batch.status == "completed" { return "Завершено · \(batch.operationsCreated) оновлень" }
    return "\(batch.phase.capitalized) · \(batch.conversations) розмов"
}

private func dashboardEventTime(_ event: OrbitCalendarEvent) -> String {
    if event.allDay { return event.startsAt.formatted(date: .abbreviated, time: .omitted) }
    return event.startsAt.formatted(date: .abbreviated, time: .shortened)
}
