import Foundation

nonisolated enum OrbitMainTab: String, CaseIterable, Identifiable {
    case home, orbit, family
    // Legacy values remain source-compatible for older contextual views and
    // tests. They are no longer part of the visible 3.0 shell.
    case today, chats, school, calendar, more

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Головна"
        case .orbit: "Orbit"
        case .family: "Сім’я"
        case .today: "Сьогодні"
        case .chats: "Чати"
        case .school: "Школа"
        case .calendar: "Календар"
        case .more: "Інше"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "sun.max.fill"
        case .orbit: "sparkles"
        case .family: "person.3.fill"
        case .today: "sun.max"
        case .chats: "message"
        case .school: "graduationcap"
        case .calendar: "calendar"
        case .more: "ellipsis.circle"
        }
    }
}

nonisolated enum OrbitMoreDestination: String, CaseIterable, Identifiable {
    case calendar, family, contacts, integrations, admin, settings, memory, calendarSettings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calendar: "Календар"
        case .family: "Сім’я"
        case .contacts: "Контакти"
        case .integrations: "Інтеграції"
        case .admin: "Адміністрування"
        case .settings: "Налаштування"
        case .memory: "Пам’ять"
        case .calendarSettings: "Підключення календарів"
        }
    }

    /// Stable source-level ownership contract for navigation regression tests.
    var routeOwner: String {
        switch self {
        case .calendar: "OrbitCalendarView"
        case .family: "FamilyHubView"
        case .contacts: "OrbitContactsView"
        case .integrations: "OrbitToolsView"
        case .admin: "OrbitDashboardView"
        case .settings: "OrbitSettingsView"
        case .memory: "MemoryCenterView"
        case .calendarSettings: "CalendarSettingsView"
        }
    }
}

nonisolated enum OrbitNavigation {
    static let defaultTab: OrbitMainTab = .home

    // Keep the primary shell compact so UIKit never creates the system "More" controller.
    static func visibleTabs() -> [OrbitMainTab] { [.home, .orbit, .school, .more] }

    // The server stays authoritative; this only hides an entry the backend would reject.
    static func moreDestinations(isOwner: Bool) -> [OrbitMoreDestination] {
        OrbitMoreDestination.allCases.filter { $0 != .admin || isOwner }
    }

    static func tab(forSchoolNotification: Bool, current: OrbitMainTab) -> OrbitMainTab {
        forSchoolNotification ? .school : current
    }
}

nonisolated enum OrbitCalendarRouteOrigin: Equatable {
    case root
    case more

    var showsBackControl: Bool { self == .more }
}

nonisolated enum OrbitChatNavigationPolicy {
    static func opensExplicitConversation(contactPrompt: String?) -> Bool {
        contactPrompt != nil
    }
}
