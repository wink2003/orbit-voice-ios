import Foundation

struct OrbitProfile: Decodable {
    let personId: String
    let displayName: String
    let familyId: String
    let isMinor: Bool
}

struct OrbitConversation: Decodable, Identifiable, Hashable {
    let id: String
    let kind: String
    let title: String
    let subtitle: String
    let lastMessage: String?
    let updatedAt: Date?
}

struct OrbitChatMessage: Decodable, Identifiable {
    let id: String
    let conversationId: String
    let senderKind: String
    let senderPersonId: String?
    let content: String
    let createdAt: Date
    let clientMessageId: String?
    let actionConfirmation: OrbitActionConfirmation?
}

struct OrbitActionConfirmation: Decodable, Equatable {
    let actionId: String
    let capability: String
    let status: String
    let recipient: String
    let message: String
    let needsConfirmation: Bool
    let channel: String?
}

private struct ChatsResponse: Decodable {
    let chats: [OrbitConversation]
    let profile: OrbitProfile
}

private struct MessagesResponse: Decodable {
    let messages: [OrbitChatMessage]
}

struct SendMessageResponse: Decodable {
    let userMessage: OrbitChatMessage
    let assistantMessage: OrbitChatMessage
}

enum OrbitChatAPIError: LocalizedError {
    case notPaired
    case requestFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notPaired: "Цей iPhone ще не активований для Orbit."
        case let .requestFailed(message): message
        case .invalidResponse: "Orbit повернув некоректну відповідь."
        }
    }
}

@MainActor
final class OrbitChatAPI {
    static let shared = OrbitChatAPI()
    private let baseURL = URL(string: "https://voice.orbit.opik.net")!
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func chats() async throws -> (profile: OrbitProfile, chats: [OrbitConversation]) {
        let response: ChatsResponse = try await request(path: "/api/chats")
        return (response.profile, response.chats)
    }

    func messages(in conversation: OrbitConversation) async throws -> [OrbitChatMessage] {
        let response: MessagesResponse = try await request(path: "/api/chats/\(conversation.id)/messages?limit=100")
        return response.messages
    }

    func send(_ text: String, to conversation: OrbitConversation, clientMessageId: String = UUID().uuidString.lowercased()) async throws -> SendMessageResponse {
        let body: [String: String] = [
            "content": text,
            "clientMessageId": clientMessageId,
        ]
        return try await request(path: "/api/chats/\(conversation.id)/messages", method: "POST", body: body)
    }

    private func request<T: Decodable>(path: String, method: String = "GET", body: [String: String]? = nil) async throws -> T {
        guard let deviceToken = KeychainStore.readDeviceToken() else { throw OrbitChatAPIError.notPaired }
        guard let url = URL(string: path, relativeTo: baseURL) else { throw OrbitChatAPIError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OrbitChatAPIError.invalidResponse }
        guard (200 ..< 300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw OrbitChatAPIError.requestFailed(message ?? "Не вдалося зв’язатися з Orbit.")
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw OrbitChatAPIError.invalidResponse
        }
    }
}
