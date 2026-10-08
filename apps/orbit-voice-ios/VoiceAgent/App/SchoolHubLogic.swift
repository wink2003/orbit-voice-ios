import Foundation

nonisolated enum SchoolHubSection: String, CaseIterable, Identifiable {
    case overview, letters, calendar, tasks
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: "Огляд"
        case .letters: "Листи"
        case .calendar: "Календар"
        case .tasks: "Задачі"
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
        guard let instant = OrbitSchoolDateDecoding.date(from: value) else { return nil }
        return dayKey(of: instant)
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

    static let searchScopeNote = "Пошук лише серед завантажених листів, подій і задач"

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
        if input.overdueTasks > 0 { lines.append("Прострочених задач: \(input.overdueTasks)") }
        if input.datedTasks > 0 { lines.append("Задач з датою: \(input.datedTasks)") }
        if input.undatedTasks > 0 { lines.append("Відкритих задач без дати: \(input.undatedTasks)") }
        if input.unclassifiedEvents > 0 { lines.append("Подій без класифікації: \(input.unclassifiedEvents)") }
        return lines
    }

    // MARK: Preparation (only what the source tasks state, nothing generic)

    static func preparation(for day: String, tasks: [SchoolHubTask]) -> [SchoolHubTask] {
        self.tasks(tasks, dueOn: day).filter { !($0.action ?? "").trimmingCharacters(in: .whitespaces).isEmpty }
    }
}
