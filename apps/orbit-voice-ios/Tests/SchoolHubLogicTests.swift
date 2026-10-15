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

        // Parent-facing chronology keeps every open task in exactly one honest bucket.
        let scheduled = SchoolHubLogic.scheduleTasks(
            [task("late", due: "2026-10-07"), task("today", due: "2026-10-08"), task("tomorrow", due: "2026-10-09"), task("week", due: "2026-10-11"), task("later", due: "2026-10-12"), task("none", due: nil)],
            today: "2026-10-08", sourceDates: ["s1": now], now: now
        )
        precondition(scheduled.overdue.map(\.id) == ["late"])
        precondition(scheduled.today.map(\.id) == ["today"])
        precondition(scheduled.tomorrow.map(\.id) == ["tomorrow"])
        precondition(scheduled.thisWeek.map(\.id) == ["week"])
        precondition(scheduled.later.map(\.id) == ["later"])
        precondition(scheduled.undated.map(\.id) == ["none"])

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

        // Source provenance stays honest and does not invent email/calendar identities.
        let letterTask = SchoolHubTask(id: "letter:key", title: "Лист", action: nil, dueAt: nil, allDay: true, importance: nil, target: nil, confidence: nil, reason: nil, sourceItemId: "letter", sourceType: "letter", sourceExternalId: "ext-letter")
        let provenanceFamilyTask = SchoolHubTask(id: "family:id", title: "Сімейна", action: nil, dueAt: nil, allDay: true, importance: nil, target: nil, confidence: nil, reason: nil, sourceItemId: "", kind: "family")
        precondition(letterTask.provenanceLabel == "Schulmanager · Лист")
        precondition(provenanceFamilyTask.provenanceLabel == "Orbit · Сімейна справа")
        let canonicalSource = SchoolHubTask(id: "item123:item123:stable", title: "Стабільна справа", action: nil, dueAt: nil, allDay: true, importance: nil, target: nil, confidence: nil, reason: nil, sourceItemId: "item123")
        precondition(canonicalSource.sourceNoteEntityId == "item123:stable")
        let fallbackSource = SchoolHubTask(id: "item123:stable", title: "Fallback", action: nil, dueAt: nil, allDay: true, importance: nil, target: nil, confidence: nil, reason: nil, sourceItemId: "item123")
        precondition(fallbackSource.sourceNoteEntityId == "item123:stable")

        // Unified chronology keeps source links and never invents dates for undated records.
        let timelineLetters = [
            SchoolHubLetter(id: "letter-1", type: "letter", title: "Поїздка", sender: "Schule", originalText: "Bitte", translation: nil, important: nil, unread: true, date: SchoolHubLogic.date(fromDayKey: "2026-10-09")),
            SchoolHubLetter(id: "letter-2", type: "message", title: "Без дати", sender: "Schule", originalText: "Info", translation: nil, important: nil, unread: false, date: nil),
        ]
        let timeline = SchoolHubLogic.timeline(
            letters: timelineLetters,
            tasks: [task("due", due: "2026-10-10"), task("none", due: nil)],
            events: [event("calendar-1", "2026-10-08", cls: "DIRECT"), event("hidden", "2026-10-08", cls: "UNRELATED")],
            from: "2026-10-08", through: "2026-10-10"
        )
        precondition(timeline.map(\.id) == ["event:calendar-1:2026-10-08", "letter:letter-1", "task:due"])
        precondition(timeline.allSatisfy { $0.sourceItemId != nil || $0.eventUID != nil })

        // Read state is independent of content: unread flag is carried through untouched
        precondition(letters.filter(\.unread).map(\.id) == ["l1"])

        // Digest is deterministic and silent about zero values
        let digest = SchoolHubLogic.digest(.init(unreadLetters: 2, tomorrowEvents: 0, overdueTasks: 1, datedTasks: 0, undatedTasks: 3, unclassifiedEvents: 0))
        precondition(digest == ["Непрочитаних листів і повідомлень: 2", "Прострочених справ: 1", "Відкритих справ без дати: 3"])
        precondition(SchoolHubLogic.digest(.init(unreadLetters: 0, tomorrowEvents: 0, overdueTasks: 0, datedTasks: 0, undatedTasks: 0, unclassifiedEvents: 0)).isEmpty)

        // Preparation only lists explicit task actions due on that day
        let prep = SchoolHubLogic.preparation(for: "2026-10-09", tasks: [task("2", due: "2026-10-09"), task("6", due: "2026-10-09", action: nil), task("7", due: "2026-10-10")])
        precondition(prep.map(\.id) == ["2"])

        // School Home ranks only supported, evidence-backed records.  A family
        // action is not exposed while the actions capability is unavailable.
        var familyTask = task("family", due: "2026-10-06")
        familyTask.kind = "family"
        let homeLetters = [
            SchoolHubLetter(id: "important", type: "letter", title: "Важливе", sender: "Школа", originalText: "", translation: nil, important: "true", unread: true, date: SchoolHubLogic.date(fromDayKey: "2026-10-08")),
            SchoolHubLetter(id: "ordinary", type: "letter", title: "Звичайне", sender: "Школа", originalText: "", translation: nil, important: nil, unread: true, date: SchoolHubLogic.date(fromDayKey: "2026-10-09")),
        ]
        let homeTasks = [familyTask, task("overdue", due: "2026-10-07"), task("soon", due: "2026-10-12")]
        let homeEvents = [event("next", "2026-10-09", cls: "DIRECT")]
        let unavailablePriorities = SchoolHubLogic.homePriorities(
            tasks: homeTasks, letters: homeLetters, events: homeEvents, today: "2026-10-08",
            sourceDates: ["s1": now], now: now, actionsAvailable: false
        )
        precondition(unavailablePriorities.map(\.id) == ["task:overdue", "task:soon", "message:important"])
        precondition(!unavailablePriorities.contains { $0.id == "task:family" })
        let availablePriorities = SchoolHubLogic.homePriorities(
            tasks: homeTasks, letters: homeLetters, events: homeEvents, today: "2026-10-08",
            sourceDates: ["s1": now], now: now, actionsAvailable: true, limit: 5
        )
        precondition(Array(availablePriorities.map(\.id).prefix(2)) == ["task:family", "task:overdue"])
        precondition(availablePriorities.first?.detail.contains("Сімейна справа Orbit") == true)
        precondition(availablePriorities.contains { $0.id == "event:next" })

        // Home previews keep the newest unread messages and order calendar
        // records chronologically without multiplying one calendar identity.
        precondition(SchoolHubLogic.recentUnreadLetters(homeLetters, limit: 1).map(\.id) == ["ordinary"])
        let sameTitleDifferentUID = SchoolHubEvent(uid: "same-title-different-uid", title: "Evacation", description: "", location: "", startsAt: "2026-10-11", endsAt: nil, allDay: true, relevanceClass: "DIRECT", audienceClass: nil, relevanceReason: nil)
        let repeatedCalendar = [
            event("vacation", "2026-10-09", end: "2026-10-16", cls: "DIRECT"),
            event("vacation", "2026-10-10", end: "2026-10-16", cls: "DIRECT"),
            sameTitleDifferentUID,
        ]
        precondition(SchoolHubLogic.homeUpcomingEvents(repeatedCalendar, today: "2026-10-08").map(\.uid) == ["vacation", "same-title-different-uid"])

        // Navigation: exactly four internal sections, no tab-bar duplication
        precondition(SchoolHubSection.allCases.map(\.title) == ["Огляд", "Листи", "Календар", "Справи"])

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

        // School Actions capability is fail-closed and keeps auth failures distinct.
        precondition(!SchoolActionsCapability.unknown.canMutate)
        precondition(!SchoolActionsCapability.unavailable.canMutate)
        precondition(SchoolActionsCapability.fromHTTPStatus(404) == .unavailable)
        precondition(SchoolActionsCapability.fromHTTPStatus(401) == .unauthorized)
        precondition(SchoolActionsCapability.fromHTTPStatus(403) == .forbidden)
        precondition(SchoolActionsCapability.fromHTTPStatus(503) == .serverFailure)
        precondition(SchoolActionsCapability.from(error: URLError(.notConnectedToInternet)) == .networkFailure)
        precondition(SchoolActionsCapability.from(error: OrbitHTTPResponseFailure(status: 404, code: "not_found")) == .unavailable)
        precondition(SchoolActionsCapability.available.canMutate)

        // Completion changes are confirmation-gated before the store mutation.
        precondition(SchoolTaskStatusConfirmation(completed: false).title == "Позначити справу виконаною?")
        precondition(SchoolTaskStatusConfirmation(completed: false).actionTitle == "Так, виконано")
        precondition(SchoolTaskStatusConfirmation(completed: true).title == "Повернути справу у відкриті?")
        precondition(SchoolTaskStatusConfirmation(completed: true).actionTitle == "Повернути")

        // School Tasks v2: sections, filters and one definition of "open".
        do {
            func t(_ id: String, due: String?, status: String = "open", source: String = "s1", key: String? = nil) -> SchoolHubTask {
                var value = task(id, due: due, source: source)
                value.status = status
                return value
            }
            let now = Date()
            let today = "2026-10-13"
            let tasks = [
                t("overdue", due: "2026-10-01"),
                t("ancient", due: "2026-01-01"),
                t("soon", due: "2026-10-20"),
                t("edge", due: "2026-10-27"),
                t("later", due: "2026-12-01"),
                t("undated", due: nil),
                t("done", due: "2026-10-05", status: "completed"),
                t("doneUndated", due: nil, status: "completed"),
                t("weekOpen", due: "2026-10-12"),
                t("weekDone", due: "2026-10-18", status: "completed"),
            ]
            let counts = SchoolHubLogic.taskCounts(tasks)
            precondition(counts.open == 7 && counts.completed == 3 && counts.all == 10)
            let open = SchoolHubLogic.taskSections(tasks, filter: .open, today: today, sourceDates: [:], now: now)
            precondition(open.thisWeek.map(\.id) == ["weekOpen"])
            precondition(open.dated.map(\.id) == ["ancient", "overdue", "soon", "edge", "later"])
            precondition(open.undated.map(\.id) == ["undated"] && open.undatedOlder.isEmpty)
            precondition(open.visibleCount == counts.open, "open filter shows exactly the open count")
            let done = SchoolHubLogic.taskSections(tasks, filter: .completed, today: today, sourceDates: [:], now: now)
            precondition(done.thisWeek.map(\.id) == ["weekDone"])
            precondition(done.dated.map(\.id) == ["done"] && done.undated.map(\.id) == ["doneUndated"] && done.visibleCount == counts.completed)
            let every = SchoolHubLogic.taskSections(tasks, filter: .all, today: today, sourceDates: [:], now: now)
            precondition(every.visibleCount == counts.all)
            precondition(every.thisWeek.map(\.id) == ["weekOpen", "weekDone"])
            precondition(every.dated.map(\.id) == ["ancient", "overdue", "done", "soon", "edge", "later"])
            precondition(Set(every.thisWeek + every.dated + every.undated + every.undatedOlder).count == counts.all)
            // Monday/Sunday boundaries, year boundary, DST conversion and stable ties.
            precondition(SchoolHubLogic.weekDays(containing: "2026-01-01") == ["2025-12-29", "2025-12-30", "2025-12-31", "2026-01-01", "2026-01-02", "2026-01-03", "2026-01-04"])
            precondition(SchoolHubLogic.dayKey(for: "2026-10-24T22:30:00Z", allDay: false) == "2026-10-25")
            let tied = [t("z", due: "2026-10-13"), t("a", due: "2026-10-13")]
            precondition(SchoolHubLogic.taskSections(tied, filter: .all, today: today, sourceDates: [:], now: now).thisWeek.map(\.id) == ["a", "z"])
            // equal titles from different sources stay separate rows
            let twins = [t("a", due: nil, source: "s1"), t("b", due: nil, source: "s2")]
            precondition(SchoolHubLogic.taskSections(twins, filter: .open, today: today, sourceDates: [:], now: now).undated.count == 2)
            // the user-facing count follows the search subset, not a hidden total
            precondition(SchoolHubLogic.taskCounts(SchoolHubLogic.searchTasks(tasks, query: "Tsoon")).open == 1)

            // calendar prefill: known deadline pre-fills, undated requires user choice
            precondition(SchoolHubLogic.calendarPrefillDay(for: t("x", due: "2026-10-20")) == "2026-10-20")
            precondition(SchoolHubLogic.calendarPrefillDay(for: t("x", due: nil)) == nil)

            // completion key matches the source completion API (`<itemId>:<taskKey>`)
            let keyed = SchoolHubTask(id: "item1:item1:form", title: "T", action: nil, dueAt: nil, allDay: true, importance: "high", target: nil, confidence: 1, reason: nil, sourceItemId: "item1")
            precondition(keyed.sourceTaskKey == "item1:form" && keyed.isHighPriority && keyed.canAddToCalendar)
            var family = keyed; family.kind = "family"
            precondition(!family.canAddToCalendar)
            var unstable = keyed; unstable.identityStable = false
            precondition(!unstable.canAddToCalendar)
        }

        print("school hub logic tests passed")
    }
}
