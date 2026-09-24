import Foundation

private let fixture = """
{"items":[{"id":"item-1","type":"letter","source":"schulmanager","externalId":"safe-external-id","title":"","sender":"","originalGerman":"safe placeholder","originalPlainText":"safe placeholder","previewPlainText":"safe placeholder","titlePlainText":"","translationUkrainian":"готово","important":"готово","tasks":[{"key":"bring-item","title":"Принести річ","action":"Принести річ","dueAt":null,"allDay":false,"importance":"normal","target":"family","confidence":0.9,"reason":"explicit","sourceKey":null}],"sourceTimestamp":"2026-09-24T10:00:00Z","importedAt":"2026-09-24T10:00:00Z","orbitReadAt":null,"unread":true,"attachments":[],"events":[],"threadId":null,"subscriptionId":null}],"unreadCount":1}
"""

struct Build60Task: Decodable { let key: String; let title: String; let action: String?; let dueAt: String?; let allDay: Bool; let importance: String?; let target: String?; let confidence: Double?; let reason: String?; let location: String?; let sourceItemId: String; let sourceType: String; let sourceExternalId: String }
struct Build60Item: Decodable { let id: String; let tasks: [Build60Task]? }
struct FixedItem: Decodable { let id: String }
struct ItemsResponse<Item: Decodable>: Decodable { let items: [Item]; let unreadCount: Int }

let data = Data(fixture.utf8)
do {
    _ = try JSONDecoder().decode(ItemsResponse<Build60Item>.self, from: data)
    fatalError("build-60 decoder unexpectedly accepted the incompatible task payload")
} catch let error as DecodingError {
    guard case .keyNotFound(let key, let context) = error else { fatalError("unexpected decoder error: \(error)") }
    precondition(key.stringValue == "sourceItemId")
    precondition(context.codingPath.map(\.stringValue).contains("tasks"))
    print("pre-fix keyNotFound path=\(context.codingPath.map(\.stringValue).joined(separator: ".")) missing=\(key.stringValue)")
}
let fixed = try! JSONDecoder().decode(ItemsResponse<FixedItem>.self, from: data)
precondition(fixed.items.count == 1)
precondition(fixed.unreadCount == 1)
print("post-fix decodedItems=\(fixed.items.count) unknownTasksIgnored=true")
