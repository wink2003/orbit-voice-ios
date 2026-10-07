import Foundation

@main
struct OrbitTodayLogicTests {
    static func main() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Berlin")!
        func d(_ h: Int, _ m: Int = 0, day: Int = 7) -> Date { cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h, minute: m))! }
        let today = d(12)

        precondition(OrbitTodayLogic.overlapsDay(start: d(9), end: d(10), day: today, calendar: cal), "inside today")
        precondition(!OrbitTodayLogic.overlapsDay(start: d(9, day: 8), end: d(10, day: 8), day: today, calendar: cal), "tomorrow")
        precondition(!OrbitTodayLogic.overlapsDay(start: d(9, day: 6), end: d(10, day: 6), day: today, calendar: cal), "yesterday")
        precondition(OrbitTodayLogic.overlapsDay(start: d(22, day: 6), end: d(2, day: 7), day: today, calendar: cal), "overnight spills into today")
        precondition(!OrbitTodayLogic.overlapsDay(start: d(20, day: 6), end: d(0, day: 7), day: today, calendar: cal), "ends exactly at midnight")
        precondition(OrbitTodayLogic.overlapsDay(start: d(0, day: 7), end: d(0, day: 8), day: today, calendar: cal), "all-day today")
        precondition(OrbitTodayLogic.overlapsDay(start: d(9), end: d(9), day: today, calendar: cal), "zero-length event")

        precondition(OrbitTodayLogic.greeting(hour: 8, name: "Олександр") == "Доброго ранку, Олександр", "morning")
        precondition(OrbitTodayLogic.greeting(hour: 14, name: nil) == "Доброго дня", "no name")
        precondition(OrbitTodayLogic.greeting(hour: 20, name: "  ") == "Доброго вечора", "blank name")
        precondition(OrbitTodayLogic.greeting(hour: 2, name: nil) == "Доброї ночі", "night")

        precondition(OrbitTodayLogic.unreadLabel(0) == "Нових шкільних матеріалів немає", "0")
        precondition(OrbitTodayLogic.unreadLabel(1) == "1 нове шкільне повідомлення", "1")
        precondition(OrbitTodayLogic.unreadLabel(3) == "3 нові шкільні повідомлення", "3")
        precondition(OrbitTodayLogic.unreadLabel(11) == "11 нових шкільних повідомлень", "11")
        precondition(OrbitTodayLogic.unreadLabel(21) == "21 нове шкільне повідомлення", "21")
        precondition(OrbitTodayLogic.unreadLabel(12) == "12 нових шкільних повідомлень", "12")
        print("OrbitTodayLogicTests passed")
    }
}
