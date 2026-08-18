import Foundation

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
    let createdAt: Date
    let updatedAt: Date
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
private struct MessageResponse: Decodable { let message: OrbitFamilyMessage }
private struct EventResponse: Decodable { let event: OrbitCalendarEvent }

@MainActor
final class MainProductAPI {
    static let shared = MainProductAPI()
    private let baseURL = URL(string: "https://voice.orbit.opik.net")!
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

    func familyMessages(limit: Int = 100) async throws -> [OrbitFamilyMessage] {
        let response: FamilyMessagesResponse = try await request(path: "/api/family/messages?limit=\(min(max(limit, 1), 120))")
        return response.messages
    }

    func sendFamilyMessage(_ content: String) async throws -> OrbitFamilyMessage {
        let body = try JSONEncoder().encode(SendFamilyMessage(content: content, clientMessageId: UUID().uuidString.lowercased()))
        let response: MessageResponse = try await request(path: "/api/family/messages", method: "POST", body: body)
        return response.message
    }

    func calendarEvents(from: Date = .now, to: Date = Calendar.current.date(byAdding: .month, value: 3, to: .now) ?? .now) async throws -> [OrbitCalendarEvent] {
        let formatter = ISO8601DateFormatter()
        let path = "/api/family/calendar?from=\(formatter.string(from: from).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&to=\(formatter.string(from: to).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        let response: CalendarResponse = try await request(path: path)
        return response.events
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
    }

    private func request<T: Decodable>(path: String, method: String = "GET", body: Data? = nil, as: T.Type = T.self) async throws -> T {
        guard let token = KeychainStore.readDeviceToken() else { throw OrbitChatAPIError.notPaired }
        guard let url = URL(string: path, relativeTo: baseURL) else { throw OrbitChatAPIError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body { request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = body }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OrbitChatAPIError.invalidResponse }
        guard (200 ..< 300).contains(http.statusCode) else {
            let code = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw OrbitChatAPIError.requestFailed(Self.userFacingError(code))
        }
        do { return try decoder.decode(T.self, from: data) } catch { throw OrbitChatAPIError.invalidResponse }
    }

    private static func userFacingError(_ code: String?) -> String {
        switch code {
        case "contact_identity_already_linked": "Ця ідентичність уже прив’язана до іншого контакту."
        case "invalid_whatsapp_number": "Вкажіть WhatsApp номер у міжнародному форматі, наприклад +380971234567."
        case "invalid_telegram_identity": "Перевірте Telegram username або відомий peer."
        case "contact_profile_not_found": "Обраний профіль Orbit недоступний."
        case "contact_not_found": "Контакт більше недоступний."
        default: "Orbit тимчасово недоступний. Спробуйте ще раз."
        }
    }
}
