import Foundation
import WidgetKit

// Main Orbit writes only authorized, minimized task snapshots. The widget has
// no network client, credentials, or task mutation path.
@MainActor
enum SchoolTasksWidgetPublisher {
    private static let suite = "group.net.opik.orbit.voice"
    private static let key = "school.tasks.widget.snapshot.v1"
    private static let kind = "orbit.school.tasks"

    static func publish(
        tasks: [SchoolHubTask],
        sourceDates: [String: Date],
        now: Date,
        verifiedCurrentScope: Bool,
        coverageComplete: Bool
    ) {
        guard verifiedCurrentScope else { clear(); return }
        let snapshot = SchoolTasksWidgetProjection.make(
            tasks: tasks, sourceDates: sourceDates, now: now,
            coverageComplete: coverageComplete)
        guard write(snapshot) else { clear(); return }
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
    }

    private static func write(_ snapshot: SchoolTasksWidgetSnapshot) -> Bool {
        guard let store = UserDefaults(suiteName: suite),
              let data = try? JSONEncoder().encode(snapshot) else {
            return false
        }
        store.set(data, forKey: key)
        return true
    }

    static func clear() {
        UserDefaults(suiteName: suite)?.removeObject(forKey: key)
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
    }

}
