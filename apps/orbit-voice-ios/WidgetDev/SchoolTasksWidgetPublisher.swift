import Foundation
import WidgetKit

// Integrate with the existing SchoolHubStore lifecycle only after the Widget
// extension's shared App Group entitlement and identity isolation are verified.
// This file is deliberately outside the active app target until that check.
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
        guard let store = UserDefaults(suiteName: suite),
              let data = try? JSONEncoder().encode(snapshot) else {
            clear()
            return
        }
        store.set(data, forKey: key)
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
    }

    static func clear() {
        UserDefaults(suiteName: suite)?.removeObject(forKey: key)
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
    }
}
