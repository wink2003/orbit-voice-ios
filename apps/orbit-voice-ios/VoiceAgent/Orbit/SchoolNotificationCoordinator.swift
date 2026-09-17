import Foundation
import UserNotifications

enum SchoolNotificationPermission: Equatable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case unavailable

    var canSchedule: Bool { self == .authorized || self == .provisional }
}

final class SchoolNotificationCoordinator: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = SchoolNotificationCoordinator()
    private override init() { super.init(); UNUserNotificationCenter.current().delegate = self }

    func authorizationStatus() async -> SchoolNotificationPermission {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized: .authorized
        case .provisional: .provisional
        case .ephemeral: .authorized
        @unknown default: .unavailable
        }
    }

    func requestAuthorization() async -> SchoolNotificationPermission {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        return await authorizationStatus()
    }

    func schedule(newItemCount: Int, itemIDs: [String]) async {
        guard newItemCount > 0 else { return }
        guard (await authorizationStatus()).canSchedule else { return }
        let content = UNMutableNotificationContent()
        content.title = "Нове зі школи"
        content.body = newItemCount == 1 ? "Новий матеріал" : "\(newItemCount) нових матеріалів"
        content.sound = .default
        content.userInfo = itemIDs.count == 1 ? ["schoolItemID": itemIDs[0]] : ["schoolInbox": true]
        let request = UNNotificationRequest(identifier: "orbit-school-\(UUID().uuidString)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    func scheduleDiagnostic() async -> Bool {
        guard (await authorizationStatus()).canSchedule else { return false }
        let content = UNMutableNotificationContent()
        content.title = "Orbit"
        content.body = "Тестове сповіщення зі школи"
        content.sound = .default
        content.userInfo = ["schoolInbox": true, "schoolDiagnostic": true]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(identifier: "orbit-school-diagnostic-\(UUID().uuidString)", content: content, trigger: trigger)
        do {
            try await UNUserNotificationCenter.current().add(request)
            return true
        } catch {
            return false
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound, .badge] }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        NotificationCenter.default.post(name: .orbitSchoolNotificationTapped, object: nil, userInfo: response.notification.request.content.userInfo)
    }
}

extension Notification.Name { static let orbitSchoolNotificationTapped = Notification.Name("orbit.school.notification.tapped") }
