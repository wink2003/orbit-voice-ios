import Foundation

@main
struct SchoolRemindersMirrorLogicTests {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) { guard condition() else { fatalError(message) } }
    static func snap(_ title: String, notes: String = "", due: String? = nil, done: Bool = false) -> MirrorSnapshot { MirrorSnapshot(title: title, notes: notes, due: due, done: done) }
    static func task(_ key: String, _ s: MirrorSnapshot, text: Bool = true, due: Bool = true) -> MirrorOrbitTask { MirrorOrbitTask(key: key, snapshot: s, canEditText: text, canEditDue: due) }
    static func rem(_ id: String, _ s: MirrorSnapshot, time: Bool = false) -> MirrorReminder { MirrorReminder(id: id, snapshot: s, hasTime: time) }

    static func main() {
        typealias L = SchoolRemindersMirrorLogic
        let base = snap("Квиток", notes: "до пʼятниці", due: "2026-11-20")
        let link = MirrorLink(key: "t1", reminderId: "r1", base: base)
        let state = MirrorState(links: [link], detached: [])

        // nothing changed on either side: nothing to do
        check(L.plan(orbit: [task("t1", base)], reminders: [rem("r1", base)], state: state).isEmpty, "unchanged pair is a no-op")

        // reminder done in iCloud -> Orbit completes
        let doneReminder = snap("Квиток", notes: "до пʼятниці", due: "2026-11-20", done: true)
        check(L.plan(orbit: [task("t1", base)], reminders: [rem("r1", doneReminder)], state: state) == [.setOrbitDone(key: "t1", done: true)], "done in Reminders completes the task")

        // Orbit title edit -> reminder updated; reminder date edit -> Orbit planning date
        let orbitEdited = snap("Квиток KVB", notes: "до пʼятниці", due: "2026-11-20")
        check(L.plan(orbit: [task("t1", orbitEdited)], reminders: [rem("r1", base)], state: state) == [.updateReminder(key: "t1", reminderId: "r1", snapshot: orbitEdited)], "Orbit edit reaches the reminder")
        let moved = snap("Квиток", notes: "до пʼятниці", due: "2026-11-22")
        check(L.plan(orbit: [task("t1", base)], reminders: [rem("r1", moved)], state: state) == [.updateOrbitTask(key: "t1", title: nil, notes: nil, due: "2026-11-22", dueChanged: true)], "reminder date edit reaches Orbit")

        // both edited the title: Orbit wins; both changed done: done wins
        let both = L.merge(base: base, orbit: task("t1", snap("A", notes: "до пʼятниці", due: "2026-11-20")), reminder: rem("r1", snap("B", notes: "до пʼятниці", due: "2026-11-20")))
        check(both.title == "A", "Orbit wins a title conflict")
        let doneWins = L.merge(base: base, orbit: task("t1", snap("Квиток", notes: "до пʼятниці", due: "2026-11-20", done: true)), reminder: rem("r1", base))
        check(doneWins.done, "done on one side wins")
        let reopenFromReminder = L.merge(base: snap("Квиток", done: true), orbit: task("t1", snap("Квиток", done: true)), reminder: rem("r1", snap("Квиток", done: false)))
        check(!reopenFromReminder.done, "unchecking in Reminders reopens when only the reminder changed")

        // letter task (text not editable): the reminder cannot change the text, Orbit text is restored in the reminder
        let letter = task("src:i:k", snap("Квиток", due: "2026-11-20"), text: false, due: false)
        let letterLink = MirrorLink(key: "src:i:k", reminderId: "r2", base: snap("Квиток", due: "2026-11-20"))
        let plan = L.plan(orbit: [letter], reminders: [rem("r2", snap("Щось інше", due: "2026-11-20"))], state: MirrorState(links: [letterLink], detached: []))
        check(plan == [.updateReminder(key: "src:i:k", reminderId: "r2", snapshot: snap("Квиток", due: "2026-11-20"))], "letter task text is not overwritten from Reminders")

        // reminder deleted in iCloud -> detach, never recreate
        check(L.plan(orbit: [task("t1", base)], reminders: [], state: state) == [.detach(key: "t1")], "deleted reminder detaches")
        check(L.plan(orbit: [task("t1", base)], reminders: [], state: MirrorState(links: [], detached: ["t1"])).isEmpty, "detached task is not recreated")

        // new items on each side; done items are not created / imported
        let created = L.plan(orbit: [task("n1", snap("Нова")), task("n2", snap("Стара", done: true))], reminders: [rem("x1", snap("Купити")), rem("x2", snap("Зроблено", done: true)), rem("x3", snap("  "))], state: MirrorState())
        check(created == [.createReminder(key: "n1", snapshot: snap("Нова")), .createOrbitTask(reminderId: "x1", snapshot: snap("Купити"))], "creates only open, titled items")

        // a task that left the Orbit window keeps its reminder untouched
        check(L.plan(orbit: [], reminders: [rem("r1", base)], state: state).isEmpty, "missing Orbit task leaves the reminder alone")

        // create cap
        let many = (0..<100).map { task("k\($0)", snap("T\($0)")) }
        check(L.plan(orbit: many, reminders: [], state: MirrorState()).count == L.maxCreatesPerRun, "creates are capped per run")
        print("school reminders mirror logic tests passed")
    }
}
