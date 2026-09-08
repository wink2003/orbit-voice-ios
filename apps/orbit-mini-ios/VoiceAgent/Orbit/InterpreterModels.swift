import Foundation

enum InterpreterDirection: String, CaseIterable, Identifiable, Sendable {
    case ukrainianToGerman = "uk-UA-to-de-DE"
    case germanToUkrainian = "de-DE-to-uk-UA"

    var id: String { rawValue }
    var sourceLanguage: String { self == .ukrainianToGerman ? "uk-UA" : "de-DE" }
    var targetLanguage: String { self == .ukrainianToGerman ? "de" : "uk" }
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
}
