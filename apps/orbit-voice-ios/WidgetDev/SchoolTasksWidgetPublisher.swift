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

    #if DEBUG
    /// Fixture-only signed App Group smoke. It contains no live school content.
    @discardableResult
    static func publishSmokeFixture(now: Date = .now) -> Bool {
        let snapshot = SchoolTasksWidgetSnapshot(
            schemaVersion: 1,
            generatedAt: now,
            weekStart: SchoolTasksWidgetSnapshot.schoolWeekStart(for: now),
            openCount: 3,
            overdue: [.init(id: "smoke-overdue", title: "TEST ONLY · Прострочена справа", effectiveDay: nil, completed: false)],
            thisWeek: [
                .init(id: "smoke-week-1", title: "TEST ONLY · Поточний тиждень 1", effectiveDay: nil, completed: true),
                .init(id: "smoke-week-2", title: "TEST ONLY · Поточний тиждень 2", effectiveDay: nil, completed: false),
                .init(id: "smoke-week-3", title: "TEST ONLY · Поточний тиждень 3", effectiveDay: nil, completed: true),
                .init(id: "smoke-week-4", title: "TEST ONLY · Поточний тиждень 4", effectiveDay: nil, completed: false)
            ],
            completedThisWeek: 2,
            totalThisWeek: 4,
            coverageComplete: true)
        let written = write(snapshot)
        if written { WidgetCenter.shared.reloadTimelines(ofKind: kind) }
        return written
    }
    #endif
}
