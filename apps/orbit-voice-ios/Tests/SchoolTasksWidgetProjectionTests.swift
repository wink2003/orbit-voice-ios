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
        precondition(snapshot.allPrioritized.allSatisfy { $0.id != "next" && $0.id != "undated" })
        precondition(snapshot.isUsable(at: now))
        precondition(!snapshot.isUsable(at: now.addingTimeInterval(-300)))
        precondition(!snapshot.isUsable(at: now.addingTimeInterval(13 * 3600)))
        precondition(!snapshot.isUsable(at: now.addingTimeInterval(7 * 86400)))
        let roundTrip = try JSONDecoder().decode(SchoolTasksWidgetSnapshot.self, from: JSONEncoder().encode(snapshot))
        precondition(roundTrip == snapshot)
        let currentWeekPast = SchoolTasksWidgetProjection.make(
            tasks: [makeTask("monday", "2026-11-16")], sourceDates: [:],
            now: clock.date(from: "2026-11-19T12:00:00Z")!, coverageComplete: false)
        precondition(currentWeekPast.overdue.isEmpty && currentWeekPast.thisWeek.count == 1)
        precondition(!currentWeekPast.coverageComplete)
        let completedPrevious = SchoolTasksWidgetProjection.make(
            tasks: [makeTask("previous", "2026-11-11", completed: true)], sourceDates: [:], now: now, coverageComplete: true)
        precondition(completedPrevious.overdue.isEmpty)
        print("school tasks widget projection tests passed")
    }
}
