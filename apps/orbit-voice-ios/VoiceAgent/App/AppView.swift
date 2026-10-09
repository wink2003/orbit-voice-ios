import LiveKit
import SwiftUI

struct AppView: View {
    @EnvironmentObject private var authentication: OrbitAuthentication
    @Namespace private var namespace
    @AppStorage("orbit.appearance") private var appearance = "system"
    @State private var selectedTab = OrbitNavigation.defaultTab

    var body: some View {
        Group {
            if authentication.identityResolved {
                tabs
            } else {
                ProgressView("Завантаження Orbit…")
            }
        }
        .task { await authentication.refreshIdentity() }
    }

    // Main Orbit 3.0 keeps four daily destinations. Calendar, contacts, memory,
    // settings and server diagnostics remain contextual surfaces instead of
    // competing with the four jobs users return to every day.
    private var tabs: some View {
        TabView(selection: $selectedTab) {
            MainOrbit3HomeView(open: { selectedTab = $0 })
                .tabItem { Label(OrbitMainTab.home.title, systemImage: OrbitMainTab.home.systemImage) }
                .tag(OrbitMainTab.home)
            SchoolHubView()
                .tabItem { Label(OrbitMainTab.school.title, systemImage: OrbitMainTab.school.systemImage) }
                .tag(OrbitMainTab.school)
            OrbitChatsView()
                .tabItem { Label(OrbitMainTab.orbit.title, systemImage: OrbitMainTab.orbit.systemImage) }
                .tag(OrbitMainTab.orbit)
            MainOrbit3FamilyView()
                .tabItem { Label(OrbitMainTab.family.title, systemImage: OrbitMainTab.family.systemImage) }
                .tag(OrbitMainTab.family)
        }
        .environment(\.namespace, namespace)
        .preferredColorScheme(preferredColorScheme)
        .onReceive(NotificationCenter.default.publisher(for: .orbitSchoolNotificationTapped)) { _ in
            selectedTab = OrbitNavigation.tab(forSchoolNotification: true, current: selectedTab)
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch appearance {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }
}
