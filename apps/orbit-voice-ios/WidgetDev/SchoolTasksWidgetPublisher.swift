import Foundation
import WidgetKit

enum SchoolTasksWidgetDiagnosticStore {
    static let loadKey = "orbit.schoolTasksWidgetDiagnostics.load.v1"
    static let eligibilityKey = "orbit.schoolTasksWidgetDiagnostics.eligibility.v1"
    static let containerKey = "orbit.schoolTasksWidgetDiagnostics.appGroup.v1"
    static let writeKey = "orbit.schoolTasksWidgetDiagnostics.write.v1"
    static let reloadKey = "orbit.schoolTasksWidgetDiagnostics.reload.v1"
    static let reloadAtKey = "orbit.schoolTasksWidgetDiagnostics.reloadAt.v1"

    static func record(_ value: String, for key: String) {
        UserDefaults.standard.set(value, forKey: key)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key + ".updatedAt")
    }
}

// Main Orbit writes only authorized, minimized task snapshots. The widget has
// no network client, credentials, or task mutation path.
@MainActor
enum SchoolTasksWidgetPublisher {
    private static let suite = "group.net.opik.orbit.voice"
    private static let key = "school.tasks.widget.snapshot.v1"
    private static let kind = "orbit.school.tasks"

    static func recordEligibility(reasons: [String]) {
        let result = reasons.isEmpty ? "allowed" : "denied"
        let codes = reasons.joined(separator: ",")
        SchoolTasksWidgetDiagnosticStore.record(
            codes.isEmpty ? result : "\(result):\(codes)",
            for: SchoolTasksWidgetDiagnosticStore.eligibilityKey)
    }

    static func recordLoadOutcome(items: String, tasks: String, actionTasks: String) {
        SchoolTasksWidgetDiagnosticStore.record(
            "items=\(items),tasks=\(tasks),action_tasks=\(actionTasks)",
            for: SchoolTasksWidgetDiagnosticStore.loadKey)
    }

    static func recordLoadBlocked(reason: String) {
        SchoolTasksWidgetDiagnosticStore.record("blocked:\(reason)", for: SchoolTasksWidgetDiagnosticStore.loadKey)
    }

    static func recordScopeReset() {
        SchoolTasksWidgetDiagnosticStore.record("not_evaluated:scope_reset", for: SchoolTasksWidgetDiagnosticStore.eligibilityKey)
        SchoolTasksWidgetDiagnosticStore.record("not_run:scope_reset", for: SchoolTasksWidgetDiagnosticStore.loadKey)
    }

    static func publish(
        tasks: [SchoolHubTask],
        sourceDates: [String: Date],
        now: Date,
        verifiedCurrentScope: Bool,
        coverageComplete: Bool
    ) {
        guard verifiedCurrentScope else {
            clear(); return
        }
        let groupContainerAvailable = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: suite) != nil
        let groupStatus = groupContainerAvailable ? "available" : "unavailable"
        SchoolTasksWidgetDiagnosticStore.record(groupStatus, for: SchoolTasksWidgetDiagnosticStore.containerKey)
        guard groupContainerAvailable else {
            SchoolTasksWidgetDiagnosticStore.record("app_group_unavailable", for: SchoolTasksWidgetDiagnosticStore.writeKey)
            clear(); return
        }
        let snapshot = SchoolTasksWidgetProjection.make(
            tasks: tasks, sourceDates: sourceDates, now: now,
            coverageComplete: coverageComplete)
        guard write(snapshot) else {
            clear(); return
        }
        requestTimelineReload()
    }

    private static func write(_ snapshot: SchoolTasksWidgetSnapshot) -> Bool {
        guard let store = UserDefaults(suiteName: suite) else {
            SchoolTasksWidgetDiagnosticStore.record("defaults_suite_unavailable", for: SchoolTasksWidgetDiagnosticStore.writeKey)
            return false
        }
        guard let data = try? JSONEncoder().encode(snapshot) else {
            SchoolTasksWidgetDiagnosticStore.record("encoding_failed", for: SchoolTasksWidgetDiagnosticStore.writeKey)
            return false
        }
        store.set(data, forKey: key)
        let readbackSucceeded = store.data(forKey: key) == data
        SchoolTasksWidgetDiagnosticStore.record(
            readbackSucceeded ? "readback_ok" : "readback_failed",
            for: SchoolTasksWidgetDiagnosticStore.writeKey)
        guard readbackSucceeded else { return false }
        return true
    }

    static func clear() {
        UserDefaults(suiteName: suite)?.removeObject(forKey: key)
        requestTimelineReload()
    }

    private static func requestTimelineReload() {
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
        SchoolTasksWidgetDiagnosticStore.record("requested", for: SchoolTasksWidgetDiagnosticStore.reloadKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: SchoolTasksWidgetDiagnosticStore.reloadAtKey)
    }

}
