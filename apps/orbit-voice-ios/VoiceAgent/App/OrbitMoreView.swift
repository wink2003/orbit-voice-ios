import SwiftUI

struct OrbitMoreView: View {
    @EnvironmentObject private var authentication: OrbitAuthentication

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label(authentication.displayName ?? "Активний профіль", systemImage: "person.crop.circle")
                        .font(.headline)
                        .frame(minHeight: OrbitSpacing.minTarget)
                        .accessibilityLabel("Профіль: \(authentication.displayName ?? "активний профіль")")
                }
                Section {
                    ForEach(OrbitNavigation.moreDestinations(isOwner: authentication.canViewServerOverview)) { destination in
                        NavigationLink { screen(for: destination) } label: { row(for: destination) }
                            .frame(minHeight: OrbitSpacing.minTarget)
                    }
                }
                Section("Календарі") {
                    NavigationLink { CalendarSettingsView() } label: { Label("Підключення календарів", systemImage: "calendar.badge.clock") }
                }
                Section {
                    Text("Main Orbit — сімейний AI-помічник. Orbit Mini залишається окремим клієнтом для голосу без рук.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Ще")
        }
    }

    @ViewBuilder private func screen(for destination: OrbitMoreDestination) -> some View {
        switch destination {
        case .memory: MemoryCenterView()
        case .family: FamilyHubView()
        case .contacts: OrbitContactsView()
        case .settings: OrbitSettingsView()
        case .admin: OrbitDashboardView(isSelected: true)
        }
    }

    @ViewBuilder private func row(for destination: OrbitMoreDestination) -> some View {
        switch destination {
        case .memory: Label("Пам’ять", systemImage: "brain.head.profile")
        case .family: Label("Сім’я", systemImage: "person.3")
        case .contacts: Label("Контакти", systemImage: "person.crop.circle.badge.plus")
        case .settings: Label("Налаштування", systemImage: "gearshape")
        case .admin: Label("Admin · сервер", systemImage: "server.rack")
        }
    }
}
