import Foundation

protocol OrbitCalendarV2EventLike {
    var id: String { get }
    var startsAt: Date { get }
    var endsAt: Date { get }
    var sourceType: String { get }
    var sourceIdentifier: String? { get }
}

enum OrbitCalendarV2Logic {
    enum Section: String, CaseIterable, Hashable {
        case calendar
        case selectedDate
        case today
        case thisWeek
        case nextWeek
        case later
    }

    enum DisplayMode: Equatable {
        case week
        case month

        mutating func toggle() {
            self = self == .week ? .month : .week
        }
    }

    struct Timeline<Event> {
        let today: [Event]
        let thisWeek: [Event]
        let nextWeek: [Event]
        let later: [Event]
    }

    static let sectionOrder: [Section] = Section.allCases

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

    static func weekInterval(containing date: Date, calendar: Calendar) -> DateInterval? {
        calendar.dateInterval(of: .weekOfYear, for: date)
    }

    static func weekDays(containing date: Date, calendar: Calendar) -> [Date] {
        guard let interval = weekInterval(containing: date, calendar: calendar) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
    }

    static func showsSelectedDateSection(selectedDate: Date?, today: Date, calendar: Calendar) -> Bool {
        guard let selectedDate else { return false }
        return !calendar.isDate(selectedDate, inSameDayAs: today)
    }

    static func eventKey<Event: OrbitCalendarV2EventLike>(_ event: Event) -> String {
        event.id
    }

    /// Partitions the timeline by local calendar periods. A spanning event is
    /// assigned to its first visible section, so no event identity repeats.
    static func timeline<Event: OrbitCalendarV2EventLike>(
        _ events: [Event],
        now: Date,
        calendar: Calendar,
        excluding excludedKeys: Set<String> = []
    ) -> Timeline<Event> {
        let unique = deduplicated(events).filter { !excludedKeys.contains(eventKey($0)) }
        var assigned = Set<String>()
        let today = unique.filter { occurs($0, on: now, calendar: calendar) && assigned.insert(eventKey($0)).inserted }

        guard let currentWeek = weekInterval(containing: now, calendar: calendar),
              let nextWeek = weekInterval(containing: currentWeek.end, calendar: calendar) else {
            return Timeline(today: today, thisWeek: [], nextWeek: [], later: [])
        }

        func intersects(_ event: Event, _ period: DateInterval) -> Bool {
            event.startsAt < period.end && event.endsAt > period.start
        }

        let thisWeek = unique.filter { intersects($0, currentWeek) && assigned.insert(eventKey($0)).inserted }
        let nextWeekEvents = unique.filter { intersects($0, nextWeek) && assigned.insert(eventKey($0)).inserted }
        let laterCandidates = unique
            .filter { $0.startsAt >= nextWeek.end && $0.endsAt > now && !assigned.contains(eventKey($0)) }
            .sorted(by: eventOrder)
        let later = Array(laterCandidates.filter { assigned.insert(eventKey($0)).inserted }.prefix(5))
        return Timeline(today: today.sorted(by: eventOrder), thisWeek: thisWeek.sorted(by: eventOrder), nextWeek: nextWeekEvents.sorted(by: eventOrder), later: later)
    }

    static func deduplicated<Event: OrbitCalendarV2EventLike>(_ events: [Event]) -> [Event] {
        var seen = Set<String>()
        return events.filter { event in
            seen.insert(sourceEventKey(event)).inserted
        }
    }

    static func nextFive<Event: OrbitCalendarV2EventLike>(_ events: [Event], now: Date) -> [Event] {
        Array(deduplicated(events)
            .filter { $0.endsAt > now }
            .sorted(by: eventOrder)
            .prefix(5))
    }

    private static func eventOrder<Event: OrbitCalendarV2EventLike>(_ lhs: Event, _ rhs: Event) -> Bool {
        if lhs.startsAt != rhs.startsAt { return lhs.startsAt < rhs.startsAt }
        if lhs.id != rhs.id { return lhs.id < rhs.id }
        return sourceEventKey(lhs) < sourceEventKey(rhs)
    }

    private static func sourceEventKey<Event: OrbitCalendarV2EventLike>(_ event: Event) -> String {
        "\(event.sourceIdentifier ?? event.sourceType):\(event.id)"
    }
}
