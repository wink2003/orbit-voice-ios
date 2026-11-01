import XCTest
@testable import VoiceAgent

final class OrbitCalendarV2LogicTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.firstWeekday = 2
        value.timeZone = TimeZone(identifier: "Europe/Kyiv")!
        return value
    }

    private func event(_ id: String, source: String = "family", start: Date, end: Date) -> OrbitCalendarEvent {
        OrbitCalendarEvent(id: id, familyId: "family", ownerPersonId: "person", title: id, notes: "", startsAt: start, endsAt: end, allDay: false, sourceType: "external", sourceIdentifier: source, sourceName: source, sourceColor: nil, createdAt: nil, updatedAt: nil)
    }

    func testMonthGridIsMondayFirstAndAlwaysSixWeeks() {
        let date = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))!
        let grid = OrbitCalendarV2Logic.monthGrid(for: date, calendar: calendar)
        XCTAssertEqual(grid.count, 42)
        XCTAssertEqual(calendar.component(.weekday, from: grid[0]), 2)
        XCTAssertEqual(calendar.component(.day, from: grid[1]), 27)
    }

    func testOccurrencesIncludeAllDayAndMultiDayBoundary() {
        let day = calendar.date(from: DateComponents(year: 2026, month: 3, day: 29))!
        let start = calendar.date(byAdding: .day, value: -1, to: day)!
        let end = calendar.date(byAdding: .day, value: 2, to: day)!
        XCTAssertTrue(OrbitCalendarV2Logic.occurs(event("multi", start: start, end: end), on: day, calendar: calendar))
        XCTAssertTrue(OrbitCalendarV2Logic.occurs(event("all-day", start: day, end: calendar.date(byAdding: .day, value: 1, to: day)!), on: day, calendar: calendar))
    }

    func testNextFiveIsIndependentOfOrderAndDeduplicatesBySourceIdentity() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let first = event("same", source: "a", start: now.addingTimeInterval(600), end: now.addingTimeInterval(1200))
        let duplicate = event("same", source: "a", start: now.addingTimeInterval(600), end: now.addingTimeInterval(1200))
        let later = (1...6).map { offset in
            event("e\(offset)", source: "b", start: now.addingTimeInterval(Double(offset) * 3600), end: now.addingTimeInterval(Double(offset) * 3600 + 600))
        }
        let result = OrbitCalendarV2Logic.nextFive([later[5], duplicate, later[1], first, later[0], later[2], later[3], later[4]], now: now)
        XCTAssertEqual(result.count, 5)
        XCTAssertEqual(result.first?.id, "same")
        XCTAssertEqual(result.dropFirst().map(\.id), ["e1", "e2", "e3", "e4"])
    }
}
