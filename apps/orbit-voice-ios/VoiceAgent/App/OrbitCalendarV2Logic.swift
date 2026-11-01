import Foundation

enum OrbitCalendarV2Logic {
    static func monthGrid(for date: Date, calendar: Calendar) -> [Date] {
        let month = calendar.dateInterval(of: .month, for: date)?.start ?? date
        let weekday = calendar.component(.weekday, from: month)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let first = calendar.date(byAdding: .day, value: -leading, to: month) ?? month
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
    }

    static func occurs(_ event: OrbitCalendarEvent, on day: Date, calendar: Calendar) -> Bool {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return false }
        return event.startsAt < end && event.endsAt > start
    }

    static func deduplicated(_ events: [OrbitCalendarEvent]) -> [OrbitCalendarEvent] {
        var seen = Set<String>()
        return events.filter { event in
            let source = event.sourceIdentifier ?? event.sourceType
            return seen.insert("\(source):\(event.id)").inserted
        }
    }

    static func nextFive(_ events: [OrbitCalendarEvent], now: Date) -> [OrbitCalendarEvent] {
        Array(deduplicated(events)
            .filter { $0.endsAt > now }
            .sorted { $0.startsAt == $1.startsAt ? $0.id < $1.id : $0.startsAt < $1.startsAt }
            .prefix(5))
    }
}
