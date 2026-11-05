import Foundation

private struct FixtureEvent: OrbitCalendarV2EventLike {
    let id: String
    let startsAt: Date
    let endsAt: Date
    let sourceType: String
    let sourceIdentifier: String?
    let occurrenceId: String?

    init(id: String, startsAt: Date, endsAt: Date, sourceType: String, sourceIdentifier: String?, occurrenceId: String? = nil) {
        self.id = id
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.sourceType = sourceType
        self.sourceIdentifier = sourceIdentifier
        self.occurrenceId = occurrenceId
    }
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
        let laterInterval = OrbitCalendarV2Logic.laterInterval(now: today, calendar: calendar)!
        precondition(laterInterval.start == nextWeek.end, "Later begins immediately after the Monday-based Next Week interval")
        precondition(calendar.component(.day, from: laterInterval.end) == 28 && calendar.component(.month, from: laterInterval.end) == 11, "Later horizon is one local calendar month after October 28")
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
        let beyondHorizon = event("beyond-horizon", at(2026, 11, 29), at(2026, 11, 29, 1))
        let timeline = OrbitCalendarV2Logic.timeline(timelineEvents + [timelineEvents[1], beyondHorizon], now: today, calendar: calendar, laterInterval: laterInterval)
        precondition(timeline.today.map(\.id) == ["today"], "today section contains today's event")
        precondition(timeline.thisWeek.map(OrbitCalendarV2Logic.eventKey) == ["family:spans-weeks"], "This Week excludes earlier days and Today while retaining an event on a later weekday")
        let iso = ISO8601DateFormatter()
        precondition(timeline.nextWeek.map(OrbitCalendarV2Logic.eventKey) == ["icloud:week", "family:next-week", "family:before-boundary"], "iCloud event with a colliding raw ID remains in next week; got \(timeline.nextWeek.map(OrbitCalendarV2Logic.eventKey)), current week got \(timeline.thisWeek.map(OrbitCalendarV2Logic.eventKey)), later got \(timeline.later.map(\.id)), interval \(iso.string(from: nextWeek.start))..<\(iso.string(from: nextWeek.end)), boundary event \(iso.string(from: timelineEvents[4].startsAt))..<\(iso.string(from: timelineEvents[4].endsAt))")
        precondition(timeline.later.map(\.id) == ["after-1", "after-2", "after-3", "after-4", "after-5"], "later section has five chronological events starting at the exclusive next-week boundary")
        precondition(!timeline.later.contains(where: { $0.id == "beyond-horizon" }), "events at or beyond HorizonEnd are excluded")
        precondition(timeline.thisWeek.filter { OrbitCalendarV2Logic.eventKey($0) == "family:week" }.isEmpty, "a canonical event on an earlier weekday is excluded from This Week")
        precondition(timeline.nextWeek.filter { OrbitCalendarV2Logic.eventKey($0) == "icloud:week" }.count == 1, "a same-ID event from another source remains assigned once to Next Week")
        precondition(OrbitCalendarV2Logic.eligibleLaterEventCount(timelineEvents, after: nextWeek.end, now: today, sourceIDs: []) == 0, "no selected sources produce no eligible later events")
        precondition(OrbitCalendarV2Logic.eligibleLaterEventCount(timelineEvents, after: nextWeek.end, now: today, sourceIDs: ["family"]) == 6, "later-event coverage counts selected sources only")
        precondition(OrbitCalendarV2Logic.eligibleLaterEventCount(timelineEvents, after: nextWeek.end, now: today, sourceIDs: ["family"], excluding: ["family:after-1"]) == 5, "selected-date canonical event identities are excluded from later-event coverage")
        precondition(OrbitCalendarV2Logic.eligibleLaterEventCount(timelineEvents, after: nextWeek.end, now: today, sourceIDs: ["unknown"]) == 0, "unselected sources do not inflate later-event coverage")
        let sunday = at(2026, 11, 8, 12)
        let sundayTimeline = OrbitCalendarV2Logic.timeline([
            event("sunday-today", at(2026, 11, 8, 9), at(2026, 11, 8, 10)),
            event("sunday-past", at(2026, 11, 6, 9), at(2026, 11, 6, 10)),
            event("monday-next", at(2026, 11, 9, 9), at(2026, 11, 9, 10))
        ], now: sunday, calendar: calendar)
        precondition(sundayTimeline.today.map(\.id) == ["sunday-today"] && sundayTimeline.thisWeek.isEmpty && sundayTimeline.nextWeek.map(\.id) == ["monday-next"], "Sunday separates the current day from next Monday without retaining past weekdays")
        let monday = at(2026, 11, 9, 12)
        let mondayTimeline = OrbitCalendarV2Logic.timeline([
            event("monday-today", at(2026, 11, 9, 9), at(2026, 11, 9, 10)),
            event("sunday-past", at(2026, 11, 8, 9), at(2026, 11, 8, 10)),
            event("tuesday", at(2026, 11, 10, 9), at(2026, 11, 10, 10))
        ], now: monday, calendar: calendar)
        precondition(mondayTimeline.today.map(\.id) == ["monday-today"] && mondayTimeline.thisWeek.map(\.id) == ["tuesday"], "Monday starts a new week and shows only future weekdays in This Week")
        let sectionKeys = timeline.today + timeline.thisWeek + timeline.nextWeek + timeline.later
        precondition(Set(sectionKeys.map(OrbitCalendarV2Logic.eventKey)).count == sectionKeys.count, "event identities never repeat across timeline sections")
        let selectedExclusion = OrbitCalendarV2Logic.timeline(timelineEvents, now: today, calendar: calendar, excluding: [OrbitCalendarV2Logic.eventKey(timelineEvents[0])])
        precondition(selectedExclusion.today.isEmpty, "selected-date event IDs are excluded from subsequent timeline sections")
        let empty = OrbitCalendarV2Logic.timeline([FixtureEvent](), now: today, calendar: calendar)
        precondition(empty.today.isEmpty && empty.thisWeek.isEmpty && empty.nextWeek.isEmpty && empty.later.isEmpty, "empty calendar preserves empty section state")
        precondition(OrbitCalendarV2Logic.nextEvent([FixtureEvent](), now: today).map(\.id) == nil, "empty sources keep the established no-upcoming-event preview")

        let recurringA = FixtureEvent(id: "series", startsAt: at(2026, 11, 10, 9), endsAt: at(2026, 11, 10, 10), sourceType: "external", sourceIdentifier: "caldav", occurrenceId: "caldav:series:2026-11-10")
        let recurringB = FixtureEvent(id: "series", startsAt: at(2026, 11, 11, 9), endsAt: at(2026, 11, 11, 10), sourceType: "external", sourceIdentifier: "caldav", occurrenceId: "caldav:series:2026-11-11")
        let recurrenceTimeline = OrbitCalendarV2Logic.timeline([recurringB, recurringA, recurringA], now: today, calendar: calendar, laterInterval: laterInterval)
        precondition(recurrenceTimeline.later.map(OrbitCalendarV2Logic.eventKey) == ["caldav:series:2026-11-10", "caldav:series:2026-11-11"], "distinct recurrence occurrences survive while duplicate occurrence payloads are deduplicated")

        let jan31 = at(2026, 1, 31, 12)
        let febInterval = OrbitCalendarV2Logic.laterInterval(now: jan31, calendar: calendar)!
        precondition(calendar.component(.month, from: febInterval.end) == 2 && calendar.component(.day, from: febInterval.end) == 28, "month horizon uses calendar addition for a short February")
        let leapJan31 = at(2024, 1, 31, 12)
        let leapInterval = OrbitCalendarV2Logic.laterInterval(now: leapJan31, calendar: calendar)!
        precondition(calendar.component(.month, from: leapInterval.end) == 2 && calendar.component(.day, from: leapInterval.end) == 29, "month horizon preserves leap-day calendar arithmetic")
        let monthEndInterval = OrbitCalendarV2Logic.laterInterval(now: at(2026, 10, 31, 12), calendar: calendar)
        precondition(monthEndInterval != nil && monthEndInterval!.end > monthEndInterval!.start, "month-end interval remains ordered across the year/month boundary")
        for zoneName in ["Europe/Kyiv", "America/Los_Angeles"] {
            let zone = TimeZone(identifier: zoneName)!
            let allDayStart = OrbitCalendarV2Logic.localCalendarDate("2026-03-29", timeZone: zone)!
            var localCalendar = Calendar(identifier: .gregorian)
            localCalendar.timeZone = zone
            precondition(localCalendar.component(.day, from: allDayStart) == 29, "date-only all-day start stays on its local day in \(zoneName)")
        }
        precondition(OrbitCalendarV2Logic.localCalendarDate("2026-02-31", timeZone: calendar.timeZone) == nil, "invalid date-only values do not normalize into another month")

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
