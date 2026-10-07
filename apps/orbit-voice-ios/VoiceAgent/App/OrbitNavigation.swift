import Foundation

nonisolated enum OrbitMainTab: String, CaseIterable, Identifiable {
    case today, chats, school, calendar, more

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Сьогодні"
        case .chats: "Чати"
        case .school: "Школа"
        case .calendar: "Календар"
        case .more: "Ще"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "sun.max"
        case .chats: "message"
        case .school: "graduationcap"
        case .calendar: "calendar"
        case .more: "ellipsis.circle"
        }
    }
}

nonisolated enum OrbitMoreDestination: String, CaseIterable, Identifiable {
    case memory, family, contacts, settings, admin

    var id: String { rawValue }

    var title: String {
        switch self {
        case .memory: "Пам’ять"
        case .family: "Сім’я"
        case .contacts: "Контакти"
        case .settings: "Налаштування"
        case .admin: "Admin"
        }
    }
}

nonisolated enum OrbitNavigation {
    static let defaultTab: OrbitMainTab = .today

    // Always exactly five tabs, so UIKit never creates the system "More" controller.
    static func visibleTabs() -> [OrbitMainTab] { OrbitMainTab.allCases }

    // The server stays authoritative; this only hides an entry the backend would reject.
    static func moreDestinations(isOwner: Bool) -> [OrbitMoreDestination] {
        OrbitMoreDestination.allCases.filter { $0 != .admin || isOwner }
    }

    static func tab(forSchoolNotification: Bool, current: OrbitMainTab) -> OrbitMainTab {
        forSchoolNotification ? .school : current
    }
}
