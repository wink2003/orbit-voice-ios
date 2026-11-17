import Foundation

/// SideStore reads requested entitlements from each Mach-O signature, then
/// provisions a team-scoped App Group and injects its effective identifier in
/// ALTAppGroups. Xcode installs keep using the source identifier directly.
nonisolated enum SchoolTasksWidgetAppGroup {
    static let requestedIdentifier = "group.net.opik.orbit.voice"
    private static let sideStoreInfoKey = "ALTAppGroups"

    static func identifier(in infoDictionary: [String: Any]) -> String {
        let groups = infoDictionary[sideStoreInfoKey] as? [String] ?? []
        let provisioned = groups.filter { $0.hasPrefix(requestedIdentifier + ".") }
        guard provisioned.count == 1, let identifier = provisioned.first else {
            return requestedIdentifier
        }
        return identifier
    }

    static var currentIdentifier: String {
        identifier(in: Bundle.main.infoDictionary ?? [:])
    }
}

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
        unusableReason(at: now) == nil
    }

    /// Non-sensitive reason code surfaced by owner-only diagnostics and the widget fallback.
    func unusableReason(at now: Date) -> String? {
        guard schemaVersion == 1 else { return "schema_mismatch" }
        let age = now.timeIntervalSince(generatedAt)
        guard age >= -60 else { return "generated_in_future" }
        guard weekStart == Self.schoolWeekStart(for: now) else { return "week_mismatch" }
        guard age <= 12 * 3600 else { return "stale" }
        return nil
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
    static func rejectionReasons(
        resolvedPersonID: String?,
        itemsReadForCurrentLoad: Bool,
        tasksReadForCurrentLoad: Bool,
        actionTasksReadForCurrentLoad: Bool,
        hasReadableActionAccess: Bool,
        schoolReadPermission: Bool?
    ) -> [String] {
        var reasons: [String] = []
        guard let personID = resolvedPersonID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !personID.isEmpty, personID != "-" else {
            reasons.append("identity_unresolved")
            return reasons
        }
        if !itemsReadForCurrentLoad { reasons.append("items_read_not_current") }
        if !tasksReadForCurrentLoad { reasons.append("tasks_read_not_current") }
        if !actionTasksReadForCurrentLoad { reasons.append("action_tasks_read_not_current") }
        if !hasReadableActionAccess { reasons.append("action_access_unavailable") }
        if schoolReadPermission == false { reasons.append("school_read_denied") }
        return reasons
    }

    static func allows(
        resolvedPersonID: String?,
        itemsReadForCurrentLoad: Bool,
        tasksReadForCurrentLoad: Bool,
        actionTasksReadForCurrentLoad: Bool,
        hasReadableActionAccess: Bool,
        schoolReadPermission: Bool?
    ) -> Bool {
        rejectionReasons(
            resolvedPersonID: resolvedPersonID,
            itemsReadForCurrentLoad: itemsReadForCurrentLoad,
            tasksReadForCurrentLoad: tasksReadForCurrentLoad,
            actionTasksReadForCurrentLoad: actionTasksReadForCurrentLoad,
            hasReadableActionAccess: hasReadableActionAccess,
            schoolReadPermission: schoolReadPermission
        ).isEmpty
    }
}

