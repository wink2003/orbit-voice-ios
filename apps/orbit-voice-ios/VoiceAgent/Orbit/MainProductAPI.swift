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

    private struct SendFamilyMessage: Encodable { let content: String; let clientMessageId: String }
    private struct CalendarEventPayload: Encodable { let title: String; let notes: String; let startsAt: Date; let endsAt: Date; let allDay: Bool }

    private func request<T: Decodable>(path: String, method: String = "GET", body: Data? = nil) async throws -> T {
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
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw OrbitChatAPIError.requestFailed(message ?? "Orbit тимчасово недоступний.")
        }
        do { return try decoder.decode(T.self, from: data) } catch { throw OrbitChatAPIError.invalidResponse }
    }
}
