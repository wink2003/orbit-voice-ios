import Foundation

struct OrbitSchoolBrainMessage: Decodable, Identifiable {
    let id: String
    let role: String
    let content: String
    let sourceRefs: [[String: String]]
    let createdAt: Date

    private enum CodingKeys: String, CodingKey {
        case id, role, content
        case sourceRefs
        case sourceRefsSnake = "source_refs"
        case createdAt
        case createdAtSnake = "created_at"
    }

    init(id: String, role: String, content: String, sourceRefs: [[String: String]], createdAt: Date) {
        self.id = id
        self.role = role
        self.content = content
        self.sourceRefs = sourceRefs
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        role = try container.decode(String.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        sourceRefs = try container.decodeIfPresent([[String: String]].self, forKey: .sourceRefs)
            ?? container.decodeIfPresent([[String: String]].self, forKey: .sourceRefsSnake)
            ?? []
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
            ?? container.decode(Date.self, forKey: .createdAtSnake)
    }
}
