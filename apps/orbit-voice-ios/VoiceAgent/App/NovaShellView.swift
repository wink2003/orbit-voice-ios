import SwiftUI

/// The Nova dock is a presentation shell, not a second navigation system.
/// Existing destination views retain their stores and detail routes.
struct NovaShellView: View {
    @Binding var selection: OrbitMainTab

    var body: some View {
        destination
            .safeAreaInset(edge: .bottom, spacing: 0) {
                NovaDock(selection: $selection)
            }
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
    private let items: [OrbitMainTab] = [.home, .school, .orbit, .family]

    var body: some View {
        HStack(spacing: 4) {
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
                            Capsule(style: .continuous)
                                .fill(NovaTodayTokens.indigo.opacity(0.12))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item == .home ? "Today" : item.title)
                .accessibilityAddTraits(selection == item ? .isSelected : [])
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 7)
        .padding(.bottom, 7)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
