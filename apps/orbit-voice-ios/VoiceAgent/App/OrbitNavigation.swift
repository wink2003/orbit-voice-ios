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
    /// Pushed from another screen (Family route); needs its own Back like `.more`.
    case pushed

    var showsBackControl: Bool { self != .root }
}

nonisolated enum OrbitChatNavigationPolicy {
    static func opensExplicitConversation(contactPrompt: String?) -> Bool {
        contactPrompt != nil
    }
}

/// What a tap on a main-menu (dock) destination should do. The dock is visible
/// above nested screens, so every tap must resolve to a ROOT destination:
/// a different tab opens its root, the active tab returns to its own root.
/// When a nested screen holds unsaved input the user is asked first.
nonisolated enum OrbitRootNavigationPolicy {
    enum Action: Equatable {
        case switchTo(OrbitMainTab)
        case resetRoot
        case confirmDiscard(OrbitMainTab)
    }

    /// Legacy tab values map onto the visible dock destinations.
    static func canonical(_ tab: OrbitMainTab) -> OrbitMainTab {
        switch tab {
        case .today: .home
        case .chats: .orbit
        default: tab
        }
    }

    static func action(selected: OrbitMainTab, requested: OrbitMainTab, hasUnsavedInput: Bool) -> Action {
        let target = canonical(requested)
        if hasUnsavedInput { return .confirmDiscard(target) }
        return canonical(selected) == target ? .resetRoot : .switchTo(target)
    }
}

/// Native interactive-pop is allowed only below a root, outside a running
/// transition and while no screen holds unsaved input.
nonisolated enum Routes05SwipeBackRule {
    static func canBegin(stackDepth: Int, isTransitioning: Bool, hasUnsavedInput: Bool) -> Bool {
        stackDepth > 1 && !isTransitioning && !hasUnsavedInput
    }
}

/// ROUTES 05 screen headings are 80 % of the previous `largeTitle` style and
/// always occupy a single line; wrapping is replaced by tail truncation.
nonisolated enum Routes05HeadingMetrics {
    static let scale = 0.8
    static let largeTitlePoints = 34.0

    static func points(_ basePoints: Double) -> Double { basePoints * scale }

    /// Authored headings use explicit line breaks ("Справи.\nПо черзі."); a
    /// one-line heading must show the whole phrase instead of its first line.
    static func singleLine(_ title: String) -> String {
        title.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

/// Destination of the Today header badge. Kept as data so the routing is testable.
nonisolated enum OrbitTodayHeroRoute {
    static let destination: OrbitMainTab = .calendar
}
