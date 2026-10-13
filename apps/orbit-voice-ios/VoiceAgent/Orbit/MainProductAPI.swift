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
}
struct OrbitSchoolItemTask: Decodable, Hashable { let key: String?; let title: String?; let action: String?; let dueAt: String?; let allDay: Bool?; let importance: String?; let target: String?; let confidence: Double?; let reason: String? }
struct OrbitSchoolAttachment: Decodable, Hashable { let id: String?; let filename: String; let contentType: String?; let inline: Bool? }
struct OrbitSchoolItemsResponse: Decodable { let items: [OrbitSchoolItem]; let unreadCount: Int }
struct OrbitSchulmanagerCalendarEvent: Decodable, Identifiable, Hashable { let uid: String; let title: String; let description: String; let location: String; let startsAt: String?; let endsAt: String?; let allDay: Bool; let timeZone: String?; let recurrenceRule: String?; let relevanceClass: String?; let audienceClass: String?; let relevanceReason: String?; var id: String { uid } }
struct OrbitSchoolTask: Decodable, Identifiable, Hashable { let key: String; let stableIdentity: Bool?; let title: String; let action: String?; let dueAt: String?; let endsAt: String?; let allDay: Bool; let importance: String?; let target: String?; let confidence: Double?; let reason: String?; let location: String?; let sourceItemId: String; let sourceType: String; let sourceExternalId: String; let bucket: String?; let status: String?; let completedAt: String?; let actionTaskId: String?; let calendarEventId: String?; var id: String { "\(sourceItemId):\(key)" } }
struct OrbitSchulmanagerCalendarResponse: Decodable { let events: [OrbitSchulmanagerCalendarEvent] }
struct OrbitSchoolTasksResponse: Decodable { let from: String; let to: String; let coverage: String?; let truncated: Bool?; let complete: Bool?; let completionState: String?; let tasks: [OrbitSchoolTask]; let importantEvents: [OrbitSchulmanagerCalendarEvent] }
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
}

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
private struct CalendarResponse: Decodable { let events: [OrbitCalendarEvent] }
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
        decoder.dateDecodingStrategy = .iso8601
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
    func reopenSourceSchoolTask(itemId: String, taskKey: String) async throws -> OrbitSchoolActionTask { try await changeSchoolActionTask(path: "/api/school/actions/tasks/source/reopen", body: ["sourceItemId": itemId, "sourceTaskKey": taskKey]) }
    private func changeSchoolActionTask(path: String, body: [String: String] = [:]) async throws -> OrbitSchoolActionTask { struct Response: Decodable { let task: OrbitSchoolActionTask }; let data = try JSONSerialization.data(withJSONObject: body); return try await request(path: path, method: "POST", body: data, as: Response.self).task }
    func schoolActionChecklists() async throws -> OrbitSchoolActionChecklistsResponse { try await request(path: "/api/school/actions/checklists", cachePolicy: .reloadIgnoringLocalCacheData) }
    func createSchoolActionChecklist(title: String, sourceItemId: String? = nil, sourceTaskId: String? = nil, sourceEventUid: String? = nil, clientRequestId: String = UUID().uuidString) async throws -> OrbitSchoolActionChecklist { struct Payload: Encodable { let title: String; let sourceItemId: String?; let sourceTaskId: String?; let sourceEventUid: String?; let clientRequestId: String }; struct Response: Decodable { let checklist: OrbitSchoolActionChecklist }; return try await request(path: "/api/school/actions/checklists", method: "POST", body: try encoder.encode(Payload(title: title, sourceItemId: sourceItemId, sourceTaskId: sourceTaskId, sourceEventUid: sourceEventUid, clientRequestId: clientRequestId)), as: Response.self).checklist }
    func addSchoolChecklistItem(checklistId: String, title: String, sourceKind: String = "parent", clientRequestId: String = UUID().uuidString) async throws -> OrbitSchoolActionChecklistItem { struct Payload: Encodable { let title: String; let sourceKind: String; let clientRequestId: String }; struct Response: Decodable { let item: OrbitSchoolActionChecklistItem }; return try await request(path: "/api/school/actions/checklists/\(checklistId)/items", method: "POST", body: try encoder.encode(Payload(title: title, sourceKind: sourceKind, clientRequestId: clientRequestId)), as: Response.self).item }
    func updateSchoolChecklistItem(id: String, title: String? = nil, completed: Bool? = nil, revision: Int) async throws -> OrbitSchoolActionChecklistItem { struct Payload: Encodable { let title: String?; let completed: Bool?; let revision: Int }; struct Response: Decodable { let item: OrbitSchoolActionChecklistItem }; return try await request(path: "/api/school/actions/checklist-items/\(id)", method: "PATCH", body: try encoder.encode(Payload(title: title, completed: completed, revision: revision)), as: Response.self).item }
    func schoolActionNotes() async throws -> OrbitSchoolActionNotesResponse { try await request(path: "/api/school/actions/notes", cachePolicy: .reloadIgnoringLocalCacheData) }
    func createSchoolActionNote(entityType: String, entityId: String, content: String, clientRequestId: String = UUID().uuidString) async throws -> OrbitSchoolActionNote { struct Payload: Encodable { let entityType: String; let entityId: String; let content: String; let clientRequestId: String }; struct Response: Decodable { let note: OrbitSchoolActionNote }; return try await request(path: "/api/school/actions/notes", method: "POST", body: try encoder.encode(Payload(entityType: entityType, entityId: entityId, content: content, clientRequestId: clientRequestId)), as: Response.self).note }
    func updateSchoolActionNote(id: String, content: String, revision: Int) async throws -> OrbitSchoolActionNote { struct Payload: Encodable { let content: String; let revision: Int }; struct Response: Decodable { let note: OrbitSchoolActionNote }; return try await request(path: "/api/school/actions/notes/\(id)", method: "PATCH", body: try encoder.encode(Payload(content: content, revision: revision)), as: Response.self).note }
    func schoolActionHistory() async throws -> OrbitSchoolActionHistoryResponse { try await request(path: "/api/school/actions/history", cachePolicy: .reloadIgnoringLocalCacheData) }
    func schoolBriefing(classifyUnavailable: Bool = false) async throws -> OrbitSchoolBriefingResponse { try await request(path: "/api/school/brain/briefing", classifyUnavailable: classifyUnavailable, as: OrbitSchoolBriefingResponse.self) }
    func schoolBrainConversation() async throws -> OrbitSchoolBrainConversationResponse { try await request(path: "/api/school/brain/conversation") }
    func askSchool(_ content: String) async throws -> OrbitSchoolBrainMessage { struct Payload: Encodable { let content: String }; struct Response: Decodable { let message: OrbitSchoolBrainMessage }; return try await request(path: "/api/school/brain/messages", method: "POST", body: try encoder.encode(Payload(content: content)), as: Response.self).message }
    func addSchoolCalendarEvent(uid: String, key: String = "default", confirm: Bool) async throws -> SchoolCalendarResult { struct Payload: Encodable { let key: String; let confirm: Bool }; return try await request(path: "/api/school/calendar/\(uid.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? uid)/proposal", method: "POST", body: try encoder.encode(Payload(key: key, confirm: confirm))) }
    func createSchoolTaskCalendarEvent(_ request: SchoolTaskCalendarRequest) async throws -> SchoolCalendarResult {
        struct Payload: Encodable { let taskKey: String; let title: String; let date: String; let time: String?; let notes: String; let confirm: Bool }
        let body = try encoder.encode(Payload(taskKey: request.taskKey, title: request.title, date: request.date, time: request.time, notes: request.notes, confirm: true))
        let itemPath = request.itemID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? request.itemID
        return try await self.request(path: "/api/school/items/\(itemPath)/calendar-proposal", method: "POST", body: body, preserveHTTPStatus: true, as: SchoolCalendarResult.self)
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
        case "calendar_connection_rate_limited": "Забагато спроб. Спробуйте ще раз трохи пізніше."
        case "invalid_calendar_connection": "Перевірте назву, Apple ID і пароль для програми."
        default: "Orbit тимчасово недоступний. Спробуйте ще раз."
        }
    }
}

private struct SchoolItemResponse: Decodable { let item: OrbitSchoolItem }
struct SchoolCalendarResult: Decodable { let created: Bool; let duplicate: Bool?; let requiresConfirmation: Bool?; let eventId: String? }

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
