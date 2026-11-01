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
