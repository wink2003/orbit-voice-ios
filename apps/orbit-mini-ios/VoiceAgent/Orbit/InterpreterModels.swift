import Foundation

enum InterpreterDirection: String, CaseIterable, Identifiable, Sendable {
    case ukrainianToGerman = "uk-UA-to-de-DE"
    case germanToUkrainian = "de-DE-to-uk-UA"

    var id: String { rawValue }
    var sourceLanguage: String { self == .ukrainianToGerman ? "uk-UA" : "de-DE" }
    /// Locale returned by the Orbit broker and used for contract validation.
    var targetLanguage: String { self == .ukrainianToGerman ? "de-DE" : "uk-UA" }
    /// Azure Translation target language tag required by the Speech SDK.
    var azureTargetLanguage: String { self == .ukrainianToGerman ? "de" : "uk" }
    var title: String { self == .ukrainianToGerman ? "🇺🇦 Українська → 🇩🇪 Deutsch" : "🇩🇪 Deutsch → 🇺🇦 Українська" }
}

enum InterpreterState: Equatable, Sendable {
    case idle
    case requestingCredential
    case ready
    case listening
    case partialSource(String)
    case finalSource(String)
    case translatedText(String)
    case stopping
    case error(String)
}

struct InterpreterCredential: Decodable, Sendable {
    let provider: String
    let token: String
    let expiresAt: Date
    let sourceLanguage: String
    let targetLanguage: String
    let region: String
    let endpoint: URL
    let authScheme: String

    private enum CodingKeys: String, CodingKey {
        case provider, token, expiresAt, sourceLanguage, targetLanguage, region, endpoint, authScheme
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        provider = try values.decode(String.self, forKey: .provider)
        token = try values.decode(String.self, forKey: .token)
        let expiry = try values.decode(String.self, forKey: .expiresAt)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let parsed = formatter.date(from: expiry) {
            expiresAt = parsed
        } else {
            formatter.formatOptions = [.withInternetDateTime]
            guard let parsed = formatter.date(from: expiry) else {
                throw DecodingError.dataCorruptedError(forKey: .expiresAt, in: values, debugDescription: "Invalid ISO-8601 expiry")
            }
            expiresAt = parsed
        }
        sourceLanguage = try values.decode(String.self, forKey: .sourceLanguage)
        targetLanguage = try values.decode(String.self, forKey: .targetLanguage)
        region = try values.decode(String.self, forKey: .region)
        endpoint = try values.decode(URL.self, forKey: .endpoint)
        authScheme = try values.decode(String.self, forKey: .authScheme)
    }
}
