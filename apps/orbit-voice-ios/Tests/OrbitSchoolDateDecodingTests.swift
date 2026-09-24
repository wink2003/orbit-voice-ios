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

        let germanUnityDay = OrbitSchoolCivilDate.formatted("2026-10-03")
        precondition(germanUnityDay.contains("3"), "VALUE=DATE must retain its civil day")
        precondition(!germanUnityDay.contains("2"), "VALUE=DATE must not shift to the prior day")
        precondition(
            OrbitSchoolCivilDate.inclusiveRange(start: "2026-10-03", end: "2026-10-03") == germanUnityDay,
            "A one-day all-day event must not render as a duplicate range"
        )
        let range = OrbitSchoolCivilDate.inclusiveRange(start: "2026-10-03", end: "2026-10-05")
        precondition(range.contains("3") && range.contains("5"), "Inclusive stored all-day range must preserve both civil dates")
        print("School event date decoding: PASS")
    }
}
