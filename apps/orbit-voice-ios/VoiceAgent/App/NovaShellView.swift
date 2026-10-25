import SwiftUI

/// The Nova dock is a presentation shell, not a second navigation system.
/// Existing destination views retain their stores and detail routes.
struct NovaShellView: View {
    @Binding var selection: OrbitMainTab
    #if DEBUG
    private let debugFixture: Routes05DebugScreen?
    init(selection: Binding<OrbitMainTab>, debugFixture: Routes05DebugScreen? = nil) {
        _selection = selection
        self.debugFixture = debugFixture
    }
    #endif
    @State private var dockTopY: CGFloat = .infinity
    @State private var dockHeight: CGFloat = 0
    @State private var dockVisible = true

    var body: some View {
        destination
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if dockVisible {
                    NovaDock(selection: $selection)
                        .onGeometryChange(for: DockMetrics.self) { proxy in
                            DockMetrics(top: proxy.frame(in: .global).minY, height: proxy.size.height)
                        } action: { metrics in
                            dockTopY = metrics.top
                            dockHeight = metrics.height
                        }
                    }
            }
            .environment(\.novaDockTopY, dockTopY)
            .environment(\.novaDockHeight, dockHeight)
            .environment(\.novaDockVisible, $dockVisible)
            .onReceive(NotificationCenter.default.publisher(for: .orbitSchoolNotificationTapped)) { _ in
                selection = .school
            }
    }

    @ViewBuilder
    private var destination: some View {
        #if DEBUG
        if let debugFixture {
            switch debugFixture {
            case .today: OrbitTodayView(open: select, displayName: "Олена", fixture: Routes05DebugFixtures.today)
            case .orbit: OrbitChatsView(fixture: Routes05DebugFixtures.chats)
            case .school: SchoolHubView(fixture: Routes05DebugFixtures.school)
            case .family: MainOrbit3FamilyView(fixture: Routes05DebugFixtures.family)
            case .familyMenu: MainOrbit3FamilyView(fixture: Routes05DebugFixtures.family, initialShowingMore: true)
            case .conversation: OrbitChatsView(fixture: Routes05DebugFixtures.chats, debugConversation: true)
            case .inbox: SchoolHubView(fixture: Routes05DebugFixtures.school, initialDebugRoute: "inbox")
            case .letter: SchoolHubView(fixture: Routes05DebugFixtures.school, initialDebugRoute: "letter")
            case .tasks: SchoolHubView(fixture: Routes05DebugFixtures.school, initialDebugRoute: "tasks")
            case .timetable: SchoolHubView(fixture: Routes05DebugFixtures.school, initialDebugRoute: "timetable")
            case .exams: SchoolHubView(fixture: Routes05DebugFixtures.school, initialDebugRoute: "exams")
            case .brain: SchoolHubView(fixture: Routes05DebugFixtures.school, initialDebugRoute: "brain")
            case .calendar: Routes05SystemRouteView(routeID: "calendar")
            case .schoolCalendar: SchoolHubView(fixture: Routes05DebugFixtures.school, initialDebugRoute: "calendar")
            case .search: SchoolHubView(fixture: Routes05DebugFixtures.school, initialDebugRoute: "search")
            case .timeline: SchoolHubView(fixture: Routes05DebugFixtures.school, initialDebugRoute: "timeline")
            case .briefing: SchoolHubView(fixture: Routes05DebugFixtures.school, initialDebugRoute: "briefing")
            case .notes: SchoolHubView(fixture: Routes05DebugFixtures.school, initialDebugRoute: "notes")
            case .history: SchoolHubView(fixture: Routes05DebugFixtures.school, initialDebugRoute: "history")
            case .contacts: Routes05SystemRouteView(routeID: "contacts")
            case .memory: Routes05SystemRouteView(routeID: "memory")
            case .voice: Routes05SystemRouteView(routeID: "voice")
            case .familyChat: Routes05SystemRouteView(routeID: "familychat")
            case .settings: Routes05SystemRouteView(routeID: "settings")
            case .integrations: Routes05SystemRouteView(routeID: "integrations")
            case .memoryDetail: Routes05SystemRouteView(routeID: "memorydetail")
            case .contactDetail: Routes05SystemRouteView(routeID: "contactdetail")
            case .actionConfirm: Routes05SystemRouteView(routeID: "actionconfirm")
            case .admin: Routes05SystemRouteView(routeID: "admin")
            case .profile: Routes05SystemRouteView(routeID: "profile")
            case .notifications: Routes05SystemRouteView(routeID: "notifications")
            case .memoryImports: Routes05SystemRouteView(routeID: "memoryimports")
            case .unknown: Routes05UnavailableView(routeID: "unknown")
            }
        } else {
            productionDestination
        }
        #else
        productionDestination
        #endif
    }

    @ViewBuilder
    private var productionDestination: some View {
        switch selection {
        case .home, .today: OrbitTodayView(open: select, displayName: nil)
        case .school: SchoolHubView()
        case .orbit, .chats: OrbitChatsView()
        case .family, .more: MainOrbit3FamilyView()
        case .calendar: OrbitCalendarView()
        }
    }

    private func select(_ tab: OrbitMainTab) {
        selection = tab == .today ? .home : tab
    }
}

private struct DockMetrics: Equatable, Sendable {
    let top: CGFloat
    let height: CGFloat

    nonisolated static func == (lhs: DockMetrics, rhs: DockMetrics) -> Bool {
        lhs.top == rhs.top && lhs.height == rhs.height
    }
}

private struct NovaDock: View {
    @Binding var selection: OrbitMainTab
    private let items: [OrbitMainTab] = [.home, .orbit, .school, .family]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(items) { item in
                Button { selection = item } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.systemImage)
                            .font(.subheadline.weight(.semibold))
                            .frame(height: 18)
                        Text(item == .home ? "Today" : item.title)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(selection == item ? Routes05Tokens.accentInk : Routes05Tokens.secondary)
                    .background {
                        if selection == item {
                            Rectangle().fill(Routes05Tokens.yellow)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item == .home ? "Today" : item.title)
                .accessibilityAddTraits(selection == item ? .isSelected : [])
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(Routes05Tokens.canvas)
        .overlay(alignment: .top) { Rectangle().fill(Routes05Tokens.ink).frame(height: 1.5) }
    }
}

private struct NovaDockTopYKey: EnvironmentKey { static let defaultValue: CGFloat = .infinity }
private struct NovaDockHeightKey: EnvironmentKey { static let defaultValue: CGFloat = 0 }
private struct NovaDockVisibleKey: EnvironmentKey { static let defaultValue: Binding<Bool> = .constant(true) }

struct NovaDockAwareScrollContent: ViewModifier {
    @Environment(\.novaDockHeight) private var dockHeight

    func body(content: Content) -> some View {
        content.contentMargins(.bottom, dockHeight + 12, for: .scrollContent)
    }
}

extension View {
    func novaDockAwareScrollContent() -> some View {
        modifier(NovaDockAwareScrollContent())
    }
}

extension EnvironmentValues {
    /// Top edge of the Nova dock in global coordinates; `.infinity` when no dock is shown.
    var novaDockTopY: CGFloat {
        get { self[NovaDockTopYKey.self] }
        set { self[NovaDockTopYKey.self] = newValue }
    }

    var novaDockHeight: CGFloat {
        get { self[NovaDockHeightKey.self] }
        set { self[NovaDockHeightKey.self] = newValue }
    }

    var novaDockVisible: Binding<Bool> {
        get { self[NovaDockVisibleKey.self] }
        set { self[NovaDockVisibleKey.self] = newValue }
    }
}
