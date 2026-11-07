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
        // Title localization: Ukrainian preferred, German preserved and exposed as caption.
        let titled = try! decoder.decode(OrbitSchoolItem.self, from: item(#","titleUkrainian":"Батьківські збори Mathematik","titlePlainText":"Elternabend Mathematik""#))
        precondition(titled.displayTitle == "Батьківські збори Mathematik")
        precondition(titled.germanTitle == "Elternabend Mathematik" && titled.germanTitleCaption == "Elternabend Mathematik")
        precondition(old.displayTitle == "T" && old.germanTitleCaption == nil)  // older backend: German title only
        let blank = try! decoder.decode(OrbitSchoolItem.self, from: item(#","titleUkrainian":"  ""#))
        precondition(blank.displayTitle == "T" && blank.germanTitleCaption == nil)
        let same = try! decoder.decode(OrbitSchoolItem.self, from: item(#","titleUkrainian":"T""#))
        precondition(same.germanTitleCaption == nil)  // no duplicate caption
        // German original is untouched by status handling.
        precondition(old.originalGerman == "Guten Tag")
        print("School item translationStatus decoding: PASS")
    }
}
