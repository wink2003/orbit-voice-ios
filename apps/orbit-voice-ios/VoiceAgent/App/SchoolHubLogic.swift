import Foundation

nonisolated enum SchoolHubSection: String, CaseIterable, Identifiable {
    case overview, letters, calendar, tasks
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: "Огляд"
        case .letters: "Листи"
        case .calendar: "Календар"
        case .tasks: "Справи"
        }
    }
}

nonisolated enum SchoolEventRelevance: String, CaseIterable, Identifiable {
    case ours, likely, uncertain, unrelated, staffOnly, unclassified
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ours: "Для нас"
        case .likely: "Ймовірно для нас"
        case .uncertain: "Не визначено"
        case .unrelated: "Інші"
        case .staffOnly: "Для працівників"
        case .unclassified: "Без класифікації"
        }
    }
    var systemImage: String {
        switch self {
        case .ours: "checkmark.circle.fill"
        case .likely: "circle.lefthalf.filled"
        case .uncertain: "questionmark.circle"
        case .unrelated: "minus.circle"
        case .staffOnly: "person.badge.key"
        case .unclassified: "circle.dashed"
        }
    }
}

nonisolated enum SchoolEventFilter: String, CaseIterable, Identifiable {
    case all, ours, possible, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "Усі"
        case .ours: "Для нас"
        case .possible: "Можливо"
        case .other: "Інші"
        }
    }
    func includes(_ relevance: SchoolEventRelevance) -> Bool {
        switch self {
        case .all: true
        case .ours: relevance == .ours
        case .possible: relevance == .likely || relevance == .uncertain || relevance == .unclassified
        case .other: relevance == .unrelated || relevance == .staffOnly
        }
    }
}

nonisolated struct SchoolHubEvent: Hashable, Identifiable {
    let uid: String
    let title: String
    let description: String
    let location: String
    let startsAt: String?
    let endsAt: String?
    let allDay: Bool
    let relevanceClass: String?
    let audienceClass: String?
    let relevanceReason: String?
    var id: String { uid }
}

nonisolated struct SchoolHubTask: Hashable, Identifiable {
    let id: String
    let title: String
    let action: String?
    let dueAt: String?
    let allDay: Bool
    let importance: String?
    let target: String?
    let confidence: Double?
    let reason: String?
    let sourceItemId: String
    var kind: String = "source"
    var actionID: String? = nil
    var status: String = "open"
    var planningDate: String? = nil
    var identityStable: Bool = true
}

enum SchoolHubActionError: LocalizedError {
    case unavailable
    case unstableIdentity
    var errorDescription: String? {
        switch self {
        case .unavailable: return "Стан справи ще не доступний у цьому середовищі."
        case .unstableIdentity: return "Справу не можна безпечно синхронізувати: джерело не має стабільного ідентифікатора."
        }
    }
}

enum SchoolActionsCapability: Equatable {
    case unknown
    case available
    case unavailable
    case unauthorized
    case forbidden
    case networkFailure
    case serverFailure

    var canMutate: Bool { self == .available }

    static func fromHTTPStatus(_ status: Int) -> Self {
        switch status {
        case 401: .unauthorized
        case 403: .forbidden
        case 404: .unavailable
        default: .serverFailure
        }
    }

    static func from(error: Error) -> Self {
        if let response = error as? OrbitHTTPResponseFailure {
            return fromHTTPStatus(response.status)
        }
        return error is URLError ? .networkFailure : .serverFailure
    }

    var message: String {
        switch self {
        case .unknown: "Перевіряємо доступність сімейних справ Orbit."
        case .available: ""
        case .unavailable: "Сімейні справи Orbit ще не доступні. Шкільні дані можна переглядати."
        case .unauthorized: "Увійдіть в Orbit, щоб користуватися сімейними справами."
        case .forbidden: "Для цього профілю сімейні справи Orbit недоступні."
        case .networkFailure: "Не вдалося перевірити сімейні справи. Перевірте з’єднання й повторіть."
        case .serverFailure: "Сімейні справи тимчасово недоступні. Спробуйте ще раз пізніше."
        }
    }
}

struct OrbitHTTPResponseFailure: Error, Equatable {
    let status: Int
    let code: String?
}

nonisolated struct SchoolHubLetter: Hashable, Identifiable {
    let id: String
    let type: String
    let title: String
    let sender: String
    let originalText: String
    let translation: String?
    let important: String?
    let unread: Bool
    let date: Date?
}

nonisolated enum SchoolHomePriorityKind: Hashable {
    case task
    case message
    case event
}

/// A bounded, source-linked item for the School Home. This is presentation
/// metadata only; it never changes a School or Orbit record.
nonisolated struct SchoolHomePriority: Hashable, Identifiable {
    let id: String
    let kind: SchoolHomePriorityKind
    let title: String
    let detail: String
    let taskID: String?
    let messageID: String?
    let eventUID: String?
}

nonisolated enum SchoolEvidence: String {
    case sourceRecord
    case interpretation
    case needsVerification

    var title: String {
        switch self {
        case .sourceRecord: "Запис джерела"
        case .interpretation: "Інтерпретація Orbit"
        case .needsVerification: "Потребує перевірки"
        }
    }
    var systemImage: String {
        switch self {
        case .sourceRecord: "checkmark.seal"
        case .interpretation: "sparkles"
        case .needsVerification: "exclamationmark.triangle"
        }
    }
}

nonisolated struct SchoolTaskGroups: Equatable {
    var overdue: [SchoolHubTask] = []
    var dated: [SchoolHubTask] = []
    var undated: [SchoolHubTask] = []
    var undatedOlder: [SchoolHubTask] = []
}

nonisolated struct SchoolTaskSchedule: Equatable {
    var overdue: [SchoolHubTask] = []
    var today: [SchoolHubTask] = []
    var tomorrow: [SchoolHubTask] = []
    var thisWeek: [SchoolHubTask] = []
    var later: [SchoolHubTask] = []
    var undated: [SchoolHubTask] = []
    var undatedOlder: [SchoolHubTask] = []
}

nonisolated enum SchoolTimelineKind: String, Hashable {
    case letter
    case task
    case event

    var title: String {
        switch self {
        case .letter: "Повідомлення"
        case .task: "Справа"
        case .event: "Подія"
        }
    }

    var systemImage: String {
        switch self {
        case .letter: "envelope"
        case .task: "checklist"
        case .event: "calendar"
        }
    }
}

nonisolated struct SchoolTimelineEntry: Hashable, Identifiable {
    let id: String
    let day: String
    let title: String
    let detail: String
    let kind: SchoolTimelineKind
    let sourceItemId: String?
    let eventUID: String?
}

nonisolated enum SchoolHubLogic {
    static let schoolTimeZone = TimeZone(identifier: "Europe/Berlin")!
    static let olderUndatedDays = 14
    static let lowConfidence = 0.6

    static func calendar(_ zone: TimeZone = schoolTimeZone) -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = zone
        value.firstWeekday = 2
        return value
    }

    static func dayKey(of date: Date, zone: TimeZone = schoolTimeZone) -> String {
        let parts = calendar(zone).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func date(fromDayKey key: String, zone: TimeZone = schoolTimeZone) -> Date? {
        let parts = key.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar(zone).date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    static func addDays(_ days: Int, to key: String) -> String? {
        guard let base = date(fromDayKey: key), let moved = calendar().date(byAdding: .day, value: days, to: base) else { return nil }
        return dayKey(of: moved)
    }

    /// Date-only values stay civil dates; instants are converted to the school timezone.
    static func dayKey(for value: String?, allDay: Bool) -> String? {
        guard let value, !value.isEmpty else { return nil }
        if allDay || value.count == 10 { return String(value.prefix(10)) }
        guard let instant = instant(from: value) else { return nil }
        return dayKey(of: instant)
    }

    static func instant(from value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    static func weekDays(containing key: String) -> [String] {
        guard let day = date(fromDayKey: key) else { return [] }
        let cal = calendar()
        let weekday = cal.component(.weekday, from: day)
        let offset = (weekday + 5) % 7
        return (0..<7).compactMap { addDays($0 - offset, to: key) }
    }

    static func relevance(of event: SchoolHubEvent) -> SchoolEventRelevance {
        if event.audienceClass == "STAFF_ONLY" { return .staffOnly }
        switch event.relevanceClass {
        case "DIRECT", "GRADE", "SCHOOLWIDE": return .ours
        case "LIKELY": return .likely
        case "UNCERTAIN": return .uncertain
        case "UNRELATED": return .unrelated
        default: return .unclassified
        }
    }

    static func events(_ events: [SchoolHubEvent], on day: String) -> [SchoolHubEvent] {
        events.filter { event in
            guard let start = dayKey(for: event.startsAt, allDay: event.allDay) else { return false }
            let end = dayKey(for: event.endsAt, allDay: event.allDay) ?? start
            return start <= day && day <= max(start, end)
        }.sorted { ($0.startsAt ?? "") < ($1.startsAt ?? "") }
    }

    static func undatedEvents(_ events: [SchoolHubEvent]) -> [SchoolHubEvent] {
        events.filter { dayKey(for: $0.startsAt, allDay: $0.allDay) == nil }
    }

    static func counts(_ events: [SchoolHubEvent]) -> [SchoolEventRelevance: Int] {
        events.reduce(into: [:]) { $0[relevance(of: $1), default: 0] += 1 }
    }

    static func filter(_ events: [SchoolHubEvent], by filter: SchoolEventFilter) -> [SchoolHubEvent] {
        events.filter { filter.includes(relevance(of: $0)) }
    }

    /// Events that deserve a place in "Tomorrow": everything except explicitly unrelated/staff-only.
    static func isDayRelevant(_ event: SchoolHubEvent) -> Bool {
        let value = relevance(of: event)
        return value != .unrelated && value != .staffOnly
    }

    static func groupTasks(_ tasks: [SchoolHubTask], today: String, sourceDates: [String: Date], now: Date) -> SchoolTaskGroups {
        var groups = SchoolTaskGroups()
        let cutoff = calendar().date(byAdding: .day, value: -olderUndatedDays, to: now) ?? now
        for task in tasks {
            if let due = dayKey(for: task.dueAt, allDay: task.allDay) {
                if due < today { groups.overdue.append(task) } else { groups.dated.append(task) }
            } else if let sourceDate = sourceDates[task.sourceItemId], sourceDate < cutoff {
                groups.undatedOlder.append(task)
            } else {
                groups.undated.append(task)
            }
        }
        let byDue: (SchoolHubTask, SchoolHubTask) -> Bool = { ($0.dueAt ?? "") < ($1.dueAt ?? "") }
        groups.overdue.sort(by: byDue)
        groups.dated.sort(by: byDue)
        return groups
    }

    static func tasks(_ tasks: [SchoolHubTask], dueOn day: String) -> [SchoolHubTask] {
        tasks.filter { dayKey(for: $0.dueAt, allDay: $0.allDay) == day }
    }

    /// A parent-facing chronology. Date-less tasks stay visible and are never assigned a guessed deadline.
    static func scheduleTasks(_ tasks: [SchoolHubTask], today: String, sourceDates: [String: Date], now: Date) -> SchoolTaskSchedule {
        let groups = groupTasks(tasks, today: today, sourceDates: sourceDates, now: now)
        let tomorrow = addDays(1, to: today) ?? today
        let weekEnd = weekDays(containing: today).last ?? today
        var schedule = SchoolTaskSchedule(overdue: groups.overdue, undated: groups.undated, undatedOlder: groups.undatedOlder)
        for task in groups.dated {
            guard let due = dayKey(for: task.dueAt, allDay: task.allDay) else { continue }
            if due == today { schedule.today.append(task) }
            else if due == tomorrow { schedule.tomorrow.append(task) }
            else if due <= weekEnd { schedule.thisWeek.append(task) }
            else { schedule.later.append(task) }
        }
        return schedule
    }

    static func evidence(forEvent event: SchoolHubEvent) -> SchoolEvidence {
        switch relevance(of: event) {
        case .uncertain, .unclassified: .needsVerification
        default: .sourceRecord
        }
    }

    /// Source-verified is never derived from model confidence: a task is at best an
    /// interpretation, and drops to needs-verification without a resolvable source or confidence.
    static func evidence(forTask task: SchoolHubTask, sourceLoaded: Bool, activeNames: [String] = [], sourceText: String = "") -> SchoolEvidence {
        if !sourceLoaded { return .needsVerification }
        guard let confidence = task.confidence, confidence >= lowConfidence else { return .needsVerification }
        if nameConflict(in: sourceText + " " + task.title + " " + (task.action ?? ""), activeNames: activeNames) != nil { return .needsVerification }
        return .interpretation
    }

    private static let confusableNames: [[String]] = [["oleksii", "олексій", "олексий"], ["oleksandr", "олександр", "alexander"]]

    /// Returns the foreign confusable name when the text names one variant but the active profile uses the other.
    static func nameConflict(in text: String, activeNames: [String]) -> String? {
        let lowered = text.lowercased()
        let active = activeNames.map { $0.lowercased() }
        for (index, group) in confusableNames.enumerated() {
            let other = confusableNames[1 - index]
            guard active.contains(where: { name in group.contains { name.contains($0) } }) else { continue }
            if active.contains(where: { name in other.contains { name.contains($0) } }) { continue }
            if let hit = other.first(where: { lowered.contains($0) }) { return hit }
        }
        return nil
    }

    // MARK: Search (client-side, loaded data only)

    static let searchScopeNote = "Пошук лише серед завантажених листів, подій і справ"

    static func matches(_ query: String, in fields: [String?]) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        guard !needle.isEmpty else { return false }
        return fields.contains { ($0 ?? "").folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).contains(needle) }
    }

    static func searchLetters(_ letters: [SchoolHubLetter], query: String) -> [SchoolHubLetter] {
        letters.filter { matches(query, in: [$0.title, $0.sender, $0.originalText, $0.translation, $0.important]) }
    }
    static func searchEvents(_ events: [SchoolHubEvent], query: String) -> [SchoolHubEvent] {
        events.filter { matches(query, in: [$0.title, $0.description, $0.location]) }
    }
    static func searchTasks(_ tasks: [SchoolHubTask], query: String) -> [SchoolHubTask] {
        tasks.filter { matches(query, in: [$0.title, $0.action, $0.reason]) }
    }

    // MARK: Deterministic digest

    struct DigestInput {
        var unreadLetters: Int
        var tomorrowEvents: Int
        var overdueTasks: Int
        var datedTasks: Int
        var undatedTasks: Int
        var unclassifiedEvents: Int
    }

    static func digest(_ input: DigestInput) -> [String] {
        var lines: [String] = []
        if input.unreadLetters > 0 { lines.append("Непрочитаних листів і повідомлень: \(input.unreadLetters)") }
        if input.tomorrowEvents > 0 { lines.append("Подій на завтра: \(input.tomorrowEvents)") }
        if input.overdueTasks > 0 { lines.append("Прострочених справ: \(input.overdueTasks)") }
        if input.datedTasks > 0 { lines.append("Справ з датою: \(input.datedTasks)") }
        if input.undatedTasks > 0 { lines.append("Відкритих справ без дати: \(input.undatedTasks)") }
        if input.unclassifiedEvents > 0 { lines.append("Подій без класифікації: \(input.unclassifiedEvents)") }
        return lines
    }

    // MARK: Preparation (only what the source tasks state, nothing generic)

    static func preparation(for day: String, tasks: [SchoolHubTask]) -> [SchoolHubTask] {
        self.tasks(tasks, dueOn: day).filter { !($0.action ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
    }

    // MARK: School Home

    /// Orders only evidence-backed records that can help a parent decide what
    /// to open next. Family tasks are omitted until their capability is known
    /// to be usable; source-derived tasks remain read-only and visible.
    static func homePriorities(
        tasks: [SchoolHubTask],
        letters: [SchoolHubLetter],
        events: [SchoolHubEvent],
        today: String,
        sourceDates: [String: Date],
        now: Date,
        actionsAvailable: Bool,
        limit: Int = 3
    ) -> [SchoolHomePriority] {
        let usableTasks = tasks.filter { $0.kind != "family" || actionsAvailable }
        let groups = groupTasks(usableTasks, today: today, sourceDates: sourceDates, now: now)
        let horizon = addDays(7, to: today) ?? today
        let dueSoon = groups.dated.filter { task in
            guard let key = dayKey(for: task.dueAt, allDay: task.allDay) else { return false }
            return key <= horizon
        }

        var candidates: [SchoolHomePriority] = []
        for task in groups.overdue {
            candidates.append(priority(for: task, urgency: "Прострочено"))
        }
        for task in dueSoon {
            guard let key = dayKey(for: task.dueAt, allDay: task.allDay) else { continue }
            candidates.append(priority(for: task, urgency: key == today ? "Термін сьогодні" : "Термін: \(key)"))
        }
        for letter in letters
            .filter({ $0.unread && !($0.important ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            .sorted(by: { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }) {
            candidates.append(SchoolHomePriority(
                id: "message:\(letter.id)", kind: .message, title: letter.title.isEmpty ? "Нове повідомлення зі школи" : letter.title,
                detail: letter.sender.isEmpty ? "Нове повідомлення" : "Нове · \(letter.sender)",
                taskID: nil, messageID: letter.id, eventUID: nil
            ))
        }
        let eventHorizon = addDays(3, to: today) ?? today
        for event in homeUpcomingEvents(events, today: today, limit: Int.max) {
            guard let key = dayKey(for: event.startsAt, allDay: event.allDay), key <= eventHorizon else { continue }
            candidates.append(SchoolHomePriority(
                id: "event:\(event.uid)", kind: .event, title: event.title,
                detail: key == today ? "Подія сьогодні" : "Подія: \(key)",
                taskID: nil, messageID: nil, eventUID: event.uid
            ))
        }

        var seen = Set<String>()
        return candidates.filter { seen.insert($0.id).inserted }.prefix(max(0, limit)).map { $0 }
    }

    static func recentUnreadLetters(_ letters: [SchoolHubLetter], limit: Int = 2) -> [SchoolHubLetter] {
        Array(letters.filter(\.unread).sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }.prefix(max(0, limit)))
    }

    /// A duplicate calendar identity can arrive more than once in a source
    /// window. Preserve the original event, but show one representative row.
    /// Different UIDs are never collapsed merely because their titles match.
    static func homeUpcomingEvents(_ events: [SchoolHubEvent], today: String, limit: Int = 3) -> [SchoolHubEvent] {
        let ordered = events
            .filter(isDayRelevant)
            .filter { (dayKey(for: $0.startsAt, allDay: $0.allDay) ?? "9999-12-31") >= today }
            .sorted { ($0.startsAt ?? "") < ($1.startsAt ?? "") }
        var seen = Set<String>()
        return ordered.filter { seen.insert($0.uid).inserted }.prefix(max(0, limit)).map { $0 }
    }

    private static func priority(for task: SchoolHubTask, urgency: String) -> SchoolHomePriority {
        let source = task.kind == "family" ? "Сімейна справа Orbit" : "Schulmanager"
        return SchoolHomePriority(
            id: "task:\(task.id)", kind: .task, title: task.title,
            detail: "\(urgency) · \(source)",
            taskID: task.id, messageID: nil, eventUID: nil
        )
    }

    /// Builds a bounded, source-linked chronology from records already loaded by
    /// the authorized client. It never invents dates for undated records.
    static func timeline(
        letters: [SchoolHubLetter],
        tasks: [SchoolHubTask],
        events: [SchoolHubEvent],
        from: String,
        through: String
    ) -> [SchoolTimelineEntry] {
        var result: [SchoolTimelineEntry] = []
        for letter in letters {
            guard let date = letter.date else { continue }
            let day = dayKey(of: date)
            guard day >= from, day <= through else { continue }
            result.append(SchoolTimelineEntry(
                id: "letter:\(letter.id)", day: day, title: letter.title.isEmpty ? "Шкільне повідомлення" : letter.title,
                detail: letter.sender.isEmpty ? "Оригінал і переклад доступні" : letter.sender,
                kind: .letter, sourceItemId: letter.id, eventUID: nil
            ))
        }
        for task in tasks {
            guard let day = dayKey(for: task.dueAt, allDay: task.allDay), day >= from, day <= through else { continue }
            result.append(SchoolTimelineEntry(
                id: "task:\(task.id)", day: day, title: task.title,
                detail: task.action?.isEmpty == false ? task.action! : "Дія з джерела Schulmanager",
                kind: .task, sourceItemId: task.sourceItemId, eventUID: nil
            ))
        }
        for event in events {
            guard let day = dayKey(for: event.startsAt, allDay: event.allDay), day >= from, day <= through else { continue }
            guard isDayRelevant(event) else { continue }
            result.append(SchoolTimelineEntry(
                id: "event:\(event.uid):\(day)", day: day, title: event.title,
                detail: event.allDay ? "Увесь день" : "Шкільний календар",
                kind: .event, sourceItemId: nil, eventUID: event.uid
            ))
        }
        return result.sorted { lhs, rhs in
            if lhs.day != rhs.day { return lhs.day < rhs.day }
            if lhs.kind == rhs.kind { return lhs.title.localizedCompare(rhs.title) == .orderedAscending }
            return lhs.kind.rawValue < rhs.kind.rawValue
        }
    }
}

/// Profile isolation: data is only valid for the scope it was requested under.
struct SchoolHubLoadGate: Equatable {
    private(set) var scopeKey: String?
    private(set) var generation = 0

    static func scopeKey(personId: String?, impersonating: Bool) -> String {
        "\(personId ?? "-")|\(impersonating ? "imp" : "own")"
    }

    /// Starts a new scope; every outstanding token becomes stale.
    mutating func reset(to key: String) {
        scopeKey = key
        generation += 1
    }

    /// Token for a request started now; nil until a scope is set.
    func token() -> Int? { scopeKey == nil ? nil : generation }

    func accepts(_ token: Int?) -> Bool { token != nil && token == generation }
}
