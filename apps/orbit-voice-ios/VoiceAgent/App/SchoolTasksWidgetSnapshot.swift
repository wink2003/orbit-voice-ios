import Foundation

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

/// Small, deterministic row budget used by the non-scrollable medium widget.
/// It reserves a row for the overflow link instead of silently hiding tasks.
nonisolated enum SchoolTasksWidgetLayout {
    static func mediumRowBudget(
        availableHeight: Double,
        captionPointSize: Double,
        accessibilitySize: Bool,
        coverageComplete: Bool
    ) -> Int {
        let rowHeight = max(16, captionPointSize + (accessibilitySize ? 9 : 5))
        // At accessibility sizes section captions move into the compact header,
        // freeing room for readable task rows and a separate overflow link.
        let overhead = (accessibilitySize ? captionPointSize + 13 : 51)
            + (coverageComplete ? 0 : 10)
        return max(0, Int((availableHeight - overhead) / rowHeight))
    }

    static func visibleRowCount(totalRows: Int, rowBudget: Int) -> Int {
        max(0, rowBudget - (totalRows > rowBudget ? 1 : 0))
    }

    static func hiddenRowCount(totalRows: Int, visibleRows: Int) -> Int {
        max(0, totalRows - visibleRows)
    }
}

/// Publishing requires the active, resolved profile and successful reads from
/// the current load. Unknown permissions may proceed only after the authorized
/// action-task read itself succeeds; an explicit deny always closes the gate.
nonisolated enum SchoolTasksWidgetPublicationEligibility {
    static func allows(
        resolvedPersonID: String?,
        itemsReadForCurrentLoad: Bool,
        tasksReadForCurrentLoad: Bool,
        actionTasksReadForCurrentLoad: Bool,
        hasReadableActionAccess: Bool,
        schoolReadPermission: Bool?
    ) -> Bool {
        guard let personID = resolvedPersonID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !personID.isEmpty, personID != "-",
              itemsReadForCurrentLoad,
              tasksReadForCurrentLoad,
              actionTasksReadForCurrentLoad,
              hasReadableActionAccess,
              schoolReadPermission != false else { return false }
        return true
    }
}

