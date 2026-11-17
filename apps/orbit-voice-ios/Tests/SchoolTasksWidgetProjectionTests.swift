import Foundation

private func makeTask(_ id: String, _ due: String?, completed: Bool = false) -> SchoolHubTask {
    SchoolHubTask(id: id, title: "Synthetic \(id)", action: nil, dueAt: due,
                  allDay: true, importance: nil, target: nil, confidence: nil,
                  reason: nil, sourceItemId: id, status: completed ? "completed" : "open")
}

@main
struct SchoolTasksWidgetProjectionTests {
    @MainActor static func main() throws {
        let clock = ISO8601DateFormatter()
        let now = clock.date(from: "2026-11-16T12:00:00Z")!
        let tasks = [
            makeTask("overdue", "2026-11-11"),
            makeTask("week-a", "2026-11-16", completed: true),
            makeTask("week-b", "2026-11-17"),
            makeTask("week-c", "2026-11-18", completed: true),
            makeTask("week-d", "2026-11-19"),
            makeTask("next", "2026-11-23"),
            makeTask("undated", nil),
        ]
        let snapshot = SchoolTasksWidgetProjection.make(tasks: tasks, sourceDates: [:], now: now, coverageComplete: true)
        precondition(snapshot.schemaVersion == 1 && snapshot.weekStart == "2026-11-16")
        precondition(snapshot.openCount == 5)
        precondition(snapshot.overdue.map(\.id) == ["overdue"])
        precondition(snapshot.thisWeek.map(\.id) == ["week-a", "week-b", "week-c", "week-d"])
        precondition(snapshot.completedThisWeek == 2 && snapshot.totalThisWeek == 4)
        precondition(snapshot.allPrioritized.count == 5)
        // iPhone 12 is 390x844 pt; Apple's iOS dimensions specify a 338x158 pt
        // medium widget. With this view's 11 pt vertical padding, 136 pt remain.
        let mediumBudget = SchoolTasksWidgetLayout.mediumRowBudget(
            availableHeight: 136, captionPointSize: 11, accessibilitySize: false,
            coverageComplete: true)
        precondition(mediumBudget == 5)
        precondition(SchoolTasksWidgetLayout.visibleRowCount(totalRows: snapshot.allPrioritized.count, rowBudget: mediumBudget) == 5)
        precondition(snapshot.overdue.count == 1 && snapshot.thisWeek.count == 4)
        precondition(snapshot.completedThisWeek == 2 && snapshot.totalThisWeek == 4)
        let overflowBudget = SchoolTasksWidgetLayout.mediumRowBudget(
            availableHeight: 136, captionPointSize: 11, accessibilitySize: false,
            coverageComplete: true)
        precondition(SchoolTasksWidgetLayout.visibleRowCount(totalRows: 7, rowBudget: overflowBudget) == 4)
        precondition(SchoolTasksWidgetLayout.hiddenRowCount(totalRows: 7, visibleRows: 4) == 3,
                     "overflow link reports all three hidden rows")
        precondition(SchoolTasksWidgetLayout.mediumRowBudget(
            availableHeight: 136, captionPointSize: 22, accessibilitySize: true,
            coverageComplete: true) == 3, "accessibility rows and overflow link fit without clipping")
        precondition(SchoolTasksWidgetLayout.visibleRowCount(totalRows: 5, rowBudget: 3) == 2)
        let readableProfile = SchoolTasksWidgetPublicationEligibility.allows(
            resolvedPersonID: "child-42", itemsReadForCurrentLoad: true,
            tasksReadForCurrentLoad: true, actionTasksReadForCurrentLoad: true,
            hasReadableActionAccess: true, schoolReadPermission: true)
        precondition(readableProfile)
        precondition(!SchoolTasksWidgetPublicationEligibility.allows(
            resolvedPersonID: "-", itemsReadForCurrentLoad: true,
            tasksReadForCurrentLoad: true, actionTasksReadForCurrentLoad: true,
            hasReadableActionAccess: true, schoolReadPermission: true), "unresolved identity fails closed")
        precondition(!SchoolTasksWidgetPublicationEligibility.allows(
            resolvedPersonID: "child-42", itemsReadForCurrentLoad: true,
            tasksReadForCurrentLoad: true, actionTasksReadForCurrentLoad: false,
            hasReadableActionAccess: true, schoolReadPermission: true), "stale action read fails closed")
        precondition(!SchoolTasksWidgetPublicationEligibility.allows(
            resolvedPersonID: "child-42", itemsReadForCurrentLoad: true,
            tasksReadForCurrentLoad: true, actionTasksReadForCurrentLoad: true,
            hasReadableActionAccess: true, schoolReadPermission: false), "revoked permission fails closed")
        let rejected = SchoolTasksWidgetPublicationEligibility.rejectionReasons(
            resolvedPersonID: "child-42", itemsReadForCurrentLoad: false,
            tasksReadForCurrentLoad: true, actionTasksReadForCurrentLoad: false,
            hasReadableActionAccess: false, schoolReadPermission: false)
        precondition(rejected == ["items_read_not_current", "action_tasks_read_not_current", "action_access_unavailable", "school_read_denied"], "status codes identify producer eligibility failures without identity data")
        precondition(snapshot.allPrioritized.allSatisfy { $0.id != "next" && $0.id != "undated" })
        precondition(snapshot.isUsable(at: now))
        precondition(!snapshot.isUsable(at: now.addingTimeInterval(-300)))
        precondition(!snapshot.isUsable(at: now.addingTimeInterval(13 * 3600)))
        precondition(!snapshot.isUsable(at: now.addingTimeInterval(7 * 86400)))
        precondition(snapshot.unusableReason(at: now.addingTimeInterval(-300)) == "generated_in_future")
        precondition(snapshot.unusableReason(at: now.addingTimeInterval(13 * 3600)) == "stale")
        precondition(snapshot.unusableReason(at: now.addingTimeInterval(7 * 86400)) == "week_mismatch")
        let roundTrip = try JSONDecoder().decode(SchoolTasksWidgetSnapshot.self, from: JSONEncoder().encode(snapshot))
        precondition(roundTrip == snapshot)
        let currentWeekPast = SchoolTasksWidgetProjection.make(
            tasks: [makeTask("monday", "2026-11-16")], sourceDates: [:],
            now: clock.date(from: "2026-11-19T12:00:00Z")!, coverageComplete: false)
        precondition(currentWeekPast.overdue.isEmpty && currentWeekPast.thisWeek.count == 1)
        precondition(!currentWeekPast.coverageComplete)
        let sunday = SchoolTasksWidgetProjection.make(
            tasks: [makeTask("sunday", "2026-11-15")], sourceDates: [:],
            now: clock.date(from: "2026-11-15T12:00:00Z")!, coverageComplete: true)
        precondition(sunday.weekStart == "2026-11-09" && sunday.thisWeek.map(\.id) == ["sunday"])
        let mondayRollover = SchoolTasksWidgetProjection.make(
            tasks: [makeTask("sunday", "2026-11-15")], sourceDates: [:],
            now: clock.date(from: "2026-11-16T12:00:00Z")!, coverageComplete: true)
        precondition(mondayRollover.weekStart == "2026-11-16" && mondayRollover.overdue.map(\.id) == ["sunday"])
        let empty = SchoolTasksWidgetProjection.make(tasks: [], sourceDates: [:], now: now, coverageComplete: true)
        precondition(empty.openCount == 0 && empty.overdue.isEmpty && empty.thisWeek.isEmpty)
        let completedPrevious = SchoolTasksWidgetProjection.make(
            tasks: [makeTask("previous", "2026-11-11", completed: true)], sourceDates: [:], now: now, coverageComplete: true)
        precondition(completedPrevious.overdue.isEmpty)
        print("school tasks widget projection tests passed")
    }
}
