import Foundation
import UserNotifications

struct OrbitSchoolEvent: Decodable, Identifiable, Hashable {
    let key: String
    let title: String
    let startsAt: Date?
    let endsAt: Date?
    let allDay: Bool
    let location: String?
    var id: String { key }

    private enum CodingKeys: String, CodingKey { case key, title, startsAt, endsAt, allDay, location }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        title = try container.decode(String.self, forKey: .title)
        allDay = try container.decode(Bool.self, forKey: .allDay)
        location = try container.decodeIfPresent(String.self, forKey: .location)
        startsAt = try Self.decodeDate(container, forKey: .startsAt)
        endsAt = try Self.decodeDate(container, forKey: .endsAt)
    }

    private static func decodeDate(_ container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Date? {
        guard let value = try container.decodeIfPresent(String.self, forKey: key) else { return nil }
        guard let date = OrbitSchoolDateDecoding.date(from: value) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "Unsupported School event date format")
        }
        return date
    }
}
struct OrbitSchoolItem: Decodable, Identifiable, Hashable {
    let id: String; let type: String; let source: String; let externalId: String; let title: String; let sender: String
    let originalGerman: String; let originalPlainText: String?; let previewPlainText: String?; let titlePlainText: String?; let translationUkrainian: String?; let important: String?; let sourceTimestamp: Date?; let importedAt: Date?
    let orbitReadAt: Date?; let unread: Bool; let attachments: [OrbitSchoolAttachment]; let events: [OrbitSchoolEvent]; let threadId: String?; let subscriptionId: String?
    let tasks: [OrbitSchoolItemTask]?
    // Additive, backend-provided: ready | pending | failed | original_only. Absent on older backends.
    var translationStatus: String? = nil
    // Additive, backend-provided Ukrainian rendering of `title`. Absent on older backends or before translation.
    var titleUkrainian: String? = nil
}
extension OrbitSchoolItem {
    private static func nonBlank(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
    /// German plain-text title, exactly as received (never altered).
    var germanTitle: String { Self.nonBlank(titlePlainText) ?? title }
    /// Ukrainian title when the backend provides one, otherwise the German original.
    var displayTitle: String { Self.nonBlank(titleUkrainian) ?? germanTitle }
    /// The German original, shown as a caption only when a different Ukrainian title is displayed.
    var germanTitleCaption: String? { Self.nonBlank(titleUkrainian) != nil && germanTitle != displayTitle && !germanTitle.isEmpty ? germanTitle : nil }
}
struct OrbitSchoolItemTask: Decodable, Hashable { let key: String?; let title: String?; let action: String?; let dueAt: String?; let allDay: Bool?; let importance: String?; let target: String?; let confidence: Double?; let reason: String? }
struct OrbitSchoolAttachment: Decodable, Hashable {
    let id: String?
    let filename: String
    let contentType: String?
    let inline: Bool?
    // Present only when the source provides a safe downloadable URL.
    let url: String?
    let downloadURL: String?
    // Additive, backend-provided (migration 072/078). The translation text is only in the item DETAIL payload.
    var readStatus: String? = nil
    var translationStatus: String? = nil      // pending | ready | failed
    var translationChars: Int? = nil
    var translation: String? = nil
}
struct OrbitSchoolItemsResponse: Decodable { let items: [OrbitSchoolItem]; let unreadCount: Int }
struct OrbitSchulmanagerCalendarEvent: Decodable, Identifiable, Hashable { let uid: String; let title: String; let description: String; let location: String; let startsAt: String?; let endsAt: String?; let allDay: Bool; let timeZone: String?; let recurrenceRule: String?; let relevanceClass: String?; let audienceClass: String?; let relevanceReason: String?; var id: String { uid } }
struct OrbitSchoolTask: Decodable, Identifiable, Hashable { let key: String; let stableIdentity: Bool?; let title: String; let action: String?; let dueAt: String?; let endsAt: String?; let allDay: Bool; let importance: String?; let target: String?; let confidence: Double?; let reason: String?; let location: String?; let sourceItemId: String; let sourceType: String; let sourceExternalId: String; let bucket: String?; let status: String?; let completedAt: String?; let actionTaskId: String?; let calendarEventId: String?; let effectiveDueAt: String?; let effectiveDueDateOrigin: String?; let group: String?; var id: String { key.hasPrefix("\(sourceItemId):") ? key : "\(sourceItemId):\(key)" } }
struct OrbitSchulmanagerCalendarResponse: Decodable { let events: [OrbitSchulmanagerCalendarEvent] }
struct OrbitSchoolTasksResponse: Decodable { let from: String; let to: String; let coverage: String?; let truncated: Bool?; let complete: Bool?; let completionState: String?; let tasks: [OrbitSchoolTask]; let importantEvents: [OrbitSchulmanagerCalendarEvent] }

private extension KeyedDecodingContainer {
    /// Decodes the two School Hub lesson-hour fields emitted by the backend.
    /// The deployed serializer preserves the database text type, so both JSON
    /// integers and canonical integer strings are valid. Other representations
    /// remain decoding errors rather than being silently treated as nil.
    func decodeStrictOptionalInt(forKey key: Key) throws -> Int? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        if let value = try? decode(Int.self, forKey: key) { return value }
        let string = try decode(String.self, forKey: key)
        guard !string.isEmpty, let value = Int(string) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Expected an integer or integer string")
        }
        return value
    }
}

struct OrbitSchoolHubV2Freshness: Decodable, Hashable {
    let state: String
    let sourceStates: [String: String]
    let observedAt: Date?
    let source: String?
    let fingerprint: String?
}
struct OrbitSchoolHubV2Coverage: Decodable, Hashable {
    let state: String
    let rowCount: Int?
    let sourceStatus: String?
    let sourceFingerprint: String?
    let successfulSyncAt: Date?
    let observedAt: Date?
    let errorCode: String?
    let startDayKey: String?
    let endDayKey: String?
}
struct OrbitSchoolHubV2Overview: Decodable, Hashable {
    let state: String
    let freshness: OrbitSchoolHubV2Freshness
    let sourceStates: [String: String]
    let profileTitle: String?
    let todayDayKey: String?
    let upcomingExams: [OrbitSchoolHubV2Exam]
    let projects: [OrbitSchoolHubV2Project]
    let coverage: [String: OrbitSchoolHubV2Coverage]?
    let schoolClass: String?

    private enum CodingKeys: String, CodingKey {
        case state, freshness, sourceStates, profileTitle, todayDayKey, upcomingExams, projects, coverage
        case studentClass, schoolClass, className, school_class
    }

    init(state: String, freshness: OrbitSchoolHubV2Freshness, sourceStates: [String: String], profileTitle: String?, todayDayKey: String?, upcomingExams: [OrbitSchoolHubV2Exam], projects: [OrbitSchoolHubV2Project], coverage: [String: OrbitSchoolHubV2Coverage]?, schoolClass: String? = nil) {
        self.state = state; self.freshness = freshness; self.sourceStates = sourceStates; self.profileTitle = profileTitle; self.todayDayKey = todayDayKey; self.upcomingExams = upcomingExams; self.projects = projects; self.coverage = coverage; self.schoolClass = schoolClass
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        state = try c.decode(String.self, forKey: .state)
        freshness = try c.decode(OrbitSchoolHubV2Freshness.self, forKey: .freshness)
        sourceStates = try c.decode([String: String].self, forKey: .sourceStates)
        profileTitle = try c.decodeIfPresent(String.self, forKey: .profileTitle)
        todayDayKey = try c.decodeIfPresent(String.self, forKey: .todayDayKey)
        upcomingExams = try c.decode([OrbitSchoolHubV2Exam].self, forKey: .upcomingExams)
        projects = try c.decode([OrbitSchoolHubV2Project].self, forKey: .projects)
        coverage = try c.decodeIfPresent([String: OrbitSchoolHubV2Coverage].self, forKey: .coverage)
        schoolClass = [
            try c.decodeIfPresent(String.self, forKey: .studentClass),
            try c.decodeIfPresent(String.self, forKey: .schoolClass),
            try c.decodeIfPresent(String.self, forKey: .className),
            try c.decodeIfPresent(String.self, forKey: .school_class)
        ].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}
struct OrbitSchoolHubV2OverviewResponse: Decodable { let overview: OrbitSchoolHubV2Overview }
struct OrbitSchoolHubV2Exam: Decodable, Identifiable, Hashable {
    let id: String
    let subject: String
    let dayKey: String
    let lessonStart: Int?
    let lessonEnd: Int?
    let startsAt: String?
    let room: String?
    let teacher: String?
    let group: String?
    let groupName: String?
    let startClassHourNumber: Int?
    let typeName: String?
    let typeColor: String?
    let typeVisibleForStudents: Bool?
    let comment: String?
    let status: String?
    let source: String?
    let sourceFingerprint: String?
    let observedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id, subject, dayKey, lessonStart, lessonEnd, startsAt, room, teacher, group, groupName,
             startClassHourNumber, typeName, typeColor, typeVisibleForStudents, comment, status,
             source, sourceFingerprint, observedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        subject = try container.decode(String.self, forKey: .subject)
        dayKey = try container.decode(String.self, forKey: .dayKey)
        lessonStart = try container.decodeIfPresent(Int.self, forKey: .lessonStart)
        lessonEnd = try container.decodeIfPresent(Int.self, forKey: .lessonEnd)
        startsAt = try container.decodeIfPresent(String.self, forKey: .startsAt)
        room = try container.decodeIfPresent(String.self, forKey: .room)
        teacher = try container.decodeIfPresent(String.self, forKey: .teacher)
        group = try container.decodeIfPresent(String.self, forKey: .group)
        groupName = try container.decodeIfPresent(String.self, forKey: .groupName)
        startClassHourNumber = try container.decodeStrictOptionalInt(forKey: .startClassHourNumber)
        typeName = try container.decodeIfPresent(String.self, forKey: .typeName)
        typeColor = try container.decodeIfPresent(String.self, forKey: .typeColor)
        typeVisibleForStudents = try container.decodeIfPresent(Bool.self, forKey: .typeVisibleForStudents)
        comment = try container.decodeIfPresent(String.self, forKey: .comment)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        sourceFingerprint = try container.decodeIfPresent(String.self, forKey: .sourceFingerprint)
        observedAt = try container.decodeIfPresent(Date.self, forKey: .observedAt)
    }
}
struct OrbitSchoolHubV2ExamsResponse: Decodable { let state: String; let freshness: OrbitSchoolHubV2Freshness; let coverage: OrbitSchoolHubV2Coverage?; let from: String; let to: String; let exams: [OrbitSchoolHubV2Exam] }
struct OrbitSchoolHubV2Project: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let status: String?
    let leader: String?
    let meeting: String?
    let location: String?
    let fromDayKey: String?
    let toDayKey: String?
    let relatedCalendarEventID: String?
    let observedAt: Date?
}
struct OrbitSchoolHubV2TimetableEntry: Decodable, Identifiable, Hashable {
    let id: String
    let dayKey: String
    let localDate: String
    let lessonIndex: Int
    let subject: String
    let teacher: String?
    let room: String?
    let group: String?
    let groupName: String?
    let startsAt: String?
    let endsAt: String?
    let startsAtLocal: String?
    let endsAtLocal: String?
    let classHourNumber: Int?
    let isCancelled: Bool
    let originalLessonCount: Int
    let teachers: [OrbitSchoolHubV2Teacher]
    let groups: [OrbitSchoolHubV2Group]
    let status: String?
    let kind: String?
    let source: String?
    let sourceFingerprint: String?
    let observedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case id, dayKey, localDate, lessonIndex, subject, teacher, room, group, groupName,
             startsAt, endsAt, startsAtLocal, endsAtLocal, classHourNumber, isCancelled,
             originalLessonCount, teachers, groups, status, kind, source, sourceFingerprint, observedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        dayKey = try container.decode(String.self, forKey: .dayKey)
        localDate = try container.decode(String.self, forKey: .localDate)
        lessonIndex = try container.decode(Int.self, forKey: .lessonIndex)
        subject = try container.decode(String.self, forKey: .subject)
        teacher = try container.decodeIfPresent(String.self, forKey: .teacher)
        room = try container.decodeIfPresent(String.self, forKey: .room)
        group = try container.decodeIfPresent(String.self, forKey: .group)
        groupName = try container.decodeIfPresent(String.self, forKey: .groupName)
        startsAt = try container.decodeIfPresent(String.self, forKey: .startsAt)
        endsAt = try container.decodeIfPresent(String.self, forKey: .endsAt)
        startsAtLocal = try container.decodeIfPresent(String.self, forKey: .startsAtLocal)
        endsAtLocal = try container.decodeIfPresent(String.self, forKey: .endsAtLocal)
        classHourNumber = try container.decodeStrictOptionalInt(forKey: .classHourNumber)
        isCancelled = try container.decode(Bool.self, forKey: .isCancelled)
        originalLessonCount = try container.decode(Int.self, forKey: .originalLessonCount)
        teachers = try container.decode([OrbitSchoolHubV2Teacher].self, forKey: .teachers)
        groups = try container.decode([OrbitSchoolHubV2Group].self, forKey: .groups)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        sourceFingerprint = try container.decodeIfPresent(String.self, forKey: .sourceFingerprint)
        observedAt = try container.decodeIfPresent(Date.self, forKey: .observedAt)
    }
}
struct OrbitSchoolHubV2Teacher: Decodable, Hashable { let abbreviation: String? }
struct OrbitSchoolHubV2Group: Decodable, Hashable { let name: String? }
struct OrbitSchoolHubV2Timetable: Decodable, Hashable {
    let state: String
    let freshness: OrbitSchoolHubV2Freshness
    let startDayKey: String
    let entries: [OrbitSchoolHubV2TimetableEntry]
    let coverage: OrbitSchoolHubV2Coverage?
}
struct OrbitSchoolHubV2TimetableResponse: Decodable { let timetable: OrbitSchoolHubV2Timetable }
#if DEBUG
extension OrbitSchoolHubV2Exam {
    init(id: String, subject: String, dayKey: String, lessonStart: Int?, lessonEnd: Int?, startsAt: String?, room: String?, teacher: String?, group: String?, groupName: String?, startClassHourNumber: Int?, typeName: String?, typeColor: String?, typeVisibleForStudents: Bool?, comment: String?, status: String?, source: String?, sourceFingerprint: String?, observedAt: Date?) {
        self.id = id; self.subject = subject; self.dayKey = dayKey; self.lessonStart = lessonStart; self.lessonEnd = lessonEnd; self.startsAt = startsAt; self.room = room; self.teacher = teacher; self.group = group; self.groupName = groupName; self.startClassHourNumber = startClassHourNumber; self.typeName = typeName; self.typeColor = typeColor; self.typeVisibleForStudents = typeVisibleForStudents; self.comment = comment; self.status = status; self.source = source; self.sourceFingerprint = sourceFingerprint; self.observedAt = observedAt
    }
}

extension OrbitSchoolHubV2TimetableEntry {
    init(id: String, dayKey: String, localDate: String, lessonIndex: Int, subject: String, teacher: String?, room: String?, group: String?, groupName: String?, startsAt: String?, endsAt: String?, startsAtLocal: String?, endsAtLocal: String?, classHourNumber: Int?, isCancelled: Bool, originalLessonCount: Int, teachers: [OrbitSchoolHubV2Teacher], groups: [OrbitSchoolHubV2Group], status: String?, kind: String?, source: String?, sourceFingerprint: String?, observedAt: Date?) {
        self.id = id; self.dayKey = dayKey; self.localDate = localDate; self.lessonIndex = lessonIndex; self.subject = subject; self.teacher = teacher; self.room = room; self.group = group; self.groupName = groupName; self.startsAt = startsAt; self.endsAt = endsAt; self.startsAtLocal = startsAtLocal; self.endsAtLocal = endsAtLocal; self.classHourNumber = classHourNumber; self.isCancelled = isCancelled; self.originalLessonCount = originalLessonCount; self.teachers = teachers; self.groups = groups; self.status = status; self.kind = kind; self.source = source; self.sourceFingerprint = sourceFingerprint; self.observedAt = observedAt
    }
}
#endif
struct OrbitSchoolActionTask: Codable, Identifiable, Hashable {
    let id: String
    let kind: String
    var title: String
    var description: String
    let sourceItemId: String?
    let sourceTaskKey: String?
    let sourceEventUid: String?
    let schoolDueAt: String?
    var planningDate: String?
    var status: String
    let createdByPersonId: String
    let completedByPersonId: String?
    let completedAt: Date?
    let revision: Int
    let createdAt: Date
    let updatedAt: Date
}
struct OrbitSchoolActionTasksResponse: Decodable { let tasks: [OrbitSchoolActionTask] }
struct OrbitSchoolActionChecklistItem: Codable, Identifiable, Hashable {
    let id: String
    var title: String
    let sourceKind: String
    let completedAt: Date?
    let completedByPersonId: String?
    let archivedAt: Date?
    let revision: Int
    let position: Int
    let createdAt: Date
    let updatedAt: Date
}
struct OrbitSchoolActionChecklist: Codable, Identifiable, Hashable {
    let id: String
    var title: String
    let sourceItemId: String?
    let sourceTaskId: String?
    let sourceEventUid: String?
    let archivedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let revision: Int
    var items: [OrbitSchoolActionChecklistItem]
}
struct OrbitSchoolActionChecklistsResponse: Decodable { let checklists: [OrbitSchoolActionChecklist] }
struct OrbitSchoolActionNote: Codable, Identifiable, Hashable {
    let id: String
    let entityType: String
    let entityId: String
    var content: String
    let createdByPersonId: String
    let updatedByPersonId: String
    let createdAt: Date
    let updatedAt: Date
    let revision: Int
    let clientRequestId: String?
}
struct OrbitSchoolActionNotesResponse: Decodable { let notes: [OrbitSchoolActionNote] }
struct OrbitSchoolActionHistoryEntry: Decodable, Identifiable, Hashable {
    let id: String
    let entityType: String
    let entityId: String
    let action: String
    let actorPersonId: String
    let metadata: String?
    let createdAt: Date
}
struct OrbitSchoolActionHistoryResponse: Decodable { let history: [OrbitSchoolActionHistoryEntry] }
struct OrbitSchoolBrainConversationResponse: Decodable { let conversation: OrbitSchoolBrainConversation; let messages: [OrbitSchoolBrainMessage] }
struct OrbitSchoolBrainConversation: Decodable { let id: String; let title: String; let createdAt: Date; let updatedAt: Date }

struct OrbitFamilyMessage: Decodable, Identifiable {
    let id: String
    let familyId: String
    let senderPersonId: String
    let senderDisplayName: String
    let content: String
    let createdAt: Date
}

struct OrbitFamilyProfile: Decodable, Identifiable {
    let personId: String
    let displayName: String
    let isMinor: Bool
    var id: String { personId }
}

/// What the signed-in person may do with one provider event (server decides; the UI only reflects it).
struct OrbitCalendarCapabilities: Codable, Hashable { let edit: [String]; let delete: Bool }
struct OrbitCalendarOrganizer: Codable, Hashable { let personId: String?; let external: Bool? }
struct OrbitCalendarAttendee: Codable, Hashable { let personId: String?; let name: String?; let status: String? }

/// A calendar the signed-in person may create events in (server decides: adults every family calendar, a child only their own).
struct OrbitCalendarTarget: Decodable, Identifiable, Hashable { let id: String; let name: String; let kind: String?; let access: String? }
/// A family member who has a stored calendar address and can be invited.
struct OrbitInviteOption: Decodable, Identifiable, Hashable { let personId: String; let name: String; var id: String { personId } }
struct OrbitCalendarTargetsResponse: Decodable { let targets: [OrbitCalendarTarget]; let inviteOptions: [OrbitInviteOption]? }
/// Honest outcome of a write to iCloud: accepted | conflict | refused | failed | outcome_unknown | already_requested.
struct OrbitProviderWriteResult: Decodable { let state: String; let code: String? }

enum OrbitProviderWriteCopy {
    static func text(_ result: OrbitProviderWriteResult) -> String {
        switch result.state {
        case "accepted": return "Готово."
        case "already_requested": return "Цю подію вже створювали. Перевірте календар."
        case "conflict": return result.code == "gone_in_provider" ? "Цієї події вже немає в iCloud. Оновіть календар." : "Подію змінили в iCloud. Оновіть календар і повторіть."
        case "outcome_unknown": return "iCloud не підтвердив результат вчасно. Перевірте календар за кілька хвилин і не повторюйте дію."
        case "failed": return "iCloud відхилив запит. Спробуйте пізніше."
        case "refused": return refused(result.code)
        default: return "Не вдалося виконати дію."
        }
    }

    private static func refused(_ code: String?) -> String {
        switch code ?? "" {
        case "ui_write_disabled", "provider_write_disabled": return "Запис в iCloud з Orbit поки вимкнено для цього профілю."
        case "source_access_denied", "minor_or_unknown_actor", "forbidden": return "У вас немає права змінювати цей календар."
        case "invites_disabled": return "Запрошення поки вимкнені."
        case "invites_not_allowed_in_calendar": return "У цьому календарі запрошення неможливі. Оберіть календар для запрошень."
        case "invitee_not_allowed": return "Цю людину поки не можна запрошувати."
        case "invitee_address_missing": return "Для цієї людини не вказано адресу календаря."
        case "organizer_address_missing": return "Не вказано адресу організатора."
        case "minor_cannot_invite": return "Запрошувати можуть лише дорослі."
        case "recurring_unsupported": return "Повторювані події поки не можна змінювати з Orbit."
        case "ui_rate_limited": return "Забагато змін за годину. Спробуйте пізніше."
        case "write_in_flight": return "Ця подія вже змінюється. Зачекайте хвилину."
        case "etag_missing_resync": return "Подію ще синхронізують. Оновіть календар і спробуйте знову."
        case "invalid_invitation": return "Некоректний список запрошених."
        default: return "Дію відхилено сервером."
        }
    }
}

struct OrbitCalendarEvent: Codable, Identifiable, Hashable {
    let id: String
    let familyId: String
    let ownerPersonId: String
    var title: String
    var notes: String
    var startsAt: Date
    var endsAt: Date
    var allDay: Bool
    let sourceType: String
    let sourceIdentifier: String?
    let sourceName: String?
    let sourceColor: String?
    let createdAt: Date?
    let updatedAt: Date?
    var occurrenceId: String? = nil
    var startDate: String? = nil
    var endDate: String? = nil
    var timeZone: String? = nil
    // Additive, backend-provided (calendar mirror). Absent on older backends.
    var location: String? = nil
    var mirrorEventId: String? = nil
    var capabilities: OrbitCalendarCapabilities? = nil
    var organizer: OrbitCalendarOrganizer? = nil
    var attendees: [OrbitCalendarAttendee]? = nil
    var calendarOwners: [String]? = nil

    private enum CodingKeys: String, CodingKey {
        case id, familyId, ownerPersonId, title, notes, startsAt, endsAt, allDay
        case sourceType, sourceIdentifier, sourceName, sourceColor, createdAt, updatedAt
        case occurrenceId, startDate, endDate, timeZone
        case location, mirrorEventId, capabilities, organizer, attendees, calendarOwners
    }

    init(
        id: String,
        familyId: String,
        ownerPersonId: String,
        title: String,
        notes: String,
        startsAt: Date,
        endsAt: Date,
        allDay: Bool,
        sourceType: String,
        sourceIdentifier: String?,
        sourceName: String?,
        sourceColor: String?,
        createdAt: Date?,
        updatedAt: Date?,
        occurrenceId: String? = nil,
        startDate: String? = nil,
        endDate: String? = nil,
        timeZone: String? = nil
    ) {
        self.id = id
        self.familyId = familyId
        self.ownerPersonId = ownerPersonId
        self.title = title
        self.notes = notes
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.allDay = allDay
        self.sourceType = sourceType
        self.sourceIdentifier = sourceIdentifier
        self.sourceName = sourceName
        self.sourceColor = sourceColor
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.occurrenceId = occurrenceId
        self.startDate = startDate
        self.endDate = endDate
        self.timeZone = timeZone
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        familyId = try values.decode(String.self, forKey: .familyId)
        ownerPersonId = try values.decode(String.self, forKey: .ownerPersonId)
        title = try values.decode(String.self, forKey: .title)
        notes = try values.decode(String.self, forKey: .notes)
        allDay = try values.decode(Bool.self, forKey: .allDay)
        sourceType = try values.decode(String.self, forKey: .sourceType)
        sourceIdentifier = try values.decodeIfPresent(String.self, forKey: .sourceIdentifier)
        sourceName = try values.decodeIfPresent(String.self, forKey: .sourceName)
        sourceColor = try values.decodeIfPresent(String.self, forKey: .sourceColor)
        createdAt = try values.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try values.decodeIfPresent(Date.self, forKey: .updatedAt)
        occurrenceId = try values.decodeIfPresent(String.self, forKey: .occurrenceId)
        startDate = try values.decodeIfPresent(String.self, forKey: .startDate)
        endDate = try values.decodeIfPresent(String.self, forKey: .endDate)
        timeZone = try values.decodeIfPresent(String.self, forKey: .timeZone)
        location = try values.decodeIfPresent(String.self, forKey: .location)
        mirrorEventId = try values.decodeIfPresent(String.self, forKey: .mirrorEventId)
        capabilities = try values.decodeIfPresent(OrbitCalendarCapabilities.self, forKey: .capabilities)
        organizer = try values.decodeIfPresent(OrbitCalendarOrganizer.self, forKey: .organizer)
        attendees = try values.decodeIfPresent([OrbitCalendarAttendee].self, forKey: .attendees)
        calendarOwners = try values.decodeIfPresent([String].self, forKey: .calendarOwners)

        let eventCalendarTimeZone = timeZone.flatMap(TimeZone.init(identifier:)) ?? .current
        if allDay, let startDate, let localStart = OrbitCalendarV2Logic.localCalendarDate(startDate, timeZone: eventCalendarTimeZone) {
            startsAt = localStart
        } else {
            startsAt = try values.decode(Date.self, forKey: .startsAt)
        }
        if allDay, let endDate, let localEnd = OrbitCalendarV2Logic.localCalendarDate(endDate, timeZone: eventCalendarTimeZone) {
            endsAt = localEnd
        } else {
            endsAt = try values.decode(Date.self, forKey: .endsAt)
        }
    }

}

extension OrbitCalendarEvent: OrbitCalendarV2EventLike {}

struct OrbitCalendarConnection: Decodable, Identifiable, Hashable {
    let id: String
    let provider: String
    let accountLabel: String
    let status: String
    let lastVerifiedAt: Date?
    let defaultWritableSourceId: String?
}

struct OrbitCalendarConnectionResult: Decodable, Hashable {
    let connection: OrbitCalendarConnection
    let calendars: Int
}

struct OrbitCalendarSource: Decodable, Identifiable, Hashable {
    let id: String
    let connectionId: String
    let displayName: String
    let color: String?
    let writable: Bool
    var selected: Bool
    let isDefaultWritable: Bool
}

struct OrbitCalendarLaterResult: Hashable {
    let events: [OrbitCalendarEvent]
    let horizonEnd: Date
    let complete: Bool
    let partialFailure: Bool
    let truncated: Bool

    var coverageDescription: String {
        if complete {
            return "Пошук «Далі» охоплює події до \(horizonEnd.formatted(date: .abbreviated, time: .omitted))."
        }
        return "Перевірка календарів часткова; список може не містити всіх найближчих подій."
    }
}

struct OrbitMemoryAssertion: Decodable, Identifiable, Hashable {
    let id: String
    let kind: String
    let subjectName: String
    let predicate: String
    let valueText: String
    let valueType: String
    let status: String
    let validFrom: Date?
    let validTo: Date?
    let observedAt: Date?
    let recordedAt: Date?
    let supersedesId: String?
    let successor: OrbitMemorySuccessor?
    let sourceType: String?
    let sourceTimestamp: Date?
    let conversationIdentifier: String?
    let sensitivity: String
    let confidence: Double
    let canCorrect: Bool
}

struct OrbitMemorySuccessor: Decodable, Hashable {
    let id: String
    let valueText: String
    let status: String
    let validFrom: Date?
    let validTo: Date?
    let observedAt: Date?
}

struct OrbitMemoryRelationship: Decodable, Identifiable, Hashable {
    let id: String
    let kind: String
    let subjectName: String
    let relationType: String
    let objectName: String
    let status: String
    let validFrom: Date?
    let validTo: Date?
    let sourceType: String?
    let sourceTimestamp: Date?
    let sensitivity: String
}

struct OrbitMemoryEvent: Decodable, Identifiable, Hashable {
    let id: String
    let kind: String
    let eventType: String
    let summary: String
    let occurredFrom: Date?
    let occurredTo: Date?
    let sourceType: String?
    let sourceTimestamp: Date?
    let sensitivity: String
}

struct OrbitMemoryCenterResponse: Decodable {
    let assertions: [OrbitMemoryAssertion]
    let relationships: [OrbitMemoryRelationship]
    let events: [OrbitMemoryEvent]
    let profile: OrbitMemoryProfile
}

struct OrbitIntegrationStatus: Decodable {
    let whatsapp: OrbitWhatsAppIntegrationStatus
}

struct OrbitContact: Codable, Identifiable, Hashable {
    let id: String
    var displayName: String
    var nickname: String?
    var note: String?
    var whatsappNumber: String?
    var telegramPeer: String?
    var telegramUsername: String?
    var telegramIdentityType: String?
    var targetPersonId: String?
    var visibility: String
    var defaultMessagingChannel: String?
    var availableMessagingChannels: [String]?
    let isActive: Bool
    let createdAt: Date?
    let updatedAt: Date?
}

struct OrbitWhatsAppIntegrationStatus: Decodable {
    let state: String
    let inboundVerified: Bool
    let outboundProviderAccepted: Bool
    let requiresConfirmation: Bool
}

struct OrbitMemoryProfile: Decodable {
    let personId: String
    let displayName: String
}

struct OrbitMemoryImportBatch: Decodable, Identifiable {
    let id: String
    let sourceType: String
    let status: String
    let phase: String
    let startedAt: Date
    let completedAt: Date?
    let conversations: Int
    let candidates: Int
    let operationsCreated: Int
    let duplicatesSkipped: Int
    let credentialRejected: Int
    let needsReview: Int
}

private struct MemoryImportsResponse: Decodable { let batches: [OrbitMemoryImportBatch] }
private struct ContactsResponse: Decodable { let contacts: [OrbitContact] }
private struct ContactResponse: Decodable { let contact: OrbitContact }

private struct FamilyMessagesResponse: Decodable { let messages: [OrbitFamilyMessage] }
private struct CalendarResponse: Decodable {
    let events: [OrbitCalendarEvent]
    let partialFailure: Bool?
    let truncated: Bool?
    let complete: Bool?
    let selectionMode: String?
}
private struct CalendarConnectionsResponse: Decodable { let connections: [OrbitCalendarConnection] }
private struct CalendarSourcesResponse: Decodable { let sources: [OrbitCalendarSource] }
private struct CalendarSourceResponse: Decodable { let source: OrbitCalendarSource }
private struct CalendarConnectionResultResponse: Decodable { let connection: OrbitCalendarConnection; let calendars: Int }
private struct MessageResponse: Decodable { let message: OrbitFamilyMessage }
private struct EventResponse: Decodable { let event: OrbitCalendarEvent }

@MainActor
final class MainProductAPI {
    static let shared = MainProductAPI()
    nonisolated private static let serviceBaseURL = URL(string: "https://voice.orbit.opik.net")!
    private let baseURL = MainProductAPI.serviceBaseURL
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = OrbitSchoolDateDecoding.jsonDecoderStrategy
        return decoder
    }()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    func familyProfiles() async throws -> [OrbitFamilyProfile] {
        let response: [OrbitFamilyProfile] = try await request(path: "/api/family/profiles")
        return response
    }

    func schoolItems(filter: String = "all", classifyUnavailable: Bool = false) async throws -> OrbitSchoolItemsResponse {
        try await request(
            path: "/api/school/items?filter=\(filter.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "all")",
            cachePolicy: .reloadIgnoringLocalCacheData,
            classifyUnavailable: classifyUnavailable
        )
    }
    func schulmanagerCalendar(scope: String = "for-us", from: Date = .now, to: Date = Calendar.current.date(byAdding: .month, value: 3, to: .now) ?? .now) async throws -> [OrbitSchulmanagerCalendarEvent] {
        let f = ISO8601DateFormatter(); let path = "/api/school/calendar?scope=\(scope)&from=\(f.string(from: from).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&to=\(f.string(from: to).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"; return try await request(path: path, as: OrbitSchulmanagerCalendarResponse.self).events
    }
    func schoolTasks(coverage: String = "window") async throws -> OrbitSchoolTasksResponse { try await request(path: "/api/school/tasks?coverage=\(coverage)", as: OrbitSchoolTasksResponse.self) }
    func schoolOverview(start: String? = nil, end: String? = nil) async throws -> OrbitSchoolHubV2OverviewResponse {
        try await request(path: schoolV2Path("/api/school/overview", start: start, end: end), cachePolicy: .reloadIgnoringLocalCacheData, preserveHTTPStatus: true)
    }
    func schoolExams(from: String, to: String) async throws -> OrbitSchoolHubV2ExamsResponse {
        try await request(path: schoolV2Path("/api/school/exams", start: from, end: to), cachePolicy: .reloadIgnoringLocalCacheData, preserveHTTPStatus: true)
    }
    func schoolTimetable(from: String, to: String) async throws -> OrbitSchoolHubV2TimetableResponse {
        try await request(path: schoolV2Path("/api/school/timetable", start: from, end: to), cachePolicy: .reloadIgnoringLocalCacheData, preserveHTTPStatus: true)
    }
    func schoolActionTasks(preserveHTTPStatus: Bool = false) async throws -> OrbitSchoolActionTasksResponse {
        try await request(
            path: "/api/school/actions/tasks",
            cachePolicy: .reloadIgnoringLocalCacheData,
            preserveHTTPStatus: preserveHTTPStatus
        )
    }
    func createSchoolActionTask(title: String, description: String = "", schoolDueAt: String? = nil, planningDate: String? = nil, sourceItemId: String? = nil, sourceTaskKey: String? = nil, sourceEventUid: String? = nil, clientRequestId: String = UUID().uuidString) async throws -> OrbitSchoolActionTask {
        struct Payload: Encodable { let title: String; let description: String; let schoolDueAt: String?; let planningDate: String?; let sourceItemId: String?; let sourceTaskKey: String?; let sourceEventUid: String?; let clientRequestId: String }
        struct Response: Decodable { let task: OrbitSchoolActionTask }
        return try await request(path: "/api/school/actions/tasks", method: "POST", body: try encoder.encode(Payload(title: title, description: description, schoolDueAt: schoolDueAt, planningDate: planningDate, sourceItemId: sourceItemId, sourceTaskKey: sourceTaskKey, sourceEventUid: sourceEventUid, clientRequestId: clientRequestId)), as: Response.self).task
    }
    func updateSchoolActionTask(id: String, title: String? = nil, description: String? = nil, planningDate: String? = nil, revision: Int? = nil) async throws -> OrbitSchoolActionTask {
        struct Payload: Encodable { let title: String?; let description: String?; let planningDate: String?; let revision: Int? }
        struct Response: Decodable { let task: OrbitSchoolActionTask }
        return try await request(path: "/api/school/actions/tasks/\(id)", method: "PATCH", body: try encoder.encode(Payload(title: title, description: description, planningDate: planningDate, revision: revision)), as: Response.self).task
    }
    func completeSchoolActionTask(id: String) async throws -> OrbitSchoolActionTask { try await changeSchoolActionTask(path: "/api/school/actions/tasks/\(id)/complete") }
    func reopenSchoolActionTask(id: String) async throws -> OrbitSchoolActionTask { try await changeSchoolActionTask(path: "/api/school/actions/tasks/\(id)/reopen") }
    func completeSourceSchoolTask(itemId: String, taskKey: String) async throws -> OrbitSchoolActionTask { try await changeSchoolActionTask(path: "/api/school/actions/tasks/source/complete", body: ["sourceItemId": itemId, "sourceTaskKey": taskKey]) }
    /// Sets/changes the family's planned date (`YYYY-MM-DD`) of a school source task; Orbit-owned state only.
    func planSourceSchoolTask(itemId: String, taskKey: String, planningDate: String, revision: Int? = nil) async throws -> OrbitSchoolActionTask {
        struct Payload: Encodable { let sourceItemId: String; let sourceTaskKey: String; let planningDate: String; let revision: Int? }
        struct Response: Decodable { let task: OrbitSchoolActionTask }
        return try await request(path: "/api/school/actions/tasks/source/plan", method: "POST", body: try encoder.encode(Payload(sourceItemId: itemId, sourceTaskKey: taskKey, planningDate: planningDate, revision: revision)), as: Response.self).task
    }
    func reopenSourceSchoolTask(itemId: String, taskKey: String) async throws -> OrbitSchoolActionTask { try await changeSchoolActionTask(path: "/api/school/actions/tasks/source/reopen", body: ["sourceItemId": itemId, "sourceTaskKey": taskKey]) }
    private func changeSchoolActionTask(path: String, body: [String: String] = [:]) async throws -> OrbitSchoolActionTask { struct Response: Decodable { let task: OrbitSchoolActionTask }; let data = try JSONSerialization.data(withJSONObject: body); return try await request(path: path, method: "POST", body: data, as: Response.self).task }
    func schoolActionChecklists() async throws -> OrbitSchoolActionChecklistsResponse { try await request(path: "/api/school/actions/checklists", cachePolicy: .reloadIgnoringLocalCacheData) }
    func createSchoolActionChecklist(title: String, sourceItemId: String? = nil, sourceTaskId: String? = nil, sourceEventUid: String? = nil, clientRequestId: String = UUID().uuidString) async throws -> OrbitSchoolActionChecklist { struct Payload: Encodable { let title: String; let sourceItemId: String?; let sourceTaskId: String?; let sourceEventUid: String?; let clientRequestId: String }; struct Response: Decodable { let checklist: OrbitSchoolActionChecklist }; return try await request(path: "/api/school/actions/checklists", method: "POST", body: try encoder.encode(Payload(title: title, sourceItemId: sourceItemId, sourceTaskId: sourceTaskId, sourceEventUid: sourceEventUid, clientRequestId: clientRequestId)), as: Response.self).checklist }
    func addSchoolChecklistItem(checklistId: String, title: String, sourceKind: String = "parent", clientRequestId: String = UUID().uuidString) async throws -> OrbitSchoolActionChecklistItem { struct Payload: Encodable { let title: String; let sourceKind: String; let clientRequestId: String }; struct Response: Decodable { let item: OrbitSchoolActionChecklistItem }; return try await request(path: "/api/school/actions/checklists/\(checklistId)/items", method: "POST", body: try encoder.encode(Payload(title: title, sourceKind: sourceKind, clientRequestId: clientRequestId)), as: Response.self).item }
    func updateSchoolChecklistItem(id: String, title: String? = nil, completed: Bool? = nil, revision: Int) async throws -> OrbitSchoolActionChecklistItem { struct Payload: Encodable { let title: String?; let completed: Bool?; let revision: Int }; struct Response: Decodable { let item: OrbitSchoolActionChecklistItem }; return try await request(path: "/api/school/actions/checklist-items/\(id)", method: "PATCH", body: try encoder.encode(Payload(title: title, completed: completed, revision: revision)), as: Response.self).item }
    func schoolActionNotes(entityType: String? = nil, entityId: String? = nil) async throws -> OrbitSchoolActionNotesResponse {
        var path = "/api/school/actions/notes"
        if let entityType, let entityId,
           let type = entityType.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let id = entityId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "?entityType=\(type)&entityId=\(id)"
        }
        return try await request(path: path, cachePolicy: .reloadIgnoringLocalCacheData)
    }
    func createSchoolActionNote(entityType: String, entityId: String, content: String, clientRequestId: String = UUID().uuidString) async throws -> OrbitSchoolActionNote { struct Payload: Encodable { let entityType: String; let entityId: String; let content: String; let clientRequestId: String }; struct Response: Decodable { let note: OrbitSchoolActionNote }; return try await request(path: "/api/school/actions/notes", method: "POST", body: try encoder.encode(Payload(entityType: entityType, entityId: entityId, content: content, clientRequestId: clientRequestId)), preserveHTTPStatus: true, as: Response.self).note }
    func updateSchoolActionNote(id: String, content: String, revision: Int) async throws -> OrbitSchoolActionNote { struct Payload: Encodable { let content: String; let revision: Int }; struct Response: Decodable { let note: OrbitSchoolActionNote }; return try await request(path: "/api/school/actions/notes/\(id)", method: "PATCH", body: try encoder.encode(Payload(content: content, revision: revision)), preserveHTTPStatus: true, as: Response.self).note }
    func schoolActionHistory() async throws -> OrbitSchoolActionHistoryResponse { try await request(path: "/api/school/actions/history", cachePolicy: .reloadIgnoringLocalCacheData) }
    func schoolBriefing(classifyUnavailable: Bool = false) async throws -> OrbitSchoolBriefingResponse { try await request(path: "/api/school/brain/briefing", classifyUnavailable: classifyUnavailable, as: OrbitSchoolBriefingResponse.self) }
    func schoolBrainConversation() async throws -> OrbitSchoolBrainConversationResponse { try await request(path: "/api/school/brain/conversation") }
    func askSchool(_ content: String) async throws -> OrbitSchoolBrainMessage { struct Payload: Encodable { let content: String }; struct Response: Decodable { let message: OrbitSchoolBrainMessage }; return try await request(path: "/api/school/brain/messages", method: "POST", body: try encoder.encode(Payload(content: content)), as: Response.self).message }
    func addSchoolCalendarEvent(uid: String, key: String = "default", confirm: Bool) async throws -> SchoolCalendarResult { struct Payload: Encodable { let key: String; let confirm: Bool }; return try await request(path: "/api/school/calendar/\(uid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? uid)/proposal", method: "POST", body: try encoder.encode(Payload(key: key, confirm: confirm))) }
    /// School "add to calendar" into a CHOSEN iCloud calendar with optional invitees (server: adults; idempotent per School event).
    func addSchoolCalendarEventToProvider(uid: String, key: String = "default", targetId: String, attendees: [String]) async throws -> OrbitProviderWriteResult {
        struct Payload: Encodable { let key: String; let confirm: Bool; let targetId: String; let attendees: [String] }
        let path = "/api/school/calendar/\(uid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? uid)/proposal"
        return try await providerWrite(path: path, method: "POST", body: try encoder.encode(Payload(key: key, confirm: true, targetId: targetId, attendees: attendees)))
    }
    func createSchoolTaskCalendarEvent(_ request: SchoolTaskCalendarRequest) async throws -> SchoolCalendarResult {
        struct Payload: Encodable { let taskKey: String; let title: String; let date: String; let time: String?; let notes: String; let confirm: Bool }
        let body = try encoder.encode(Payload(taskKey: request.taskKey, title: request.title, date: request.date, time: request.time, notes: request.notes, confirm: true))
        let itemPath = request.itemID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? request.itemID
        return try await self.request(path: "/api/school/items/\(itemPath)/calendar-proposal", method: "POST", body: body, preserveHTTPStatus: true, as: SchoolCalendarResult.self)
    }
    /// School task -> a CHOSEN iCloud calendar (server: adults; idempotent per item + task).
    func createSchoolTaskCalendarEventToProvider(_ request: SchoolTaskCalendarRequest, targetId: String) async throws -> OrbitProviderWriteResult {
        struct Payload: Encodable { let taskKey: String; let title: String; let date: String; let time: String?; let notes: String; let confirm: Bool; let targetId: String; let attendees: [String] }
        let body = try encoder.encode(Payload(taskKey: request.taskKey, title: request.title, date: request.date, time: request.time, notes: request.notes, confirm: true, targetId: targetId, attendees: request.attendees))
        let itemPath = request.itemID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? request.itemID
        return try await providerWrite(path: "/api/school/items/\(itemPath)/calendar-proposal", method: "POST", body: body)
    }
    /// School letter/message event -> a CHOSEN iCloud calendar with optional invitees.
    func addSchoolEventToProvider(itemID: String, event: OrbitSchoolEvent, targetId: String, attendees: [String]) async throws -> OrbitProviderWriteResult {
        struct Payload: Encodable { let key: String; let title: String; let startsAt: Date?; let endsAt: Date?; let allDay: Bool; let location: String?; let confirm: Bool; let targetId: String; let attendees: [String] }
        let body = try encoder.encode(Payload(key: event.key, title: event.title, startsAt: event.startsAt, endsAt: event.endsAt, allDay: event.allDay, location: event.location, confirm: true, targetId: targetId, attendees: attendees))
        let itemPath = itemID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? itemID
        return try await providerWrite(path: "/api/school/items/\(itemPath)/calendar-proposal", method: "POST", body: body)
    }
    func schoolItem(id: String) async throws -> OrbitSchoolItem { try await request(path: "/api/school/items/\(id)", as: SchoolItemResponse.self).item }
    func markSchoolItemRead(id: String) async throws { struct Response: Decodable { let ok: Bool }; _ = try await request(path: "/api/school/items/\(id)/read", method: "POST", body: nil, as: Response.self) }
    func addSchoolEvent(itemID: String, event: OrbitSchoolEvent, confirm: Bool) async throws -> SchoolCalendarResult {
        struct Payload: Encodable { let key: String; let title: String; let startsAt: Date?; let endsAt: Date?; let allDay: Bool; let location: String?; let confirm: Bool }
        let body = try encoder.encode(Payload(key: event.key, title: event.title, startsAt: event.startsAt, endsAt: event.endsAt, allDay: event.allDay, location: event.location, confirm: confirm))
        return try await request(path: "/api/school/items/\(itemID)/calendar-proposal", method: "POST", body: body)
    }

    func familyMessages(limit: Int = 100) async throws -> [OrbitFamilyMessage] {
        let response: FamilyMessagesResponse = try await request(path: "/api/family/messages?limit=\(min(max(limit, 1), 120))")
        return response.messages
    }

    func sendFamilyMessage(_ content: String) async throws -> OrbitFamilyMessage {
        let body = try JSONEncoder().encode(SendFamilyMessage(content: content, clientMessageId: UUID().uuidString.lowercased()))
        let response: MessageResponse = try await request(path: "/api/family/messages", method: "POST", body: body)
        return response.message
    }

    func calendarEvents(from: Date = .now, to: Date = Calendar.current.date(byAdding: .month, value: 3, to: .now) ?? .now, classifyUnavailable: Bool = false) async throws -> [OrbitCalendarEvent] {
        let formatter = ISO8601DateFormatter()
        let path = "/api/family/calendar?from=\(formatter.string(from: from).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&to=\(formatter.string(from: to).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        let response: CalendarResponse = try await request(path: path, classifyUnavailable: classifyUnavailable)
        return response.events
    }

    /// Requests the single, half-open local-date interval used by the Later section.
    func laterCalendarEvents(
        from start: Date,
        to end: Date,
        timeZone: TimeZone = .current,
        excludingEventKeys: Set<String> = []
    ) async throws -> OrbitCalendarLaterResult {
        guard end > start else {
            return OrbitCalendarLaterResult(events: [], horizonEnd: end, complete: true, partialFailure: false, truncated: false)
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let excludedJSON = try encoder.encode(excludingEventKeys.sorted())
        guard let excluded = String(data: excludedJSON, encoding: .utf8) else { throw OrbitChatAPIError.invalidResponse }
        var components = URLComponents()
        components.path = "/api/family/calendar"
        components.queryItems = [
            URLQueryItem(name: "selection", value: "starts"),
            URLQueryItem(name: "from", value: formatter.string(from: start)),
            URLQueryItem(name: "to", value: formatter.string(from: end)),
            URLQueryItem(name: "timeZone", value: timeZone.identifier),
            URLQueryItem(name: "excludeEventKeys", value: excluded),
        ]
        guard let path = components.string else { throw OrbitChatAPIError.invalidResponse }
        let response: CalendarResponse = try await request(path: path, classifyUnavailable: true)
        let complete = response.complete == true && response.selectionMode == "starts" && response.partialFailure != true && response.truncated != true
        return OrbitCalendarLaterResult(
            events: response.events,
            horizonEnd: end,
            complete: complete,
            partialFailure: response.partialFailure == true,
            truncated: response.truncated == true || response.complete == nil
        )
    }

    func calendarConnections() async throws -> [OrbitCalendarConnection] {
        try await request(path: "/api/calendar/connections", as: CalendarConnectionsResponse.self).connections
    }

    func connectICloudCalendar(accountLabel: String, username: String, appSpecificPassword: String) async throws -> OrbitCalendarConnectionResult {
        struct Payload: Encodable {
            let accountLabel: String
            let username: String
            let appSpecificPassword: String
        }
        let body = try encoder.encode(Payload(accountLabel: accountLabel, username: username, appSpecificPassword: appSpecificPassword))
        let response: CalendarConnectionResultResponse = try await request(path: "/api/calendar/connections", method: "POST", body: body)
        return OrbitCalendarConnectionResult(connection: response.connection, calendars: response.calendars)
    }

    func refreshCalendarConnection(id: String) async throws {
        struct Response: Decodable { let connectionId: String; let calendars: Int }
        let _: Response = try await request(path: "/api/calendar/connections/\(id)/refresh", method: "POST", body: nil)
    }

    func disconnectCalendarConnection(id: String) async throws {
        struct Response: Decodable { let disconnected: Bool }
        let _: Response = try await request(path: "/api/calendar/connections/\(id)", method: "DELETE", body: nil)
    }

    /// Best-effort, read-only: asks the server to refresh its iCloud mirror for the visible window now (pull-to-refresh). Failures are ignored.
    func refreshCalendarNow(from: Date, to: Date) async {
        struct Payload: Encodable { let from: String; let to: String }
        struct Response: Decodable { let refreshed: Int?; let skipped: Int?; let errors: Int? }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let body = try? encoder.encode(Payload(from: formatter.string(from: from), to: formatter.string(from: to))) else { return }
        let _: Response? = try? await request(path: "/api/calendar/refresh-now", method: "POST", body: body)
    }

    func calendarSources() async throws -> [OrbitCalendarSource] {
        try await request(path: "/api/calendar/sources", as: CalendarSourcesResponse.self).sources
    }

    func updateCalendarSource(id: String, selected: Bool) async throws -> OrbitCalendarSource {
        struct Payload: Encodable { let selected: Bool }
        let body = try encoder.encode(Payload(selected: selected))
        return try await request(path: "/api/calendar/sources/\(id)", method: "PATCH", body: body, as: CalendarSourceResponse.self).source
    }

    func setDefaultWritableCalendar(sourceId: String) async throws {
        struct Payload: Encodable { let sourceId: String }
        let body = try encoder.encode(Payload(sourceId: sourceId))
        struct Response: Decodable { let defaultWritableSourceId: String }
        _ = try await request(path: "/api/calendar/default-writable-source", method: "PUT", body: body, as: Response.self)
    }

    func calendarTargets() async throws -> OrbitCalendarTargetsResponse {
        try await request(path: "/api/calendar/targets", as: OrbitCalendarTargetsResponse.self)
    }

    private static func localDayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// Creates ONE event in the chosen iCloud calendar (adults any family calendar, a child only their own). A fixed idempotency key makes a repeated tap safe.
    func createProviderEvent(targetId: String, title: String, notes: String, location: String, startsAt: Date, endsAt: Date, allDay: Bool, attendees: [String], idempotencyKey: String) async throws -> OrbitProviderWriteResult {
        struct Payload: Encodable {
            let targetId: String
            let title: String
            let notes: String
            let location: String
            let allDay: Bool
            let startsAt: Date?
            let endsAt: Date?
            let startDate: String?
            let endDate: String?
            let attendees: [String]
            let idempotencyKey: String
        }
        let body = try encoder.encode(Payload(
            targetId: targetId, title: title, notes: notes, location: location, allDay: allDay,
            startsAt: allDay ? nil : startsAt, endsAt: allDay ? nil : endsAt,
            startDate: allDay ? Self.localDayString(startsAt) : nil, endDate: allDay ? Self.localDayString(max(endsAt, startsAt)) : nil,
            attendees: attendees, idempotencyKey: idempotencyKey
        ))
        return try await providerWrite(path: "/api/calendar/events", method: "POST", body: body)
    }

    /// Edits a mirrored iCloud event. Only the fields the server allows for this person are sent; a changed ETag in iCloud means NOT applied (conflict).
    func updateProviderEvent(mirrorEventId: String, title: String?, notes: String?, location: String?, startsAt: Date?, endsAt: Date?) async throws -> OrbitProviderWriteResult {
        struct Payload: Encodable { let title: String?; let notes: String?; let location: String?; let startsAt: Date?; let endsAt: Date? }
        let body = try encoder.encode(Payload(title: title, notes: notes, location: location, startsAt: startsAt, endsAt: endsAt))
        return try await providerWrite(path: "/api/calendar/events/\(mirrorEventId)", method: "PATCH", body: body)
    }

    func deleteProviderEvent(mirrorEventId: String) async throws -> OrbitProviderWriteResult {
        try await providerWrite(path: "/api/calendar/events/\(mirrorEventId)", method: "DELETE", body: nil)
    }

    /// Writes answer with {state, code} on every status (200 accepted, 202 unknown, 403 refused, 409 conflict, 422 failed); that body is the result.
    private func providerWrite(path: String, method: String, body: Data?) async throws -> OrbitProviderWriteResult {
        guard let token = KeychainStore.readMainBearerToken() else { throw OrbitChatAPIError.notPaired }
        guard let url = URL(string: path, relativeTo: baseURL) else { throw OrbitChatAPIError.invalidResponse }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.timeoutInterval = 75
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body { urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type"); urlRequest.httpBody = body }
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw OrbitChatAPIError.invalidResponse }
        if let result = try? decoder.decode(OrbitProviderWriteResult.self, from: data) { return result }
        if http.statusCode == 403 { return OrbitProviderWriteResult(state: "refused", code: "forbidden") }
        let code = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
        throw OrbitChatAPIError.requestFailed(Self.userFacingError(code))
    }

    func createCalendarEvent(title: String, notes: String, startsAt: Date, endsAt: Date, allDay: Bool) async throws -> OrbitCalendarEvent {
        let body = try encoder.encode(CalendarEventPayload(title: title, notes: notes, startsAt: startsAt, endsAt: endsAt, allDay: allDay))
        let response: EventResponse = try await request(path: "/api/family/calendar", method: "POST", body: body)
        return response.event
    }

    func updateCalendarEvent(_ event: OrbitCalendarEvent) async throws -> OrbitCalendarEvent {
        let body = try encoder.encode(CalendarEventPayload(title: event.title, notes: event.notes, startsAt: event.startsAt, endsAt: event.endsAt, allDay: event.allDay))
        let response: EventResponse = try await request(path: "/api/family/calendar/\(event.id)", method: "PATCH", body: body)
        return response.event
    }

    func deleteCalendarEvent(_ event: OrbitCalendarEvent) async throws {
        struct Empty: Decodable {}
        _ = try await request(path: "/api/family/calendar/\(event.id)", method: "DELETE", body: nil) as Empty
    }

    func memoryCenter(query: String = "", includeHistory: Bool = false, limit: Int = 50) async throws -> OrbitMemoryCenterResponse {
        var components = URLComponents(string: "/api/memory")!
        components.queryItems = [
            URLQueryItem(name: "history", value: includeHistory ? "true" : "false"),
            URLQueryItem(name: "limit", value: String(min(max(limit, 1), 80))),
        ]
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            components.queryItems?.append(URLQueryItem(name: "q", value: query))
        }
        do {
            return try await request(path: components.url!.absoluteString)
        } catch let OrbitChatAPIError.requestFailed(message) where message == "memory_center_unavailable" {
            throw OrbitChatAPIError.requestFailed("Не вдалося завантажити пам’ять Orbit. Перевірте з’єднання та повторіть спробу.")
        }
    }

    func correctMemoryAssertion(id: String, correction: String) async throws {
        let body = try JSONEncoder().encode(MemoryCorrection(correction: correction))
        let _: MemoryCorrectionResponse = try await request(path: "/api/memory/assertions/\(id)/correct", method: "POST", body: body)
    }

    func memoryImports(limit: Int = 40) async throws -> [OrbitMemoryImportBatch] {
        let response: MemoryImportsResponse = try await request(path: "/api/memory/imports?limit=\(min(max(limit, 1), 80))")
        return response.batches
    }

    func integrationStatus() async throws -> OrbitIntegrationStatus {
        try await request(path: "/api/integrations/status")
    }

    func contacts(query: String = "") async throws -> [OrbitContact] {
        var path = "/api/contacts"
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            path += "?q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        }
        return try await request(path: path, as: ContactsResponse.self).contacts
    }

    func createContact(_ payload: OrbitContactPayload) async throws -> OrbitContact {
        let body = try encoder.encode(payload)
        return try await request(path: "/api/contacts", method: "POST", body: body, as: ContactResponse.self).contact
    }

    func updateContact(id: String, _ payload: OrbitContactPayload) async throws -> OrbitContact {
        let body = try encoder.encode(payload)
        return try await request(path: "/api/contacts/\(id)", method: "PATCH", body: body, as: ContactResponse.self).contact
    }

    func archiveContact(id: String) async throws {
        struct ArchiveResponse: Decodable { let id: String; let archived: Bool }
        _ = try await request(path: "/api/contacts/\(id)/archive", method: "POST", body: nil, as: ArchiveResponse.self)
    }

    private struct SendFamilyMessage: Encodable { let content: String; let clientMessageId: String }
    private struct CalendarEventPayload: Encodable { let title: String; let notes: String; let startsAt: Date; let endsAt: Date; let allDay: Bool }
    private struct MemoryCorrection: Encodable { let correction: String }
    private struct MemoryCorrectionResponse: Decodable { let idempotent: Bool; let confirmed: Bool }

    struct OrbitContactPayload: Encodable {
        let displayName: String
        let nickname: String?
        let note: String?
        let whatsappNumber: String?
        let telegramPeer: String?
        let telegramUsername: String?
        let targetPersonId: String?
        let visibility: String
        let defaultMessagingChannel: String?
    }

    func request<T: Decodable>(path: String, method: String = "GET", body: Data? = nil, cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy, classifyUnavailable: Bool = false, allowRefresh: Bool = true, preserveHTTPStatus: Bool = false, as: T.Type = T.self) async throws -> T {
        guard let token = KeychainStore.readMainBearerToken() else { throw OrbitChatAPIError.notPaired }
        guard let url = URL(string: path, relativeTo: baseURL) else { throw OrbitChatAPIError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.cachePolicy = cachePolicy
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body { request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = body }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OrbitChatAPIError.invalidResponse }
        if http.statusCode == 401, allowRefresh, KeychainStore.readSessionToken() != nil, await OrbitAuthentication.refreshStoredSession() {
            return try await self.request(path: path, method: method, body: body, cachePolicy: cachePolicy, classifyUnavailable: classifyUnavailable, allowRefresh: false, preserveHTTPStatus: preserveHTTPStatus, as: T.self)
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let code = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            if preserveHTTPStatus { throw OrbitHTTPResponseFailure(status: http.statusCode, code: code) }
            if classifyUnavailable, let failure = OrbitHTTPFailure.classify(status: http.statusCode) { throw failure }
            throw OrbitChatAPIError.requestFailed(Self.userFacingError(code))
        }
        do { return try decoder.decode(T.self, from: data) } catch { throw OrbitChatAPIError.invalidResponse }
    }

    nonisolated static func triggerSchoolSync() async throws {
        guard let token = KeychainStore.readMainBearerToken() else { throw OrbitSchoolSyncError.notPaired }
        var request = URLRequest(url: serviceBaseURL.appendingPathComponent("api/integrations/schulmanager/sync-trigger"))
        request.httpMethod = "POST"
        request.timeoutInterval = 35
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"source":"ios-shortcuts"}"#.utf8)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw OrbitSchoolSyncError.network
        }
        guard let http = response as? HTTPURLResponse else { throw OrbitSchoolSyncError.invalidResponse }
        guard http.statusCode == 200 else {
            if http.statusCode == 401 || http.statusCode == 403 { throw OrbitSchoolSyncError.unauthorized }
            throw OrbitSchoolSyncError.serviceUnavailable
        }
        guard let result = try? JSONDecoder().decode(OrbitSchoolSyncResponse.self, from: data), result.ok, result.accepted else {
            throw OrbitSchoolSyncError.invalidResponse
        }
        if result.newItemCount > 0 { await SchoolNotificationCoordinator.shared.schedule(newItemCount: result.newItemCount, itemIDs: result.items.map(\.id)) }
    }

    private static func userFacingError(_ code: String?) -> String {
        switch code {
        case "contact_identity_already_linked": "Ця ідентичність уже прив’язана до іншого контакту."
        case "invalid_whatsapp_number": "Вкажіть WhatsApp номер у міжнародному форматі, наприклад +380971234567."
        case "invalid_telegram_identity": "Перевірте Telegram username або відомий peer."
        case "contact_profile_not_found": "Обраний профіль Orbit недоступний."
        case "contact_not_found": "Контакт більше недоступний."
        case "invalid_credentials": "Не вдалося увійти в iCloud. Перевірте Apple ID та пароль для програми."
        case "network_error", "service_unavailable": "Не вдалося підключитися до iCloud. Спробуйте ще раз."
        case "principal_discovery_failed", "calendar_home_discovery_failed", "collection_discovery_failed", "invalid_response", "unsupported_redirect": "Не вдалося отримати список календарів iCloud."
        case "child_profile_read_only": OrbitPermissionCopy.readOnlyProfile
        case "proposal_target_not_found", "proposal_target_not_correctable", "proposal_target_not_current": "Цей факт зараз не можна виправити пропозицією."
        case "proposal_value_invalid", "proposal_value_not_storable": "Перевірте текст: він має бути коротким і без паролів чи кодів."
        case "proposal_limit_reached": "Забагато пропозицій очікують розгляду. Спробуйте пізніше."
        case "adult_required", "self_approval_forbidden": "Рішення за пропозицією ухвалює інший дорослий член родини."
        case "calendar_connection_rate_limited": "Забагато спроб. Спробуйте ще раз трохи пізніше."
        case "invalid_calendar_connection": "Перевірте назву, Apple ID і пароль для програми."
        default: "Orbit тимчасово недоступний. Спробуйте ще раз."
        }
    }
}

private struct SchoolItemResponse: Decodable { let item: OrbitSchoolItem }
struct SchoolCalendarResult: Decodable { let created: Bool; let duplicate: Bool?; let requiresConfirmation: Bool?; let eventId: String? }

private func schoolV2Path(_ path: String, start: String?, end: String?) -> String {
    var items = [(String, String)]()
    if let start { items.append(("start", start)) }
    if let end { items.append(("end", end)) }
    guard !items.isEmpty else { return path }
    let query = items.map { key, value in
        "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value)"
    }.joined(separator: "&")
    return "\(path)?\(query)"
}

nonisolated struct OrbitSchoolSyncResponse: Decodable, Sendable {
    let ok: Bool
    let accepted: Bool
    let pending: Bool
    let newItemCount: Int
    let newLetterCount: Int
    let newMessageCount: Int
    let items: [SchoolSyncItem]
}
nonisolated struct SchoolSyncItem: Decodable, Sendable { let id: String; let type: String }

nonisolated enum OrbitSchoolSyncError: LocalizedError, Sendable {
    case notPaired
    case unauthorized
    case network
    case serviceUnavailable
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notPaired: "Orbit не активований на цьому пристрої."
        case .unauthorized: "Orbit не підтвердив доступ цього пристрою."
        case .network, .serviceUnavailable: "Не вдалося передати шкільний тригер до Orbit."
        case .invalidResponse: "Orbit повернув неочікувану відповідь."
        }
    }
}
