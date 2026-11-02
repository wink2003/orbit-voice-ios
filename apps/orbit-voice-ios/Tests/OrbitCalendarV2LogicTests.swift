import Foundation

private struct FixtureEvent: OrbitCalendarV2EventLike {
    let id: String
    let startsAt: Date
    let endsAt: Date
    let sourceType: String
    let sourceIdentifier: String?
}

@main
struct OrbitCalendarV2LogicTests {
    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = TimeZone(identifier: "Europe/Kyiv")!

        let february = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))!
        let grid = OrbitCalendarV2Logic.monthGrid(for: february, calendar: calendar)
        precondition(grid.count == 42, "month grid has six complete weeks")
        precondition(calendar.component(.weekday, from: grid[0]) == 2, "month grid starts Monday")
        precondition(calendar.component(.day, from: grid[1]) == 27, "leading day is correct")

        let day = calendar.date(from: DateComponents(year: 2026, month: 3, day: 29))!
        let multiDay = FixtureEvent(id: "multi", startsAt: calendar.date(byAdding: .day, value: -1, to: day)!, endsAt: calendar.date(byAdding: .day, value: 2, to: day)!, sourceType: "external", sourceIdentifier: "source")
        precondition(OrbitCalendarV2Logic.occurs(multiDay, on: day, calendar: calendar), "multi-day event overlaps selected day")

        let dstWeekDate = calendar.date(from: DateComponents(year: 2026, month: 3, day: 25, hour: 12))!
        let dstWeek = OrbitCalendarV2Logic.weekInterval(containing: dstWeekDate, calendar: calendar)!
        precondition(calendar.component(.weekday, from: dstWeek.start) == 2, "week begins Monday in the configured local calendar")
        precondition(OrbitCalendarV2Logic.weekDays(containing: dstWeekDate, calendar: calendar).count == 7, "collapsed week has seven local dates across DST")
        precondition(calendar.component(.day, from: dstWeek.end) == 30, "week boundary is the following Monday across DST")

        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 12))!
        let currentWeek = OrbitCalendarV2Logic.weekInterval(containing: today, calendar: calendar)!
        let nextWeek = OrbitCalendarV2Logic.nextWeekInterval(after: currentWeek, calendar: calendar)!
        precondition(nextWeek.start == currentWeek.end, "next week starts at the exclusive current-week boundary")
        precondition(!OrbitCalendarV2Logic.showsSelectedDateSection(selectedDate: nil, today: today, calendar: calendar), "default date selection creates no selected-date section")
        precondition(!OrbitCalendarV2Logic.showsSelectedDateSection(selectedDate: today, today: today, calendar: calendar), "explicitly selecting today creates no duplicate selected-date section")
        precondition(OrbitCalendarV2Logic.showsSelectedDateSection(selectedDate: today.addingTimeInterval(86_400), today: today, calendar: calendar), "explicit selection of another date shows the selected-date section")

        var mode = OrbitCalendarV2Logic.DisplayMode.week
        mode.toggle()
        precondition(mode == .month, "week expands to full month")
        mode.toggle()
        precondition(mode == .week, "full month collapses back to week")
        precondition(OrbitCalendarV2Logic.sectionOrder.map(\.rawValue) == ["calendar", "selectedDate", "today", "thisWeek", "nextWeek", "later"], "timeline blocks retain the accepted display order")

        func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
        }
        func event(_ id: String, _ start: Date, _ end: Date, source: String = "family") -> FixtureEvent {
            FixtureEvent(id: id, startsAt: start, endsAt: end, sourceType: "external", sourceIdentifier: source)
        }
        let timelineEvents = [
            event("today", at(2026, 10, 28, 13), at(2026, 10, 28, 14)),
            event("week", at(2026, 10, 26, 9), at(2026, 10, 26, 10)),
            event("week", at(2026, 11, 3, 8), at(2026, 11, 3, 9), source: "icloud"),
            event("spans-weeks", at(2026, 10, 31, 9), at(2026, 11, 4, 10)),
            event("next-week", at(2026, 11, 3, 11), at(2026, 11, 3, 12)),
            event("before-boundary", at(2026, 11, 8, 23, 30), at(2026, 11, 9, 0, 30)),
            event("after-1", at(2026, 11, 9), at(2026, 11, 9, 1)),
            event("after-2", at(2026, 11, 10), at(2026, 11, 10, 1)),
            event("after-3", at(2026, 11, 11), at(2026, 11, 11, 1)),
            event("after-4", at(2026, 11, 12), at(2026, 11, 12, 1)),
            event("after-5", at(2026, 11, 13), at(2026, 11, 13, 1)),
            event("after-6", at(2026, 11, 14), at(2026, 11, 14, 1))
        ]
        let excluded = Set([OrbitCalendarV2Logic.eventKey(timelineEvents[5])])
        let timeline = OrbitCalendarV2Logic.timeline(timelineEvents + [timelineEvents[1]], now: today, calendar: calendar, excluding: excluded)
        precondition(timeline.today.map(\.id) == ["today"], "today section contains today's event")
        precondition(timeline.thisWeek.map(\.id) == ["week", "spans-weeks"], "current-week section handles cross-week events once")
        precondition(timeline.nextWeek.map(\.id) == ["next-week", "before-boundary"], "next-week section includes the full local week; got \(timeline.nextWeek.map(\.id)), current week got \(timeline.thisWeek.map(\.id))")
        precondition(timeline.later.map(\.id) == ["after-2", "after-3", "after-4", "after-5", "after-6"], "later section has five chronological events strictly after next week")
        let sectionKeys = timeline.today + timeline.thisWeek + timeline.nextWeek + timeline.later
        precondition(Set(sectionKeys.map(OrbitCalendarV2Logic.eventKey)).count == sectionKeys.count, "event identities never repeat across timeline sections")
        let empty = OrbitCalendarV2Logic.timeline([FixtureEvent](), now: today, calendar: calendar)
        precondition(empty.today.isEmpty && empty.thisWeek.isEmpty && empty.nextWeek.isEmpty && empty.later.isEmpty, "empty calendar preserves empty section state")

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let duplicate = FixtureEvent(id: "same", startsAt: now.addingTimeInterval(600), endsAt: now.addingTimeInterval(1200), sourceType: "external", sourceIdentifier: "a")
        let later = (1...6).map { offset in
            FixtureEvent(id: "e\(offset)", startsAt: now.addingTimeInterval(Double(offset) * 3600), endsAt: now.addingTimeInterval(Double(offset) * 3600 + 600), sourceType: "external", sourceIdentifier: "b")
        }
        let result = OrbitCalendarV2Logic.nextFive([later[5], duplicate, later[1], duplicate, later[0], later[2], later[3], later[4]], now: now)
        precondition(result.map(\.id) == ["same", "e1", "e2", "e3", "e4"], "next-five is sorted and deduplicated")
        print("OrbitCalendarV2LogicTests passed")
    }
}
