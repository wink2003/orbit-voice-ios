import Foundation

protocol OrbitCalendarV2EventLike {
    var id: String { get }
    var startsAt: Date { get }
    var endsAt: Date { get }
    var sourceType: String { get }
    var sourceIdentifier: String? { get }
}

enum OrbitCalendarV2Logic {
    static func monthGrid(for date: Date, calendar: Calendar) -> [Date] {
        let month = calendar.dateInterval(of: .month, for: date)?.start ?? date
        let weekday = calendar.component(.weekday, from: month)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let first = calendar.date(byAdding: .day, value: -leading, to: month) ?? month
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
    }

    static func occurs<Event: OrbitCalendarV2EventLike>(_ event: Event, on day: Date, calendar: Calendar) -> Bool {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return false }
        return event.startsAt < end && event.endsAt > start
    }

    static func deduplicated<Event: OrbitCalendarV2EventLike>(_ events: [Event]) -> [Event] {
        var seen = Set<String>()
        return events.filter { event in
            let source = event.sourceIdentifier ?? event.sourceType
            return seen.insert("\(source):\(event.id)").inserted
        }
    }

    static func nextFive<Event: OrbitCalendarV2EventLike>(_ events: [Event], now: Date) -> [Event] {
        Array(deduplicated(events)
            .filter { $0.endsAt > now }
            .sorted { $0.startsAt == $1.startsAt ? $0.id < $1.id : $0.startsAt < $1.startsAt }
            .prefix(5))
    }
}
