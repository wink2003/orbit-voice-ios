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

    // Exactly five tabs: UIKit never creates the system "More" controller, so each
    // tab owns a single NavigationStack. Voice is an explicit action inside Chats.
    private var tabs: some View {
        TabView(selection: $selectedTab) {
            OrbitTodayView(isSelected: selectedTab == .today) { selectedTab = $0 }
                .tabItem { Label(OrbitMainTab.today.title, systemImage: OrbitMainTab.today.systemImage) }
                .tag(OrbitMainTab.today)
            OrbitChatsView()
                .tabItem { Label(OrbitMainTab.chats.title, systemImage: OrbitMainTab.chats.systemImage) }
                .tag(OrbitMainTab.chats)
            SchoolInboxView()
                .tabItem { Label(OrbitMainTab.school.title, systemImage: OrbitMainTab.school.systemImage) }
                .tag(OrbitMainTab.school)
            OrbitCalendarView()
                .tabItem { Label(OrbitMainTab.calendar.title, systemImage: OrbitMainTab.calendar.systemImage) }
                .tag(OrbitMainTab.calendar)
            OrbitMoreView()
                .tabItem { Label(OrbitMainTab.more.title, systemImage: OrbitMainTab.more.systemImage) }
                .tag(OrbitMainTab.more)
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
