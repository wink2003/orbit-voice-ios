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
        precondition(calendar.component(.day, from: nextWeek.start) == 2 && calendar.component(.day, from: nextWeek.end) == 9, "next week spans Monday November 2 through the exclusive Monday November 9 boundary")
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
        let timeline = OrbitCalendarV2Logic.timeline(timelineEvents + [timelineEvents[1]], now: today, calendar: calendar)
        precondition(timeline.today.map(\.id) == ["today"], "today section contains today's event")
        precondition(timeline.thisWeek.map(OrbitCalendarV2Logic.eventKey) == ["family:week", "family:spans-weeks"], "family event remains in the current-week section")
        let iso = ISO8601DateFormatter()
        precondition(timeline.nextWeek.map(OrbitCalendarV2Logic.eventKey) == ["icloud:week", "family:next-week", "family:before-boundary"], "iCloud event with a colliding raw ID remains in next week; got \(timeline.nextWeek.map(OrbitCalendarV2Logic.eventKey)), current week got \(timeline.thisWeek.map(OrbitCalendarV2Logic.eventKey)), later got \(timeline.later.map(\.id)), interval \(iso.string(from: nextWeek.start))..<\(iso.string(from: nextWeek.end)), boundary event \(iso.string(from: timelineEvents[4].startsAt))..<\(iso.string(from: timelineEvents[4].endsAt))")
        precondition(timeline.later.map(\.id) == ["after-1", "after-2", "after-3", "after-4", "after-5"], "later section has five chronological events starting at the exclusive next-week boundary")
        precondition(timeline.thisWeek.filter { OrbitCalendarV2Logic.eventKey($0) == "family:week" }.count == 1, "duplicate instances of one canonical event are assigned only once")
        precondition(OrbitCalendarV2Logic.eligibleLaterEventCount(timelineEvents, after: nextWeek.end, now: today, sourceIDs: []) == 0, "no selected sources produce no eligible later events")
        precondition(OrbitCalendarV2Logic.eligibleLaterEventCount(timelineEvents, after: nextWeek.end, now: today, sourceIDs: ["family"]) == 6, "later-event coverage counts selected sources only")
        precondition(OrbitCalendarV2Logic.eligibleLaterEventCount(timelineEvents, after: nextWeek.end, now: today, sourceIDs: ["family"], excluding: ["family:after-1"]) == 5, "selected-date canonical event identities are excluded from later-event coverage")
        precondition(OrbitCalendarV2Logic.eligibleLaterEventCount(timelineEvents, after: nextWeek.end, now: today, sourceIDs: ["unknown"]) == 0, "unselected sources do not inflate later-event coverage")
        let sectionKeys = timeline.today + timeline.thisWeek + timeline.nextWeek + timeline.later
        precondition(Set(sectionKeys.map(OrbitCalendarV2Logic.eventKey)).count == sectionKeys.count, "event identities never repeat across timeline sections")
        let selectedExclusion = OrbitCalendarV2Logic.timeline(timelineEvents, now: today, calendar: calendar, excluding: [OrbitCalendarV2Logic.eventKey(timelineEvents[0])])
        precondition(selectedExclusion.today.isEmpty, "selected-date event IDs are excluded from subsequent timeline sections")
        let empty = OrbitCalendarV2Logic.timeline([FixtureEvent](), now: today, calendar: calendar)
        precondition(empty.today.isEmpty && empty.thisWeek.isEmpty && empty.nextWeek.isEmpty && empty.later.isEmpty, "empty calendar preserves empty section state")
        precondition(OrbitCalendarV2Logic.nextEvent([FixtureEvent](), now: today).map(\.id) == nil, "empty sources keep the established no-upcoming-event preview")

        let previewEarlier = event("next-week-preview", at(2026, 11, 3, 9), at(2026, 11, 3, 10))
        let previewLater = event("later-preview", at(2026, 11, 9, 9), at(2026, 11, 9, 10))
        let previewExpired = event("expired-preview", at(2026, 10, 27, 9), at(2026, 10, 28, 12))
        let previewQueue = OrbitCalendarV2Logic.timeline([previewEarlier, previewLater, previewExpired], now: today, calendar: calendar)
        let preview = OrbitCalendarV2Logic.nextEvent(
            previewQueue.today + previewQueue.thisWeek + previewQueue.nextWeek + previewQueue.later,
            now: today
        )
        precondition(preview?.id == "next-week-preview", "Today preview chooses the nearer Next Week event instead of Later[0]")
        precondition(OrbitCalendarV2Logic.nextEvent([previewExpired], now: today).map(\.id) == nil, "event ending at local now is not presented as upcoming")

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
