import Foundation

@main
struct OrbitNavigationTests {
    static func main() {
        precondition(OrbitNavigation.visibleTabs().map(\.title) == ["Головна", "Школа", "Orbit", "Сім’я"], "four daily destinations in order")
        precondition(OrbitNavigation.visibleTabs().count == 4, "four primary destinations")
        precondition(OrbitNavigation.defaultTab == .home, "default tab is Home")
        precondition(!OrbitNavigation.moreDestinations(isOwner: false).contains(.admin), "admin hidden for non-owner")
        precondition(OrbitNavigation.moreDestinations(isOwner: true).contains(.admin), "admin shown for owner")
        precondition(OrbitNavigation.moreDestinations(isOwner: false).map(\.title) == ["Пам’ять", "Сім’я", "Контакти", "Налаштування"], "more entries")
        precondition(OrbitNavigation.tab(forSchoolNotification: true, current: .chats) == .school, "notification selects school")
        precondition(OrbitNavigation.tab(forSchoolNotification: false, current: .chats) == .chats, "no change without notification")
        print("OrbitNavigationTests passed")
    }
}
