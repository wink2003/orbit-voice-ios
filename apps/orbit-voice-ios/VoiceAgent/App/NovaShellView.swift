import SwiftUI

/// The Nova dock is a presentation shell, not a second navigation system.
/// Existing destination views retain their stores and detail routes.
struct NovaShellView: View {
    @Binding var selection: OrbitMainTab
    @State private var dockTopY: CGFloat = .infinity

    var body: some View {
        destination
            .safeAreaInset(edge: .bottom, spacing: 0) {
                NovaDock(selection: $selection)
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { dockTopY = $0 }
            }
            .environment(\.novaDockTopY, dockTopY)
            .onReceive(NotificationCenter.default.publisher(for: .orbitSchoolNotificationTapped)) { _ in
                selection = .school
            }
    }

    @ViewBuilder
    private var destination: some View {
        switch selection {
        case .home, .today:
            OrbitTodayView(open: select, displayName: nil)
        case .school:
            SchoolHubView()
        case .orbit, .chats:
            OrbitChatsView()
        case .family, .more:
            MainOrbit3FamilyView()
        case .calendar:
            OrbitCalendarView()
        }
    }

    private func select(_ tab: OrbitMainTab) {
        selection = tab == .today ? .home : tab
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
                    .foregroundStyle(selection == item ? NovaTodayTokens.indigo : .secondary)
                    .background {
                        if selection == item {
                            Capsule(style: .continuous).fill(NovaTodayTokens.indigo.opacity(0.12))
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
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Rectangle().fill(NovaTodayTokens.indigo.opacity(0.10)).frame(height: 1) }
    }
}

private struct NovaDockTopYKey: EnvironmentKey { static let defaultValue: CGFloat = .infinity }

extension EnvironmentValues {
    /// Top edge of the Nova dock in global coordinates; `.infinity` when no dock is shown.
    var novaDockTopY: CGFloat {
        get { self[NovaDockTopYKey.self] }
        set { self[NovaDockTopYKey.self] = newValue }
    }
}
