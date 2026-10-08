import Foundation

private func event(_ uid: String, _ start: String?, end: String? = nil, allDay: Bool = true, cls: String? = nil, audience: String? = nil) -> SchoolHubEvent {
    SchoolHubEvent(uid: uid, title: "E\(uid)", description: "", location: "", startsAt: start, endsAt: end, allDay: allDay, relevanceClass: cls, audienceClass: audience, relevanceReason: nil)
}
private func task(_ id: String, due: String?, confidence: Double? = 0.9, action: String? = "Принести", source: String = "s1") -> SchoolHubTask {
    SchoolHubTask(id: id, title: "T\(id)", action: action, dueAt: due, allDay: true, importance: nil, target: nil, confidence: confidence, reason: nil, sourceItemId: source)
}

@main
struct SchoolHubLogicTests {
    static func main() {
        // Week navigation: 7 days Monday..Sunday
        let week = SchoolHubLogic.weekDays(containing: "2026-10-08")
        precondition(week.count == 7 && week.first == "2026-10-05" && week.last == "2026-10-11")
        precondition(SchoolHubLogic.weekDays(containing: "2026-10-11").first == "2026-10-05")
        precondition(SchoolHubLogic.weekDays(containing: "2026-10-12").first == "2026-10-12")

        // Unknown relevance is counted, kept in "all" and "possible", never silently dropped
        let events = [
            event("a", "2026-10-08", cls: "DIRECT"),
            event("b", "2026-10-08", cls: "LIKELY"),
            event("c", "2026-10-08", cls: nil),
            event("d", "2026-10-08", cls: "SOMETHING_NEW"),
            event("e", "2026-10-08", cls: "UNRELATED"),
            event("f", "2026-10-08", cls: "DIRECT", audience: "STAFF_ONLY"),
            event("g", nil, cls: "UNCERTAIN"),
        ]
        let counts = SchoolHubLogic.counts(events)
        precondition(counts[.unclassified] == 2 && counts[.ours] == 1 && counts[.staffOnly] == 1 && counts[.uncertain] == 1)
        precondition(counts.values.reduce(0, +) == events.count)
        precondition(SchoolHubLogic.filter(events, by: .all).count == events.count)
        precondition(SchoolHubLogic.filter(events, by: .possible).map(\.uid).sorted() == ["b", "c", "d", "g"])
        precondition(SchoolHubLogic.filter(events, by: .ours).map(\.uid) == ["a"])
        precondition(SchoolHubLogic.undatedEvents(events).map(\.uid) == ["g"])
        precondition(SchoolHubLogic.isDayRelevant(events[2]) && !SchoolHubLogic.isDayRelevant(events[4]))
        precondition(SchoolHubLogic.evidence(forEvent: events[2]) == .needsVerification)
        precondition(SchoolHubLogic.evidence(forEvent: events[0]) == .sourceRecord)

        // Multi-day all-day events appear on every day of the span; timed events use school timezone
        let span = event("s", "2026-10-06", end: "2026-10-08")
        precondition(SchoolHubLogic.events([span], on: "2026-10-07").count == 1)
        precondition(SchoolHubLogic.events([span], on: "2026-10-09").isEmpty)
        let lateUTC = event("t", "2026-10-07T22:30:00Z", end: "2026-10-07T23:30:00Z", allDay: false)
        precondition(SchoolHubLogic.events([lateUTC], on: "2026-10-08").count == 1)
        precondition(SchoolHubLogic.events([lateUTC], on: "2026-10-07").isEmpty)

        // Undated tasks are never hidden; old ones are grouped but stay open
        let now = SchoolHubLogic.date(fromDayKey: "2026-10-08")!
        let old = now.addingTimeInterval(-30 * 86400)
        let tasks = [
            task("1", due: "2026-10-07"), task("2", due: "2026-10-09"), task("3", due: nil),
            task("4", due: nil, source: "old"), task("5", due: nil, source: "unknown-date"),
        ]
        let groups = SchoolHubLogic.groupTasks(tasks, today: "2026-10-08", sourceDates: ["old": old, "s1": now], now: now)
        precondition(groups.overdue.map(\.id) == ["1"] && groups.dated.map(\.id) == ["2"])
        precondition(groups.undated.map(\.id) == ["3", "5"] && groups.undatedOlder.map(\.id) == ["4"])
        precondition(groups.overdue.count + groups.dated.count + groups.undated.count + groups.undatedOlder.count == tasks.count)

        // Evidence: never source-verified from confidence; missing source or low confidence needs verification
        precondition(SchoolHubLogic.evidence(forTask: task("x", due: nil, confidence: 0.99), sourceLoaded: true) == .interpretation)
        precondition(SchoolHubLogic.evidence(forTask: task("x", due: nil, confidence: 0.99), sourceLoaded: false) == .needsVerification)
        precondition(SchoolHubLogic.evidence(forTask: task("x", due: nil, confidence: 0.3), sourceLoaded: true) == .needsVerification)
        precondition(SchoolHubLogic.evidence(forTask: task("x", due: nil, confidence: nil), sourceLoaded: true) == .needsVerification)
        precondition(SchoolHubLogic.evidence(forTask: task("x", due: nil), sourceLoaded: true, activeNames: ["Oleksandr"], sourceText: "Oleksii soll Sportzeug mitbringen") == .needsVerification)

        // Oleksii vs Oleksandr
        precondition(SchoolHubLogic.nameConflict(in: "Oleksii bringt", activeNames: ["Oleksandr"]) == "oleksii")
        precondition(SchoolHubLogic.nameConflict(in: "Олександр має", activeNames: ["Олексій"]) == "олександр")
        precondition(SchoolHubLogic.nameConflict(in: "Oleksandr", activeNames: ["Oleksandr"]) == nil)
        precondition(SchoolHubLogic.nameConflict(in: "Oleksii", activeNames: ["Oleksandr", "Oleksii"]) == nil)
        precondition(SchoolHubLogic.nameConflict(in: "Oleksii", activeNames: []) == nil)

        // Search is client-side, case/diacritic-insensitive, and empty query matches nothing
        let letters = [
            SchoolHubLetter(id: "l1", type: "letter", title: "Schwimmen", sender: "Frau Müller", originalText: "Bitte Badesachen", translation: "Принести купальник", important: nil, unread: true, date: nil),
            SchoolHubLetter(id: "l2", type: "message", title: "Info", sender: "", originalText: "Elternabend", translation: nil, important: nil, unread: false, date: nil),
        ]
        precondition(SchoolHubLogic.searchLetters(letters, query: "muller").map(\.id) == ["l1"])
        precondition(SchoolHubLogic.searchLetters(letters, query: "купальник").map(\.id) == ["l1"])
        precondition(SchoolHubLogic.searchLetters(letters, query: "  ").isEmpty)
        precondition(SchoolHubLogic.searchTasks(tasks, query: "T3").map(\.id) == ["3"])
        precondition(SchoolHubLogic.searchScopeNote.contains("завантажених"))

        // Read state is independent of content: unread flag is carried through untouched
        precondition(letters.filter(\.unread).map(\.id) == ["l1"])

        // Digest is deterministic and silent about zero values
        let digest = SchoolHubLogic.digest(.init(unreadLetters: 2, tomorrowEvents: 0, overdueTasks: 1, datedTasks: 0, undatedTasks: 3, unclassifiedEvents: 0))
        precondition(digest == ["Непрочитаних листів і повідомлень: 2", "Прострочених задач: 1", "Відкритих задач без дати: 3"])
        precondition(SchoolHubLogic.digest(.init(unreadLetters: 0, tomorrowEvents: 0, overdueTasks: 0, datedTasks: 0, undatedTasks: 0, unclassifiedEvents: 0)).isEmpty)

        // Preparation only lists explicit task actions due on that day
        let prep = SchoolHubLogic.preparation(for: "2026-10-09", tasks: [task("2", due: "2026-10-09"), task("6", due: "2026-10-09", action: nil), task("7", due: "2026-10-10")])
        precondition(prep.map(\.id) == ["2"])

        // Navigation: exactly four internal sections, no tab-bar duplication
        precondition(SchoolHubSection.allCases.map(\.title) == ["Огляд", "Листи", "Календар", "Задачі"])

        // Profile isolation: scope changes invalidate in-flight work from the previous profile
        let own = SchoolHubLoadGate.scopeKey(personId: "oleksandr", impersonating: false)
        let imp = SchoolHubLoadGate.scopeKey(personId: "viktoriia", impersonating: true)
        let back = SchoolHubLoadGate.scopeKey(personId: "oleksandr", impersonating: false)
        precondition(own != imp && own == back)
        precondition(SchoolHubLoadGate.scopeKey(personId: "x", impersonating: true) != SchoolHubLoadGate.scopeKey(personId: "x", impersonating: false))
        var gate = SchoolHubLoadGate()
        precondition(gate.token() == nil && !gate.accepts(nil), "no loads before a scope is set")
        gate.reset(to: own)
        let ownToken = gate.token()
        precondition(gate.accepts(ownToken))
        gate.reset(to: imp)
        precondition(!gate.accepts(ownToken), "late response from previous profile must be rejected")
        let impToken = gate.token()
        precondition(gate.accepts(impToken) && gate.scopeKey == imp)
        gate.reset(to: back)
        precondition(!gate.accepts(impToken) && !gate.accepts(ownToken), "end of impersonation invalidates impersonated loads and the original token")
        precondition(gate.accepts(gate.token()) && gate.scopeKey == own)

        print("school hub logic tests passed")
    }
}
