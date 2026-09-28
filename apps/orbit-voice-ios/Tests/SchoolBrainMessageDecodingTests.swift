import Foundation

@main
struct SchoolBrainMessageDecodingTests {
    static func main() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let message = try decoder.decode(OrbitSchoolBrainMessage.self, from: Data("""
        {"id":"message-1","role":"assistant","content":"Готово","source_refs":[{"id":"item-1","type":"letter"}],"created_at":"2026-09-28T05:26:33.884Z"}
        """.utf8))
        precondition(message.id == "message-1")
        precondition(message.content == "Готово")
        precondition(message.sourceRefs.first?["id"] == "item-1")
        precondition(message.createdAt.timeIntervalSince1970 > 0)
        print("school brain snake_case response decodes")
    }
}
