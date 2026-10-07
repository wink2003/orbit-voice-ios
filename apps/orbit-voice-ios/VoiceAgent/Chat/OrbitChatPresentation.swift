import Foundation

nonisolated struct OrbitChatRowInput: Equatable {
    let id: String
    let senderKey: String
    let date: Date
}

nonisolated struct OrbitChatRowLayout: Equatable {
    let id: String
    let startsGroup: Bool
    let endsGroup: Bool
    let dateSeparator: String?
}

nonisolated enum OrbitChatPresentation {
    static let groupWindow: TimeInterval = 5 * 60

    static func displayTitle(kind: String, title: String) -> String {
        if kind == "family" { return "Родинний чат" }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.lowercased() == "orbit" ? "Мій Orbit" : trimmed
    }

    static func layout(_ rows: [OrbitChatRowInput], calendar: Calendar = .current, now: Date = Date(), locale: Locale = Locale(identifier: "uk_UA")) -> [OrbitChatRowLayout] {
        rows.enumerated().map { index, row in
            let previous = index > 0 ? rows[index - 1] : nil
            let next = index + 1 < rows.count ? rows[index + 1] : nil
            let startsGroup = previous.map { !sameGroup($0, row, calendar: calendar) } ?? true
            let endsGroup = next.map { !sameGroup(row, $0, calendar: calendar) } ?? true
            let newDay = previous.map { !calendar.isDate($0.date, inSameDayAs: row.date) } ?? true
            return OrbitChatRowLayout(id: row.id, startsGroup: startsGroup, endsGroup: endsGroup, dateSeparator: newDay ? dayLabel(row.date, calendar: calendar, now: now, locale: locale) : nil)
        }
    }

    static func sameGroup(_ a: OrbitChatRowInput, _ b: OrbitChatRowInput, calendar: Calendar) -> Bool {
        a.senderKey == b.senderKey && calendar.isDate(a.date, inSameDayAs: b.date) && abs(b.date.timeIntervalSince(a.date)) <= groupWindow
    }

    static func dayLabel(_ date: Date, calendar: Calendar = .current, now: Date = Date(), locale: Locale = Locale(identifier: "uk_UA")) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Сьогодні" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) { return "Вчора" }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        formatter.dateFormat = sameYear ? "d MMMM" : "d MMMM yyyy"
        return formatter.string(from: date)
    }

    // Local search is a case-insensitive substring filter over loaded messages only.
    static func matches(_ content: String, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return q.isEmpty || content.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
