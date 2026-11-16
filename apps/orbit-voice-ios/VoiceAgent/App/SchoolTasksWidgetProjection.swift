import Foundation

// Pure presentation contract for Issue #119. Uses the SAME grouping as School Hub.
// The widget extension receives this Codable snapshot, never SchoolHubStore,
// backend credentials, source letters or a second implementation of due-date rules.
nonisolated struct SchoolTasksWidgetRow: Codable, Hashable, Identifiable {
    let id: String
    let title: String
    let effectiveDay: String?
    let completed: Bool
}

nonisolated struct SchoolTasksWidgetSnapshot: Codable, Equatable {
    let schemaVersion: Int
    let generatedAt: Date
    let weekStart: String
    let openCount: Int
    let overdue: [SchoolTasksWidgetRow]
    let thisWeek: [SchoolTasksWidgetRow]
    let completedThisWeek: Int
    let totalThisWeek: Int
    let coverageComplete: Bool

    var allPrioritized: [SchoolTasksWidgetRow] { overdue + thisWeek }

    /// Fail closed when stale, generated in the future or crossing a school week.
    func isUsable(at now: Date) -> Bool {
        let age = now.timeIntervalSince(generatedAt)
        return schemaVersion == 1 && age >= -60 && age <= 12 * 3600
            && weekStart == Self.schoolWeekStart(for: now)
    }

    /// Matches the Monday-first school calendar using Europe/Berlin civil days.
    static func schoolWeekStart(for date: Date) -> String {
        var calendar = Calendar(identifier: .iso8601)
        calendar.firstWeekday = 2
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        let p = calendar.dateComponents([.year, .month, .day], from: start)
        return String(format: "%04d-%02d-%02d", p.year ?? 0, p.month ?? 0, p.day ?? 0)
    }
}

nonisolated enum SchoolTasksWidgetProjection {
    static func make(
        tasks: [SchoolHubTask],
        sourceDates: [String: Date],
        now: Date,
        coverageComplete: Bool
    ) -> SchoolTasksWidgetSnapshot {
        let day = SchoolHubLogic.dayKey(of: now)
        let sections = SchoolHubLogic.taskSections(tasks, filter: .all, today: day, sourceDates: sourceDates, now: now)
        func row(_ task: SchoolHubTask) -> SchoolTasksWidgetRow {
            SchoolTasksWidgetRow(
                id: task.id,
                title: String(task.title.prefix(140)),
                effectiveDay: SchoolHubLogic.effectiveTaskDay(task, sourceDates: sourceDates),
                completed: SchoolHubLogic.isCompleted(task)
            )
        }
        return SchoolTasksWidgetSnapshot(
            schemaVersion: 1,
            generatedAt: now,
            weekStart: SchoolTasksWidgetSnapshot.schoolWeekStart(for: now),
            openCount: SchoolHubLogic.taskCounts(tasks).open,
            overdue: sections.overdue.map(row),
            thisWeek: sections.thisWeek.map(row),
            completedThisWeek: sections.thisWeek.filter(SchoolHubLogic.isCompleted).count,
            totalThisWeek: sections.thisWeek.count,
            coverageComplete: coverageComplete
        )
    }
}
