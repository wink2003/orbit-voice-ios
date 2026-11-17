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

