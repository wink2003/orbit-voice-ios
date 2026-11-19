import Foundation

// Two-way mirror of the School tasks and the iCloud Reminders list «Школа» (owner request 2026-11-19).
// This file is pure (Foundation only, no EventKit, no network): it decides WHAT to change on each side. The EventKit and API side effects live in
// SchoolRemindersMirror.swift. Rules, kept deliberately conservative:
//  - a task/reminder pair is compared with the snapshot saved after the previous sync (`base`): only the side that changed wins;
//  - both sides changed the same field: Orbit wins, except `done`, where "done" wins (a finished chore must not silently reopen);
//  - a reminder deleted in iCloud only DETACHES the task (it is never deleted in Orbit and is not recreated);
//  - fields Orbit cannot edit (a letter task has no editable text) always keep the Orbit value;
//  - Orbit tasks that are already done are not created as reminders; done reminders without a mapping are not imported.

struct MirrorSnapshot: Codable, Equatable, Hashable {
    var title: String
    var notes: String
    /// Calendar day `yyyy-MM-dd` or nil. Orbit tasks carry a day only; a time set in Reminders is kept on the reminder (see `MirrorReminder.hasTime`).
    var due: String?
    var done: Bool
}

struct MirrorOrbitTask: Equatable {
    let key: String                 // action task id, or `src:<sourceItemId>:<taskKey>` for a letter task that has no action row yet
    var snapshot: MirrorSnapshot
    let canEditText: Bool           // false for letter tasks without an action row
    let canEditDue: Bool
}

struct MirrorReminder: Equatable {
    let id: String                  // EKReminder.calendarItemIdentifier
    var snapshot: MirrorSnapshot
    let hasTime: Bool               // a time of day is set; a day-only comparison must not wipe it
}

struct MirrorLink: Codable, Equatable {
    let key: String
    var reminderId: String
    var base: MirrorSnapshot
}

struct MirrorState: Codable, Equatable {
    /// 2 = tasks assembled exactly like the School Hub list (coverage «all», source tasks keyed `src:<item>:<key>`). 0/1 = first release.
    static let currentVersion = 2
    var links: [MirrorLink] = []
    /// Keys whose reminder the user deleted in iCloud: never recreated.
    var detached: [String] = []
    var version: Int = 0

    init(links: [MirrorLink] = [], detached: [String] = [], version: Int = 0) { self.links = links; self.detached = detached; self.version = version }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        links = try c.decodeIfPresent([MirrorLink].self, forKey: .links) ?? []
        detached = try c.decodeIfPresent([String].self, forKey: .detached) ?? []
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 0
    }
}

enum MirrorAction: Equatable {
    case createReminder(key: String, snapshot: MirrorSnapshot)
    case updateReminder(key: String, reminderId: String, snapshot: MirrorSnapshot)
    case createOrbitTask(reminderId: String, snapshot: MirrorSnapshot)
    case updateOrbitTask(key: String, title: String?, notes: String?, due: String?, dueChanged: Bool)
    case setOrbitDone(key: String, done: Bool)
    case detach(key: String)
}

enum SchoolRemindersMirrorLogic {
    /// Upper bound of reminders created in one run (a first sync of a long list must not flood the list or the API).
    static let maxCreatesPerRun = 60

    private static func pick<T: Equatable>(base: T, orbit: T, reminder: T) -> T {
        if orbit == reminder { return orbit }
        let orbitChanged = orbit != base, reminderChanged = reminder != base
        if reminderChanged && !orbitChanged { return reminder }
        return orbit                                    // Orbit changed (or both did): Orbit wins
    }

    /// Merge of one linked pair. `done` is the only field where both-changed resolves to "done".
    static func merge(base: MirrorSnapshot, orbit: MirrorOrbitTask, reminder: MirrorReminder) -> MirrorSnapshot {
        let o = orbit.snapshot, r = reminder.snapshot
        var title = pick(base: base.title, orbit: o.title, reminder: r.title)
        var notes = pick(base: base.notes, orbit: o.notes, reminder: r.notes)
        var due = pick(base: base.due, orbit: o.due, reminder: r.due)
        if !orbit.canEditText { title = o.title; notes = o.notes }
        if !orbit.canEditDue { due = o.due }
        var done = pick(base: base.done, orbit: o.done, reminder: r.done)
        if o.done != base.done && r.done != base.done { done = o.done || r.done }
        return MirrorSnapshot(title: title, notes: notes, due: due, done: done)
    }

    static func plan(orbit: [MirrorOrbitTask], reminders: [MirrorReminder], state: MirrorState) -> [MirrorAction] {
        var actions: [MirrorAction] = []
        let orbitByKey = Dictionary(orbit.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let reminderById = Dictionary(reminders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let linkedKeys = Set(state.links.map(\.key))
        let linkedReminderIds = Set(state.links.map(\.reminderId))
        let detached = Set(state.detached)
        var creates = 0

        for link in state.links {
            guard let task = orbitByKey[link.key] else { continue }          // the task left the Orbit window: keep the reminder untouched
            guard let reminder = reminderById[link.reminderId] else {        // the user deleted the reminder in iCloud
                actions.append(.detach(key: link.key)); continue
            }
            let merged = merge(base: link.base, orbit: task, reminder: reminder)
            if merged.done != task.snapshot.done { actions.append(.setOrbitDone(key: link.key, done: merged.done)) }
            let titleChanged = task.canEditText && merged.title != task.snapshot.title
            let notesChanged = task.canEditText && merged.notes != task.snapshot.notes
            let dueChanged = task.canEditDue && merged.due != task.snapshot.due
            if titleChanged || notesChanged || dueChanged {
                actions.append(.updateOrbitTask(key: link.key, title: titleChanged ? merged.title : nil, notes: notesChanged ? merged.notes : nil, due: merged.due, dueChanged: dueChanged))
            }
            // A reminder with a time keeps it when the day is unchanged, so the day-only snapshots are compared.
            if merged != reminder.snapshot { actions.append(.updateReminder(key: link.key, reminderId: link.reminderId, snapshot: merged)) }
        }

        for task in orbit where !linkedKeys.contains(task.key) && !detached.contains(task.key) && !task.snapshot.done {
            guard creates < maxCreatesPerRun else { break }
            creates += 1
            actions.append(.createReminder(key: task.key, snapshot: task.snapshot))
        }
        for reminder in reminders where !linkedReminderIds.contains(reminder.id) && !reminder.snapshot.done {
            guard creates < maxCreatesPerRun else { break }
            let title = reminder.snapshot.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            creates += 1
            actions.append(.createOrbitTask(reminderId: reminder.id, snapshot: reminder.snapshot))
        }
        return actions
    }

    /// The link base after a pair was merged (what both sides should look like now).
    static func updatedLink(_ link: MirrorLink, merged: MirrorSnapshot) -> MirrorLink { MirrorLink(key: link.key, reminderId: link.reminderId, base: merged) }
}
