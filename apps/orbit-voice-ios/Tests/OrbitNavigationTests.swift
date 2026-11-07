import Foundation

@main
struct OrbitNavigationTests {
    static func main() {
        precondition(OrbitNavigation.visibleTabs().map(\.title) == ["Головна", "Orbit", "Школа", "Інше"], "four daily destinations in production order")
        precondition(OrbitNavigation.visibleTabs().count == 4, "four primary destinations")
        precondition(OrbitNavigation.defaultTab == .home, "default tab is Home")
        precondition(OrbitCalendarRouteOrigin.more.showsBackControl, "Calendar opened from More has a Back control")
        precondition(!OrbitCalendarRouteOrigin.root.showsBackControl, "Calendar at a root tab has no redundant Back control")
        precondition(!OrbitNavigation.moreDestinations(isOwner: false).contains(.admin), "admin hidden for non-owner")
        precondition(OrbitNavigation.moreDestinations(isOwner: true).contains(.admin), "admin shown for owner")
        precondition(Set(OrbitNavigation.moreDestinations(isOwner: true)) == Set(OrbitMoreDestination.allCases), "owner More routes remain complete and unique")
        precondition(OrbitNavigation.moreDestinations(isOwner: false).map(\.title) == ["Календар", "Сім’я", "Контакти", "Інтеграції", "Налаштування", "Пам’ять", "Підключення календарів"], "non-owner More entries")
        precondition(OrbitNavigation.moreDestinations(isOwner: false).map(\.routeOwner) == ["OrbitCalendarView", "FamilyHubView", "OrbitContactsView", "OrbitToolsView", "OrbitSettingsView", "MemoryCenterView", "CalendarSettingsView"], "existing More route owners")
        precondition(OrbitNavigation.moreDestinations(isOwner: true).contains { $0 == .admin && $0.routeOwner == "OrbitDashboardView" }, "admin route owner")
        precondition(OrbitNavigation.tab(forSchoolNotification: true, current: .chats) == .school, "notification selects school")
        precondition(OrbitNavigation.tab(forSchoolNotification: false, current: .chats) == .chats, "no change without notification")
        precondition(!OrbitChatNavigationPolicy.opensExplicitConversation(contactPrompt: nil), "ordinary Orbit tab entry stays on the list")
        precondition(OrbitChatNavigationPolicy.opensExplicitConversation(contactPrompt: "Напиши родині: "), "explicit prompt may open a conversation")
        precondition(OrbitRootNavigationPolicy.action(selected: .home, requested: .school, hasUnsavedInput: false) == .switchTo(.school), "other tab opens its root")
        precondition(OrbitRootNavigationPolicy.action(selected: .school, requested: .school, hasUnsavedInput: false) == .resetRoot, "active tab returns to root")
        precondition(OrbitRootNavigationPolicy.action(selected: .today, requested: .home, hasUnsavedInput: false) == .resetRoot, "legacy today equals home")
        precondition(OrbitRootNavigationPolicy.action(selected: .chats, requested: .orbit, hasUnsavedInput: false) == .resetRoot, "legacy chats equals orbit")
        precondition(OrbitRootNavigationPolicy.action(selected: .school, requested: .more, hasUnsavedInput: true) == .confirmDiscard(.more), "unsaved input asks first")
        precondition(OrbitRootNavigationPolicy.action(selected: .school, requested: .school, hasUnsavedInput: true) == .confirmDiscard(.school), "reselect with unsaved input asks first")
        precondition(OrbitNavigation.visibleTabs().allSatisfy { OrbitRootNavigationPolicy.canonical($0) == $0 }, "every dock tab is canonical")

        precondition(abs(Routes05HeadingMetrics.points(Routes05HeadingMetrics.largeTitlePoints) - 27.2) < 0.0001, "headings are 20% smaller than largeTitle")
        precondition(Routes05HeadingMetrics.singleLine("Справи.\nПо черзі.") == "Справи. По черзі.", "manual line break becomes one line")
        precondition(Routes05HeadingMetrics.singleLine("  Вхідні\nзі школи.\n") == "Вхідні зі школи.", "outer whitespace removed")
        precondition(Routes05HeadingMetrics.singleLine("Elternbrief: Klassenfahrt") == "Elternbrief: Klassenfahrt", "single line unchanged")
        print("OrbitNavigationTests passed")
    }
}
