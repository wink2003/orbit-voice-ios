import Foundation
import UserNotifications

final class SchoolNotificationCoordinator: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = SchoolNotificationCoordinator()
    private override init() { super.init(); UNUserNotificationCenter.current().delegate = self }

    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func schedule(newItemCount: Int, itemIDs: [String]) async {
        guard newItemCount > 0 else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let content = UNMutableNotificationContent()
        content.title = "Нове зі школи"
        content.body = newItemCount == 1 ? "Новий матеріал" : "(newItemCount) нових матеріалів"
        content.sound = .default
        content.userInfo = itemIDs.count == 1 ? ["schoolItemID": itemIDs[0]] : ["schoolInbox": true]
        let request = UNNotificationRequest(identifier: "orbit-school-\(UUID().uuidString)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound, .badge] }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        NotificationCenter.default.post(name: .orbitSchoolNotificationTapped, object: nil, userInfo: response.notification.request.content.userInfo)
    }
}

extension Notification.Name { static let orbitSchoolNotificationTapped = Notification.Name("orbit.school.notification.tapped") }
