import Foundation

// Pure presentation contract for Issue #119. Uses the SAME grouping as School Hub.
// The widget extension receives this Codable snapshot, never SchoolHubStore,
// backend credentials, source letters or a second implementation of due-date rules.
nonisolated enum SchoolTasksWidgetProjection {
    @MainActor static func make(
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
