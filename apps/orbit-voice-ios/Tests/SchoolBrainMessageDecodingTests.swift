import Foundation

@main
struct SchoolBrainMessageDecodingTests {
    static func main() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let message = try decoder.decode(OrbitSchoolBrainMessage.self, from: Data("""
        {"id":"message-1","role":"assistant","content":"Готово","source_refs":[{"id":"item-1","type":"letter","sourceDate":"2026-09-28","tasks":[{"title":"Дія","dueAt":"2026-09-30","importance":"high"}]}],"created_at":"2026-09-28T05:26:33.884Z"}
        """.utf8))
        precondition(message.id == "message-1")
        precondition(message.content == "Готово")
        precondition(message.sourceRefs.first?["id"] == "item-1")
        precondition(message.sourceRefs.first?["type"] == "letter")
        precondition(message.sourceRefs.first?["sourceDate"] == "2026-09-28")
        precondition(message.sourceRefs.first?["tasks"] == nil)
        precondition(message.createdAt.timeIntervalSince1970 > 0)
        let briefing = try decoder.decode(OrbitSchoolBriefingResponse.self, from: Data("""
        {"from":"2026-09-28","to":"2026-10-09","timeZone":"Europe/Berlin","dated":[{"date":"2026-10-03","title":"Подія","detail":"Опис","sourceRefs":[{"id":"calendar-1","type":"calendar"}]}],"attention":[{"date":null,"title":"Опитування","detail":"Перевірити відповідь","sourceRefs":[{"id":"item-1","type":"letter"}]}]}
        """.utf8))
        precondition(briefing.dated.first?.date == "2026-10-03")
        precondition(briefing.dated.first?.sourceRefs.first?.type == "calendar")
        precondition(briefing.attention.count == 1)
        print("school brain snake_case response decodes")
    }
}
