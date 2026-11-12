import Foundation

nonisolated enum SchoolTranslatedBody {
    /// Keeps source line breaks and list markers intact while exposing paragraph spacing to the view.
    static func paragraphs(from text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .filter { !$0.isEmpty }
    }
}

nonisolated enum SchoolTaskStatusConfirmation: Equatable {
    case complete, reopen

    init(completed: Bool) { self = completed ? .reopen : .complete }

    var title: String {
        switch self {
        case .complete: "Позначити справу виконаною?"
        case .reopen: "Повернути справу у відкриті?"
        }
    }

    var actionTitle: String {
        switch self {
        case .complete: "Так, виконано"
        case .reopen: "Повернути"
        }
    }
}

nonisolated enum SchoolChecklistMatching {
    /// A checklist is visible only when at least one real task identity is
    /// supplied and that identity matches the server record. In particular,
    /// absent IDs must never match another absent ID (`nil == nil`).
    static func matches(
        checklistSourceItemId: String?,
        checklistSourceTaskId: String?,
        sourceItemId: String?,
        sourceTaskId: String?
    ) -> Bool {
        let itemId = sourceItemId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let taskId = sourceTaskId?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard itemId?.isEmpty == false || taskId?.isEmpty == false else { return false }
        return (itemId != nil && checklistSourceItemId == itemId) ||
            (taskId != nil && checklistSourceTaskId == taskId)
    }
}

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

nonisolated enum SchoolInboxFilter: String, CaseIterable, Identifiable, Hashable {
    case all, unread, actionable

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "Усі"
        case .unread: "Нові"
        case .actionable: "Дії"
        }
    }
}

nonisolated enum SchoolInboxTypeFilter: String, CaseIterable, Identifiable, Hashable {
    case all, letters, messages

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "Усі типи"
        case .letters: "Листи"
        case .messages: "Повідомлення"
        }
    }
}

nonisolated struct SchoolInboxActionSummary: Equatable {
    let itemIDs: Set<String>
    let coverageComplete: Bool

    var count: Int? { coverageComplete ? itemIDs.count : nil }
}

nonisolated struct SchoolInboxItemSnapshot: Hashable, Identifiable {
    let id: String
    let type: String
    let title: String
    let sender: String
    let preview: String
    /// Search-only aggregate retaining source text that may not be shown as the preview.
    let searchText: String
    let unread: Bool
    let date: Date?
}

nonisolated struct SchoolInboxTaskSnapshot: Hashable {
    let sourceItemId: String
    let status: String
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
    var sourceType: String? = nil
    var sourceExternalId: String? = nil
    var kind: String = "source"
    var actionID: String? = nil
    var status: String = "open"
    var planningDate: String? = nil
    /// School deadline kept aside when `dueAt` is replaced by the family's planned date.
    var schoolDueAt: String? = nil
    var schoolDueAllDay: Bool = true
    var identityStable: Bool = true
    var calendarEventId: String? = nil
    var effectiveDueAt: String? = nil
    var effectiveDueDateOrigin: String? = nil
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
    /// The list is readable (e.g. via a family read grant) but this profile may not change it (child / read-only profile).
    case readOnly

    var canMutate: Bool { self == .available }

    /// Definite answers from the server (not signed in / forbidden / not available) always apply; a transient
    /// network/server failure keeps an already established capability (available / readOnly) instead of revoking it.
    static func afterFailure(current: Self, error next: Self) -> Self {
        switch next {
        case .unauthorized, .forbidden, .unavailable: return next
        default: return (current == .available || current == .readOnly) ? current : next
        }
    }

    /// After a successful read: writes are offered only when the effective permissions allow School writes.
    static func afterReadSucceeded(canWrite: Bool) -> Self { canWrite ? .available : .readOnly }

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
        case .readOnly: "Цей профіль лише переглядає справи. Змінювати їх можуть дорослі члени родини."
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
    static let interfaceLocale = Locale(identifier: "uk_UA")
    static let schoolTimeZone = TimeZone(identifier: "Europe/Berlin")!
    static let olderUndatedDays = 14
    static let lowConfidence = 0.6

    static func calendar(_ zone: TimeZone = schoolTimeZone) -> Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = zone
        value.firstWeekday = 2
        return value
    }

    /// Actionability is communication-level, not task-level: one letter with
    /// three open extracted tasks still contributes one actionable item.
    /// The count is intentionally unknown when the server did not provide a
    /// complete all-coverage task response.
    static func inboxActionSummary(itemIDs: Set<String>, tasks: [SchoolInboxTaskSnapshot], coverageComplete: Bool) -> SchoolInboxActionSummary {
        let openItemIDs = Set(tasks.filter { $0.status != "completed" && !$0.sourceItemId.isEmpty }.map { $0.sourceItemId })
        return SchoolInboxActionSummary(itemIDs: itemIDs.intersection(openItemIDs), coverageComplete: coverageComplete)
    }

    static func filterInboxItemIDs(
        _ items: [SchoolInboxItemSnapshot],
        filter: SchoolInboxFilter,
        typeFilter: SchoolInboxTypeFilter,
        query: String,
        actionSummary: SchoolInboxActionSummary
    ) -> [String] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter { item in
            let typeMatches: Bool = switch typeFilter {
            case .all: true
            case .letters: item.type == "letter"
            case .messages: item.type == "message"
            }
            guard typeMatches else { return false }

            let mainMatches: Bool = switch filter {
            case .all: true
            case .unread: item.unread
            case .actionable: actionSummary.itemIDs.contains(item.id)
            }
            guard mainMatches else { return false }
            guard !normalizedQuery.isEmpty else { return true }
            return item.searchText.localizedStandardContains(normalizedQuery)
        }
        .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        .map { $0.id }
    }

    static func dayKey(of date: Date, zone: TimeZone = schoolTimeZone) -> String {
        let parts = calendar(zone).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func date(fromDayKey key: String, zone: TimeZone = schoolTimeZone) -> Date? {
        let parts = key.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let value = calendar(zone)
        guard let date = value.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)),
              value.component(.year, from: date) == parts[0],
              value.component(.month, from: date) == parts[1],
              value.component(.day, from: date) == parts[2] else { return nil }
        return date
    }

    static func localizedLongDay(_ key: String, locale: Locale = interfaceLocale) -> String? {
        guard let date = date(fromDayKey: key) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = schoolTimeZone
        formatter.dateFormat = "EEEE, d MMMM"
        return formatter.string(from: date)
    }

    /// Month label for a selected Monday–Friday school week. Months are
    /// localized; years are included when the displayed days cross a year.
    static func timetableMonthLabel(dayKeys: [String], locale: Locale = interfaceLocale) -> String? {
        let dates = dayKeys.compactMap { date(fromDayKey: $0) }
        guard !dates.isEmpty else { return nil }
        var formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = schoolTimeZone
        formatter.dateFormat = "LLLL"
        let parts = dates.map { date -> (month: Int, year: Int, name: String) in
            let components = calendar().dateComponents([.year, .month], from: date)
            return (components.month ?? 0, components.year ?? 0, formatter.string(from: date))
        }
        var unique: [(month: Int, year: Int, name: String)] = []
        for part in parts where !unique.contains(where: { $0.month == part.month && $0.year == part.year }) {
            unique.append(part)
        }
        guard let first = unique.first else { return nil }
        if unique.count == 1 { return first.name }
        let crossesYear = Set(unique.map { $0.year }).count > 1
        return unique.map { crossesYear ? "\($0.name) \($0.year)" : $0.name }.joined(separator: " / ")
    }

    static func schoolDayPrecedes(_ lhs: String, _ rhs: String) -> Bool {
        switch (date(fromDayKey: lhs), date(fromDayKey: rhs)) {
        case let (left?, right?) where left != right: return left < right
        case (_?, nil): return true
        case (nil, _?): return false
        default: return lhs < rhs
        }
    }

    static func timetableGridHeight(rowHeights: [CGFloat], headerHeight: CGFloat = 40, rowSpacing: CGFloat = 6) -> CGFloat {
        headerHeight + rowHeights.reduce(0) { $0 + $1 + rowSpacing }
    }

    static func timetableColumnWidth(totalWidth: CGFloat, axisWidth: CGFloat = 22, gap: CGFloat = 3, horizontalInset: CGFloat = 16, columns: Int = 5) -> CGFloat {
        guard columns > 0 else { return 0 }
        return max(0, floor((totalWidth - horizontalInset * 2 - axisWidth - gap * CGFloat(columns)) / CGFloat(columns)))
    }

    static func timetableEntries<Entry>(_ entries: [Entry], weekStart: String, localDate: (Entry) -> String) -> [Entry] {
        let weekdays = Set((0..<5).compactMap { addDays($0, to: weekStart) })
        return entries.filter { weekdays.contains(localDate($0)) }
    }

    static func timetableCoverageState(_ coverageState: String?, responseState: String, entryCount: Int) -> String {
        if coverageState == "READY_EMPTY", entryCount > 0 { return "PARTIAL" }
        if let coverageState, coverageState != "READY" { return coverageState }
        guard coverageState == "READY" || responseState == "READY" else { return coverageState ?? responseState }
        return entryCount == 0 ? "READY_EMPTY" : "READY_WITH_DATA"
    }

    static func chronologicalExams<Exam>(_ exams: [Exam], dayKey: (Exam) -> String, id: (Exam) -> String) -> [Exam] {
        exams.sorted {
            let leftDay = dayKey($0)
            let rightDay = dayKey($1)
            if leftDay != rightDay { return schoolDayPrecedes(leftDay, rightDay) }
            return id($0) < id($1)
        }
    }

    static func addDays(_ days: Int, to key: String) -> String? {
        guard let base = date(fromDayKey: key), let moved = calendar().date(byAdding: .day, value: days, to: base) else { return nil }
        return dayKey(of: moved)
    }

    /// The school API rejects any window longer than 31 days (`invalid_school_window`),
    /// so longer horizons are requested as consecutive windows of at most `chunk` days.
    static func windows(from start: String, days: Int, chunk: Int = 28) -> [(from: String, to: String)] {
        var result: [(from: String, to: String)] = []
        var offset = 0
        while offset < days {
            let length = min(chunk, days - offset)
            guard let from = addDays(offset, to: start), let to = addDays(offset + length, to: start) else { break }
            result.append((from, to))
            offset += length
        }
        return result
    }

    /// Each argument is nil on success, else the HTTP status (0 for a non-HTTP failure).
    /// The whole hub fails only for auth problems or when every endpoint failed; otherwise sections with data stay usable.
    static func isHubWideFailure(overview: Int?, exams: Int?, timetable: Int?) -> Bool {
        let all = [overview, exams, timetable]
        if all.contains(where: { $0 == 401 || $0 == 403 }) { return true }
        return all.allSatisfy { $0 != nil }
    }

    static func daysBetween(_ from: String, _ to: String) -> Int {
        guard let a = date(fromDayKey: from), let b = date(fromDayKey: to) else { return 0 }
        return calendar().dateComponents([.day], from: a, to: b).day ?? 0
    }

    /// Compact timetable label; the full subject stays available in details and accessibility text.
    static func subjectAbbreviation(_ subject: String) -> String {
        let words = subject.split(whereSeparator: { $0.isWhitespace || $0 == "/" || $0 == "-" }).map(String.init)
        guard !words.isEmpty else { return "—" }
        if words.count > 1 { return String(words.prefix(3).compactMap(\.first)).uppercased() }
        let word = words[0]
        return word.count <= 4 ? word : String(word.prefix(3))
    }

    static func isoWeek(of key: String) -> String {
        guard let date = date(fromDayKey: key) else { return "—" }
        var value = Calendar(identifier: .iso8601)
        value.timeZone = schoolTimeZone
        return String(format: "%04d-W%02d", value.component(.yearForWeekOfYear, from: date), value.component(.weekOfYear, from: date))
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

    /// A newer load supersedes every outstanding token of the same scope.
    mutating func advance() { if scopeKey != nil { generation += 1 } }
}


// MARK: - School Tasks v2 (list sections, filters, counts)

nonisolated enum SchoolTaskFilter: String, CaseIterable, Identifiable {
    case open, completed, all
    var id: String { rawValue }
    var title: String {
        switch self {
        case .open: "Відкриті"
        case .completed: "Виконані"
        case .all: "Усі"
        }
    }
}

nonisolated struct SchoolTaskDueMeta: Equatable { let day: String?; let fromLetter: Bool; let overdue: Bool }

nonisolated struct SchoolTaskSections: Equatable {
    var overdue: [SchoolHubTask] = []
    var thisWeek: [SchoolHubTask] = []
    var nextWeek: [SchoolHubTask] = []
    var later: [SchoolHubTask] = []

    var laterOpen: [SchoolHubTask] { later.filter { $0.status != "completed" } }
    var laterCompleted: [SchoolHubTask] { later.filter { $0.status == "completed" } }

    var visibleCount: Int { overdue.count + thisWeek.count + nextWeek.count + later.count }
}

nonisolated struct SchoolTaskCounts: Equatable {
    var open = 0
    var completed = 0
    var all: Int { open + completed }
}

extension SchoolHubLogic {
    static let soonDays = 14
    static let overdueOlderDays = 60

    static func isCompleted(_ task: SchoolHubTask) -> Bool { task.status == "completed" }

    /// The single definition of "open" used by the Tasks screen and the School Home count.
    static func taskCounts(_ tasks: [SchoolHubTask]) -> SchoolTaskCounts {
        var counts = SchoolTaskCounts()
        for task in tasks { if isCompleted(task) { counts.completed += 1 } else { counts.open += 1 } }
        return counts
    }

    /// Presentation fallback until the backend returns an explicit effective due date.
    /// A source date is not silently treated as an original school deadline.
    static func effectiveTaskDay(_ task: SchoolHubTask, sourceDates: [String: Date]) -> String? {
        if let authoritative = task.effectiveDueAt { return authoritative }
        if task.effectiveDueDateOrigin == "unavailable" { return nil }
        if let due = dayKey(for: task.dueAt, allDay: task.allDay) { return due }
        guard task.kind == "source", let sourceDate = sourceDates[task.sourceItemId] else { return nil }
        return dayKey(of: sourceDate)
    }

    /// Civil day of a letter event: all-day events are calendar dates (UTC), timed events use the school time zone.
    static func eventDayKey(startsAt: Date?, allDay: Bool) -> String? {
        guard let startsAt else { return nil }
        if !allDay { return dayKey(of: startsAt) }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let parts = utc.dateComponents([.year, .month, .day], from: startsAt)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Tasks of the same letter whose SCHOOL deadline falls on the event's civil day ("Дати / дедлайни" <-> "Що потрібно").
    /// Matches on the original deadline, so a family-planned date does not break the link; no deadline => no link.
    static func linkedTasks(eventDay: String?, sourceItemId: String, tasks: [SchoolHubTask]) -> [SchoolHubTask] {
        guard let eventDay else { return [] }
        return tasks.filter { task in
            guard task.sourceItemId == sourceItemId else { return false }
            let deadline = task.schoolDueAt ?? task.dueAt
            return dayKey(for: deadline, allDay: task.schoolDueAt != nil ? task.schoolDueAllDay : task.allDay) == eventDay
        }
    }

    /// Same-letter fallback match by normalised title; ambiguous (several equal titles) => nil.
    static func matchByTitle(title: String?, among tasks: [SchoolHubTask]) -> SchoolHubTask? {
        func norm(_ s: String) -> String { s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }
        guard let title, !norm(title).isEmpty else { return nil }
        let hits = tasks.filter { norm($0.title) == norm(title) }
        return hits.count == 1 ? hits[0] : nil
    }

    /// What a task row shows about its date: the authoritative effective day, whether it came from the letter, and overdue state.
    static func dueMeta(_ task: SchoolHubTask, today: String, sourceDates: [String: Date]) -> SchoolTaskDueMeta {
        let day = effectiveTaskDay(task, sourceDates: sourceDates)
        return SchoolTaskDueMeta(day: day, fromLetter: usesSourceDate(task, sourceDates: sourceDates), overdue: !isCompleted(task) && (day.map { $0 < today } ?? false))
    }

    static func usesSourceDate(_ task: SchoolHubTask, sourceDates: [String: Date]) -> Bool {
        task.effectiveDueDateOrigin == "source_letter" || (task.effectiveDueDateOrigin == nil && task.dueAt == nil && task.kind == "source" && sourceDates[task.sourceItemId] != nil)
    }

    static func taskSections(_ tasks: [SchoolHubTask], filter: SchoolTaskFilter, today: String, sourceDates: [String: Date], now: Date) -> SchoolTaskSections {
        var sections = SchoolTaskSections()
        let visible = tasks.filter { task in
            filter == .all || (filter == .completed ? isCompleted(task) : !isCompleted(task))
        }
        let currentWeek = Set(weekDays(containing: today))
        // Derived from the same `today` civil day as every other bucket (never from the device clock), so grouping is deterministic.
        let nextWeek = Set(weekDays(containing: addDays(7, to: today) ?? today))

        for task in visible {
            guard let due = effectiveTaskDay(task, sourceDates: sourceDates) else {
                // Never drop a record if the backend has not provided a date yet.
                sections.later.append(task)
                continue
            }
            if !isCompleted(task) && due < today {
                sections.overdue.append(task)
            } else if currentWeek.contains(due) {
                sections.thisWeek.append(task)
            } else if nextWeek.contains(due) {
                sections.nextWeek.append(task)
            } else {
                sections.later.append(task)
            }
        }
        func ordered(_ a: SchoolHubTask, _ b: SchoolHubTask) -> Bool {
            let da = effectiveTaskDay(a, sourceDates: sourceDates) ?? "9999-99-99"
            let db = effectiveTaskDay(b, sourceDates: sourceDates) ?? "9999-99-99"
            if da != db { return da < db }
            return a.id < b.id
        }
        sections.overdue.sort(by: ordered)
        sections.thisWeek.sort(by: ordered)
        sections.nextWeek.sort(by: ordered)
        sections.later.sort(by: ordered)
        return sections
    }

    /// A known deadline pre-fills the calendar date (explained as a deadline).
    /// Undated tasks return nil: the user must choose a date.
    static func calendarPrefillDay(for task: SchoolHubTask) -> String? {
        dayKey(for: task.dueAt, allDay: task.allDay)
    }
    /// Exact "HH:mm" of a timed deadline, read literally as written by the school source (the Brain labels
    /// wall-clock times "...Z", e.g. "з 09:00" -> 09:00Z, so converting the instant would shift it by the UTC offset).
    /// nil for all-day, date-only or midnight (ambiguous) values.
    static func calendarPrefillTime(for task: SchoolHubTask) -> String? {
        guard !task.allDay, let value = task.dueAt else { return nil }
        return literalTimeKey(value)
    }

    static func literalTimeKey(_ value: String) -> String? {
        guard value.count > 10, let t = value.firstIndex(of: "T") else { return nil }
        let rest = value[value.index(after: t)...]
        let parts = rest.prefix(5).split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]), (0..<24).contains(h), (0..<60).contains(m), h != 0 || m != 0 else { return nil }
        return String(format: "%02d:%02d", h, m)
    }

    static func minutes(fromTimeKey key: String) -> Int? {
        let parts = key.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]), (0..<24).contains(h), (0..<60).contains(m) else { return nil }
        return h * 60 + m
    }
}

extension SchoolHubTask {
    /// Key as understood by the School Actions / calendar-proposal APIs (`<itemId>:<taskKey>`).
    var sourceTaskKey: String {
        sourceItemId.isEmpty ? id : (id.hasPrefix("\(sourceItemId):") ? String(id.dropFirst(sourceItemId.count + 1)) : id)
    }
    /// Canonical note identity: exactly one source item prefix, matching `/api/school/tasks`.
    var sourceNoteEntityId: String? {
        guard kind == "source", identityStable, !sourceItemId.isEmpty else { return nil }
        let key = sourceTaskKey
        guard !key.isEmpty else { return nil }
        return key.hasPrefix("\(sourceItemId):") ? key : "\(sourceItemId):\(key)"
    }
    var isHighPriority: Bool {
        guard let value = importance?.lowercased() else { return false }
        return ["high", "important", "critical", "urgent", "високий", "важливо", "важливий"].contains(value)
    }
    /// Calendar creation needs a server-resolvable source task with a stable identity.
    var canAddToCalendar: Bool { kind == "source" && identityStable && !sourceItemId.isEmpty }

    var provenanceLabel: String {
        if kind == "family" { return "Orbit · Сімейна справа" }
        switch (sourceType ?? "").lowercased() {
        case "letter", "schulmanager_letter": return "Schulmanager · Лист"
        case "message", "schulmanager_message": return "Schulmanager · Повідомлення"
        case "calendar", "schulmanager_calendar": return "Schulmanager · Календар"
        case "orbit_family", "family": return "Orbit · Сімейна справа"
        default: return "Schulmanager · Джерело"
        }
    }
}

/// Honest Ukrainian copy for a School item whose translation is not (yet) available.
/// Pure and testable; the German original is never altered.
enum SchoolTranslationPlaceholder {
    static func isPending(translation: String?, status: String?) -> Bool {
        hasText(translation) == false && (status == nil || status == "pending")
    }
    static func message(translation: String?, status: String?) -> String? {
        if hasText(translation) { return nil }
        switch status {
        case "pending": return "Переклад готується. Він з’явиться тут автоматично — або перегляньте німецький оригінал."
        case "body_pending": return "Текст листа ще не отримано зі Schulmanager — лист там не відкрито. Переклад з’явиться після завантаження тексту; німецький заголовок збережено."
        case "failed": return "Не вдалося підготувати переклад. Перегляньте німецький оригінал."
        case "original_only": return "У цьому листі немає тексту для перекладу."
        default: return "Переклад наразі недоступний. Перейдіть до німецького оригіналу."
        }
    }
    private static func hasText(_ value: String?) -> Bool {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
}

/// ROUTES 05 task status filter. `defaultFilter` is applied on every entry.
nonisolated enum Routes05TaskFilter: CaseIterable, Identifiable {
    case all, open, completed
    static let defaultFilter: Routes05TaskFilter = .all
    var id: Self { self }
    var title: String { self == .all ? "Всі" : self == .open ? "Відкриті" : "Завершені" }
    func count(_ counts: SchoolTaskCounts) -> Int { self == .all ? counts.all : self == .open ? counts.open : counts.completed }
}

/// Where a School item's original lives in Schulmanager. Orbit stores only
/// attachment metadata (no file bytes, no download URLs), so attachments fall back
/// to the original letter/thread in Schulmanager.
///
/// Routes come from the Schulmanager web app's own router (hash routing; states
/// `main.modules.letters.view.details` = `/modules/letters/view/view/:id` and
/// `main.modules.messenger.messages.thread` = `/modules/messenger/messages/:subscriptionId`).
/// Verified from the public app bundle only; opening it on a device is unverified.
nonisolated enum OrbitSchoolSourceLink {
    static let schulmanagerHome = URL(string: "https://login.schulmanager-online.de/")!
    private static func isNumericID(_ value: String?) -> Bool {
        guard let value, !value.isEmpty, value.count <= 32 else { return false }
        return value.allSatisfy { $0 >= "0" && $0 <= "9" }
    }
    static func url(source: String, type: String = "", externalId: String? = nil, subscriptionId: String? = nil) -> URL? {
        guard source.lowercased() == "schulmanager" else { return nil }
        let base = "https://login.schulmanager-online.de/#"
        switch type.lowercased() {
        case "letter" where isNumericID(externalId):
            return URL(string: "\(base)/modules/letters/view/view/\(externalId!)")
        case "message" where isNumericID(subscriptionId):
            return URL(string: "\(base)/modules/messenger/messages/\(subscriptionId!)")
        default:
            return schulmanagerHome
        }
    }
}

extension SchoolHubLogic {
    /// `YYYY-MM-DD` of an API planning date (`2026-11-18` or `2026-11-18T00:00:00.000Z`), nil if it is not a real day.
    static func planningDayKey(_ raw: String?) -> String? {
        guard let raw, raw.count >= 10 else { return nil }
        let key = String(raw.prefix(10))
        return date(fromDayKey: key) != nil ? key : nil
    }

    /// The family's planned date (Orbit-owned) overrides the due date used for grouping and overdue logic;
    /// the school's own deadline is preserved in `schoolDueAt`.
    static func effectiveDue(dueAt: String?, allDay: Bool, planningDate: String?) -> (dueAt: String?, allDay: Bool, schoolDueAt: String?, schoolAllDay: Bool) {
        guard let key = planningDayKey(planningDate) else { return (dueAt, allDay, nil, allDay) }
        return (key, true, dueAt, allDay)
    }
}

extension SchoolHubTask {
    /// The school's own deadline (read-only), regardless of any family planned date.
    var schoolDeadlineAt: String? {
        SchoolHubLogic.planningDayKey(planningDate) == nil ? dueAt : schoolDueAt
    }
    var schoolDeadlineAllDay: Bool {
        SchoolHubLogic.planningDayKey(planningDate) == nil ? allDay : schoolDueAllDay
    }
    var planningDayKey: String? { SchoolHubLogic.planningDayKey(planningDate) }
}


enum SchoolHubErrors {
    /// URLSession reports a cancelled request as URLError(.cancelled), not CancellationError: both mean "superseded", never "failed".
    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let url = error as? URLError, url.code == .cancelled { return true }
        let ns = error as NSError
        return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
    }
}

extension SchoolHubLogic {
    /// After a failed re-read of family actions: keep showing the last confirmed list unless the server gave a definite refusal.
    static func keepsLastActionList(after failure: SchoolActionsCapability, loadedOnce: Bool) -> Bool {
        loadedOnce && (failure == .networkFailure || failure == .serverFailure)
    }
}
