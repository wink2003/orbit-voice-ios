import Foundation

@main
struct OrbitNavigationTests {
    static func main() {
        precondition(OrbitNavigation.visibleTabs().map(\.title) == ["Сьогодні", "Чати", "Школа", "Календар", "Ще"], "five tabs in order")
        precondition(OrbitNavigation.visibleTabs().count == 5, "exactly five tabs, no system More")
        precondition(OrbitNavigation.defaultTab == .today, "default tab is Today")
        precondition(!OrbitNavigation.moreDestinations(isOwner: false).contains(.admin), "admin hidden for non-owner")
        precondition(OrbitNavigation.moreDestinations(isOwner: true).contains(.admin), "admin shown for owner")
        precondition(OrbitNavigation.moreDestinations(isOwner: false).map(\.title) == ["Пам’ять", "Сім’я", "Контакти", "Налаштування"], "more entries")
        precondition(OrbitNavigation.tab(forSchoolNotification: true, current: .chats) == .school, "notification selects school")
        precondition(OrbitNavigation.tab(forSchoolNotification: false, current: .chats) == .chats, "no change without notification")
        print("OrbitNavigationTests passed")
    }
}
