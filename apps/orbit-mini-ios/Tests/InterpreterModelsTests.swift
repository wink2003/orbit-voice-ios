import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}

@main
struct InterpreterModelsTests {
    static func main() {
        expect(InterpreterDirection.ukrainianToGerman.sourceLanguage == "uk-UA", "UA source mapping")
        expect(InterpreterDirection.ukrainianToGerman.targetLanguage == "de-DE", "DE broker target mapping")
        expect(InterpreterDirection.ukrainianToGerman.azureTargetLanguage == "de", "DE SDK target mapping")
        expect(InterpreterDirection.germanToUkrainian.sourceLanguage == "de-DE", "DE source mapping")
        expect(InterpreterDirection.germanToUkrainian.targetLanguage == "uk-UA", "UA broker target mapping")
        expect(InterpreterDirection.germanToUkrainian.azureTargetLanguage == "uk", "UA SDK target mapping")
        expect(Set(InterpreterDirection.allCases.map(\.rawValue)) == ["uk-UA-to-de-DE", "de-DE-to-uk-UA"], "direction allowlist")
        let json = #"{"provider":"azure","token":"TEST_TOKEN_DO_NOT_USE","expiresAt":"2026-09-08T13:47:36.396Z","sourceLanguage":"uk-UA","targetLanguage":"de-DE","region":"germanywestcentral","endpoint":"https://germanywestcentral.api.cognitive.microsoft.com/","authScheme":"azure-speech-bearer"}"#.data(using: .utf8)!
        let credential = try! JSONDecoder().decode(InterpreterCredential.self, from: json)
        expect(credential.token == "TEST_TOKEN_DO_NOT_USE", "token decode")
        expect(credential.sourceLanguage == "uk-UA" && credential.targetLanguage == "de-DE", "language metadata decode")
        expect(credential.region == "germanywestcentral", "region decode")
        expect(credential.expiresAt.timeIntervalSince1970 > 0, "fractional expiry decode")

        // Keep the native SDK callback boundary structurally executor-neutral.
        // This source-level guard prevents a future refactor from moving the
        // closure literals back into the @MainActor coordinator.
        let coordinatorPath = "apps/orbit-mini-ios/VoiceAgent/Orbit/OrbitMiniInterpreterCoordinator.swift"
        let coordinatorSource = try! String(contentsOfFile: coordinatorPath, encoding: .utf8)
        expect(coordinatorSource.contains("private func installInterpreterRecognizerCallbacks("), "callback adapter exists")
        expect(coordinatorSource.contains("installInterpreterRecognizerCallbacks(on: recognizer"), "coordinator uses callback adapter")
        expect(coordinatorSource.contains("Task { await sink.partial"), "partial callback hops through sink")
        expect(coordinatorSource.contains("Task { await sink.recognized"), "recognized callback hops through sink")
        expect(coordinatorSource.contains("Task { await sink.canceled"), "canceled callback hops through sink")

        let missing = InterpreterTokenClient.diagnostic(for: .keyNotFound(
            InterpreterCodingKey("endpoint"),
            .init(codingPath: [], debugDescription: "missing")
        ))
        expect(missing == .decodeMissingField("endpoint"), "missing endpoint classification")
        let null = InterpreterTokenClient.diagnostic(for: .valueNotFound(
            String.self,
            .init(codingPath: [InterpreterCodingKey("endpoint")], debugDescription: "null")
        ))
        expect(null == .decodeNullField("endpoint"), "null endpoint classification")
        let malformedEndpoint = InterpreterTokenClient.diagnostic(for: .typeMismatch(
            URL.self,
            .init(codingPath: [InterpreterCodingKey("endpoint")], debugDescription: "bad endpoint")
        ))
        expect(malformedEndpoint == .decodeEndpoint, "endpoint classification")
        let malformedExpiry = InterpreterTokenClient.diagnostic(for: .dataCorrupted(
            .init(codingPath: [InterpreterCodingKey("expiresAt")], debugDescription: "bad expiry")
        ))
        expect(malformedExpiry == .decodeExpiresAt, "expiry classification")
        let requiredFields = ["provider", "token", "expiresAt", "sourceLanguage", "targetLanguage", "region", "endpoint", "authScheme"]
        for field in requiredFields {
            let error = DecodingError.keyNotFound(InterpreterCodingKey(field), .init(codingPath: [], debugDescription: "missing"))
            expect(InterpreterTokenClient.diagnostic(for: error).rawValue == "decode_missing_\(field)", "missing \(field) classification")
        }
        let malformedJSON = InterpreterTokenClient.diagnostic(for: .dataCorrupted(
            .init(codingPath: [], debugDescription: "malformed")
        ))
        expect(malformedJSON == .decodeJSON, "malformed JSON classification")
        let userError = InterpreterTokenClientError.invalidResponse(.decodeEndpoint).localizedDescription
        expect(!userError.contains("SUPER_SECRET_TEST_TOKEN_123"), "diagnostic excludes token")
        expect(!userError.contains("https://"), "diagnostic excludes received values")
        print("InterpreterModelsTests: PASS")
    }
}

private struct InterpreterCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.init(stringValue) }
    init?(intValue: Int) { return nil }
}

enum KeychainStore {
    static func readDeviceToken() -> String? { nil }
}
