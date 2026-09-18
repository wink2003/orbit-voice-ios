import Foundation

private struct StrictEvent: Decodable { let startsAt: Date?; let endsAt: Date? }
private struct FlexibleEvent: Decodable {
    let startsAt: Date?
    let endsAt: Date?

    enum CodingKeys: String, CodingKey { case startsAt, endsAt }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startsAt = try Self.decode(c, forKey: .startsAt)
        endsAt = try Self.decode(c, forKey: .endsAt)
    }
    static func decode(_ c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Date? {
        guard let raw = try c.decodeIfPresent(String.self, forKey: key) else { return nil }
        guard let date = OrbitSchoolDateDecoding.date(from: raw) else { throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "unsupported") }
        return date
    }
}

@main
struct OrbitSchoolDateDecodingTests {
    static func main() {
        let payload = Data(#"{"startsAt":"2026-10-12","endsAt":"2026-10-16"}"#.utf8)
        let strict = JSONDecoder()
        strict.dateDecodingStrategy = .iso8601
        precondition((try? strict.decode(StrictEvent.self, from: payload)) == nil, "The production-shaped event must reproduce the old strict ISO8601 failure")
        let flexible = try! JSONDecoder().decode(FlexibleEvent.self, from: payload)
        precondition(flexible.startsAt != nil && flexible.endsAt != nil)
        print("School event date decoding: PASS")
    }
}
