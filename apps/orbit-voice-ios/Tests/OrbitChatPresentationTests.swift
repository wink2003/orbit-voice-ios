import Foundation

@main
struct OrbitChatPresentationTests {
    static func main() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Berlin")!
        func d(_ h: Int, _ m: Int, day: Int = 7) -> Date { cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h, minute: m))! }
        let now = d(15, 0)

        precondition(OrbitChatPresentation.displayTitle(kind: "family", title: "x") == "Родинний чат", "family title")
        precondition(OrbitChatPresentation.displayTitle(kind: "orbit", title: "Orbit") == "Мій Orbit", "personal title")
        precondition(OrbitChatPresentation.displayTitle(kind: "orbit", title: "") == "Мій Orbit", "empty title")

        let rows = [
            OrbitChatRowInput(id: "1", senderKey: "me", date: d(9, 0, day: 6)),
            OrbitChatRowInput(id: "2", senderKey: "orbit", date: d(9, 1, day: 6)),
            OrbitChatRowInput(id: "3", senderKey: "me", date: d(10, 0)),
            OrbitChatRowInput(id: "4", senderKey: "me", date: d(10, 2)),
            OrbitChatRowInput(id: "5", senderKey: "me", date: d(10, 30)),
        ]
        let l = OrbitChatPresentation.layout(rows, calendar: cal, now: now)
        precondition(l[0].dateSeparator == "Вчора", "yesterday separator")
        precondition(l[1].dateSeparator == nil, "same day no separator")
        precondition(l[2].dateSeparator == "Сьогодні", "today separator")
        precondition(l[0].startsGroup && l[0].endsGroup, "different sender splits group")
        precondition(l[2].startsGroup && !l[2].endsGroup, "group start")
        precondition(!l[3].startsGroup && l[3].endsGroup, "5 min window then gap > 5 min ends group")
        precondition(l[4].startsGroup && l[4].endsGroup, "gap starts new group")
        precondition(OrbitChatPresentation.layout([], calendar: cal, now: now).isEmpty, "empty")

        let older = OrbitChatPresentation.dayLabel(d(9, 0, day: 1), calendar: cal, now: now)
        precondition(older == "1 жовтня", "same-year label: \(older)")

        precondition(OrbitChatPresentation.matches("Зустріч у ПЯТНИЦЮ", query: "пятницю"), "case-insensitive")
        precondition(OrbitChatPresentation.matches("anything", query: "  "), "blank query matches all")
        precondition(!OrbitChatPresentation.matches("abc", query: "xyz"), "no match")
        print("OrbitChatPresentationTests passed")
    }
}
