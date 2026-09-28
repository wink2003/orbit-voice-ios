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

    private indirect enum SourceRefValue: Decodable {
        case string(String)
        case object([String: SourceRefValue])
        case array([SourceRefValue])
        case number(Double)
        case boolean(Bool)
        case null

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() { self = .null }
            else if let value = try? container.decode(String.self) { self = .string(value) }
            else if let value = try? container.decode([String: SourceRefValue].self) { self = .object(value) }
            else if let value = try? container.decode([SourceRefValue].self) { self = .array(value) }
            else if let value = try? container.decode(Double.self) { self = .number(value) }
            else if let value = try? container.decode(Bool.self) { self = .boolean(value) }
            else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported School Brain source reference value") }
        }
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
        let encodedRefs = try container.decodeIfPresent([[String: SourceRefValue]].self, forKey: .sourceRefs)
            ?? container.decodeIfPresent([[String: SourceRefValue]].self, forKey: .sourceRefsSnake)
            ?? []
        sourceRefs = encodedRefs.map { ref in
            ref.compactMapValues { value in
                guard case let .string(string) = value else { return nil }
                return string
            }
        }
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
            ?? container.decode(Date.self, forKey: .createdAtSnake)
    }
}

struct OrbitSchoolBriefingSource: Decodable, Hashable { let id: String; let type: String }
struct OrbitSchoolBriefingItem: Decodable, Identifiable, Hashable { let date: String?; let title: String; let detail: String; let sourceRefs: [OrbitSchoolBriefingSource]; var id: String { "\(date ?? "attention"):\(title)" } }
struct OrbitSchoolBriefingResponse: Decodable { let from: String; let to: String; let timeZone: String; let dated: [OrbitSchoolBriefingItem]; let attention: [OrbitSchoolBriefingItem] }
