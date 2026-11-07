import Foundation

@main
struct OrbitSchoolItemTranslationStatusDecodingTests {
    static func main() {
        func item(_ extra: String) -> Data {
            Data(#"{"id":"1","type":"letter","source":"schulmanager","externalId":"e","title":"T","sender":"S","originalGerman":"Guten Tag","unread":true,"attachments":[],"events":[]\#(extra)}"#.utf8)
        }
        let decoder = JSONDecoder()
        // Older backend: key absent -> nil, decoding must still succeed.
        let old = try! decoder.decode(OrbitSchoolItem.self, from: item(""))
        precondition(old.translationStatus == nil && old.translationUkrainian == nil)
        // New backend statuses.
        for status in ["ready", "pending", "failed", "original_only"] {
            let decoded = try! decoder.decode(OrbitSchoolItem.self, from: item(#","translationStatus":"\#(status)""#))
            precondition(decoded.translationStatus == status)
        }
        // Explicit null is tolerated.
        precondition((try! decoder.decode(OrbitSchoolItem.self, from: item(#","translationStatus":null"#))).translationStatus == nil)
        // German original is untouched by status handling.
        precondition(old.originalGerman == "Guten Tag")
        print("School item translationStatus decoding: PASS")
    }
}
