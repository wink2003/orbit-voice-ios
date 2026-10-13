import Foundation

/// Live adapter: School Brain keeps its own authorized, person-scoped conversation
/// and temporal/source-grounded answers, so it stays on the dedicated endpoints.
struct SchoolBrainLiveService: SchoolBrainService {
    func loadConversation() async throws -> [OrbitSchoolBrainMessage] {
        try await Self.map { try await MainProductAPI.shared.request(path: SchoolBrainEndpoints.conversation, cachePolicy: .reloadIgnoringLocalCacheData, preserveHTTPStatus: true, as: OrbitSchoolBrainConversationResponse.self).messages }
    }

    func ask(_ question: String) async throws -> OrbitSchoolBrainMessage {
        struct Payload: Encodable { let content: String }
        struct Response: Decodable { let message: OrbitSchoolBrainMessage }
        let body = try JSONEncoder().encode(Payload(content: question))
        return try await Self.map { try await MainProductAPI.shared.request(path: SchoolBrainEndpoints.ask, method: "POST", body: body, preserveHTTPStatus: true, as: Response.self).message }
    }

    func loadSourceCatalog() async throws -> [SchoolBrainSourceInfo] {
        let response = try await Self.map { try await MainProductAPI.shared.request(path: "/api/school/items?filter=all&limit=200", cachePolicy: .reloadIgnoringLocalCacheData, preserveHTTPStatus: true, as: OrbitSchoolItemsResponse.self) }
        return response.items.map { item in
            let title = (item.titlePlainText ?? item.title).trimmingCharacters(in: .whitespacesAndNewlines)
            let sender = item.sender.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolved = !title.isEmpty ? title : (item.type == "message" && !sender.isEmpty ? "Від: \(sender)" : "")
            return SchoolBrainSourceInfo(id: item.id, type: item.type, title: resolved, date: item.sourceTimestamp)
        }
    }

    private static func map<T>(_ work: () async throws -> T) async throws -> T {
        do { return try await work() }
        catch let failure as OrbitHTTPResponseFailure { throw SchoolBrainHTTPError(status: failure.status) }
        catch OrbitChatAPIError.notPaired { throw SchoolBrainNotSignedIn() }
    }
}
