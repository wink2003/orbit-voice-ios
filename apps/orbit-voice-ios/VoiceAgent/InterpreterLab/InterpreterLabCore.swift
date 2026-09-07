// DEBUG-only Orbit Live Interpreter A/B laboratory. No production credentials or provider calls.
#if DEBUG
import Foundation

enum InterpreterProviderKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case azure
    case gemini
    var id: String { rawValue }
    var title: String { self == .azure ? "Azure Speech Translation" : "Gemini Live Translate" }
}

enum InterpreterDirection: String, CaseIterable, Codable, Sendable, Identifiable {
    case ukrainianToGerman
    case germanToUkrainian
    var id: String { rawValue }
    var sourceLocale: String { self == .ukrainianToGerman ? "uk-UA" : "de-DE" }
    var targetLocale: String { self == .ukrainianToGerman ? "de-DE" : "uk-UA" }
    var azureTargetLanguage: String { self == .ukrainianToGerman ? "de" : "uk" }
    var geminiTargetLanguage: String { azureTargetLanguage }
    var title: String { self == .ukrainianToGerman ? "Українська → Deutsch" : "Deutsch → Українська" }
}

enum InterpreterMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case live
    case fixtureReplay
    var id: String { rawValue }
    var title: String { self == .live ? "Live" : "Fixture Replay" }
}

enum InterpreterState: String, Codable, Sendable {
    case idle, preparing, listening, translating, playing, stopping, failed
    var title: String {
        switch self { case .idle: "Ready"; case .preparing: "Preparing"; case .listening: "Listening"; case .translating: "Translating"; case .playing: "Speaking"; case .stopping: "Stopping"; case .failed: "Error" }
    }
}

struct InterpreterAudioFormat: Codable, Sendable, Equatable {
    static let canonical = InterpreterAudioFormat(sampleRate: 16_000, channels: 1, bitsPerSample: 16, chunkMilliseconds: 100)
    let sampleRate: Int
    let channels: Int
    let bitsPerSample: Int
    let chunkMilliseconds: Int
}

struct InterpreterPCMFrame: Sendable {
    let data: Data
    let format: InterpreterAudioFormat
    let capturedAtNanoseconds: UInt64
    var durationMilliseconds: Double { Double(data.count) / Double(format.channels * (format.bitsPerSample / 8) * format.sampleRate) * 1_000 }
}

struct InterpreterAuthorization: Codable, Sendable, Equatable {
    let provider: InterpreterProviderKind
    let token: String
    let endpoint: URL
    let region: String?
    let expiresAt: Date
    nonisolated var isExpired: Bool { expiresAt <= Date() }
}

protocol InterpreterAuthProviding: Sendable {
    func authorization(for provider: InterpreterProviderKind, direction: InterpreterDirection) async throws -> InterpreterAuthorization
}

enum InterpreterAuthError: Error, LocalizedError { case expired, unavailable
    var errorDescription: String? { self == .expired ? "Interpreter authorization expired." : "No interpreter authorization is configured." }
}

/// Deliberately non-secret placeholder. It can exercise expiry and adapter wiring but cannot authenticate anywhere.
struct MockInterpreterAuthProvider: InterpreterAuthProviding {
    let lifetime: TimeInterval = 300
    func authorization(for provider: InterpreterProviderKind, direction: InterpreterDirection) async throws -> InterpreterAuthorization {
        InterpreterAuthorization(provider: provider, token: "MOCK_INTERPRETER_TOKEN_NOT_VALID_FOR_NETWORK", endpoint: URL(string: "https://mock.invalid/interpreter")!, region: provider == .azure ? "mock-region" : nil, expiresAt: Date().addingTimeInterval(lifetime))
    }
}

enum InterpreterEvent: Sendable {
    case state(InterpreterState)
    case sourceTranscript(text: String, isFinal: Bool, receivedAtNanoseconds: UInt64)
    case translatedText(text: String, isFinal: Bool, receivedAtNanoseconds: UInt64)
    case translatedAudio(data: Data, format: InterpreterAudioFormat, receivedAtNanoseconds: UInt64)
    case interruption(String)
    case routeChanged(String)
    case error(String)
    case usage(inputAudioSeconds: Double?, outputAudioSeconds: Double?, estimatedUSD: Double?)
}

protocol InterpreterProvider: Sendable {
    var kind: InterpreterProviderKind { get }
    func events() -> AsyncStream<InterpreterEvent>
    func prepare(authorization: InterpreterAuthorization) async throws
    func start(direction: InterpreterDirection) async throws
    func accept(audio: InterpreterPCMFrame) async throws
    func stopInput() async
    func endSession() async
}

/// The only executable adapter in Phase 1. It makes zero network requests and emits no fabricated translation.
actor MockInterpreterProvider: InterpreterProvider {
    let kind: InterpreterProviderKind
    private let stream: AsyncStream<InterpreterEvent>
    private var continuation: AsyncStream<InterpreterEvent>.Continuation
    init(kind: InterpreterProviderKind) {
        self.kind = kind
        var continuation: AsyncStream<InterpreterEvent>.Continuation!
        stream = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }
    nonisolated func events() -> AsyncStream<InterpreterEvent> { stream }
    func prepare(authorization: InterpreterAuthorization) async throws {
        guard authorization.provider == kind else { throw InterpreterAuthError.unavailable }
        guard !authorization.isExpired else { throw InterpreterAuthError.expired }
        continuation.yield(.state(.preparing))
    }
    func start(direction: InterpreterDirection) async throws { continuation.yield(.state(.listening)) }
    func accept(audio: InterpreterPCMFrame) async throws { /* Intentionally no inference. */ }
    func stopInput() async { continuation.yield(.state(.stopping)) }
    func endSession() async { continuation.yield(.state(.idle)); continuation.finish() }
}

/// Integration gates intentionally remain stubs until dedicated short-lived credentials are approved.
actor AzureSpeechTranslationAdapter: InterpreterProvider {
    let kind: InterpreterProviderKind = .azure
    nonisolated func events() -> AsyncStream<InterpreterEvent> { AsyncStream { $0.yield(.error("Azure SDK integration is credential-gated in Phase 1.")); $0.finish() } }
    func prepare(authorization: InterpreterAuthorization) async throws { throw InterpreterAuthError.unavailable }
    func start(direction: InterpreterDirection) async throws {}
    func accept(audio: InterpreterPCMFrame) async throws {}
    func stopInput() async {}
    func endSession() async {}
}

actor GeminiLiveTranslationAdapter: InterpreterProvider {
    let kind: InterpreterProviderKind = .gemini
    nonisolated func events() -> AsyncStream<InterpreterEvent> { AsyncStream { $0.yield(.error("Gemini Live connection is credential-gated in Phase 1.")); $0.finish() } }
    func prepare(authorization: InterpreterAuthorization) async throws { throw InterpreterAuthError.unavailable }
    func start(direction: InterpreterDirection) async throws {}
    func accept(audio: InterpreterPCMFrame) async throws {}
    func stopInput() async {}
    func endSession() async {}
}

struct InterpreterLatencyMetrics: Codable, Sendable, Equatable {
    var firstInputPCM: UInt64?
    var firstSourceTranscript: UInt64?
    var finalSourceTranscript: UInt64?
    var firstTranslatedText: UInt64?
    var firstTranslatedAudio: UInt64?
    var firstAudioPlayed: UInt64?
    var playbackFinished: UInt64?
    mutating func record(_ event: InterpreterEvent) {
        switch event {
        case .sourceTranscript(_, let final, let time): if final { finalSourceTranscript = finalSourceTranscript ?? time } else { firstSourceTranscript = firstSourceTranscript ?? time }
        case .translatedText(_, _, let time): firstTranslatedText = firstTranslatedText ?? time
        case .translatedAudio(_, _, let time): firstTranslatedAudio = firstTranslatedAudio ?? time
        default: break
        }
    }
    var timestampsAreOrdered: Bool {
        let values = [firstInputPCM, firstSourceTranscript, finalSourceTranscript, firstTranslatedText, firstTranslatedAudio, firstAudioPlayed, playbackFinished].compactMap { $0 }
        return zip(values, values.dropFirst()).allSatisfy { $0 <= $1 }
    }
    func milliseconds(from start: UInt64?, to end: UInt64?) -> Double? { guard let start, let end, end >= start else { return nil }; return Double(end - start) / 1_000_000 }
}

struct InterpreterBenchmarkRecord: Codable, Sendable {
    let schemaVersion = 1
    let provider: InterpreterProviderKind
    let direction: InterpreterDirection
    let mode: InterpreterMode
    let fixtureID: String?
    let sessionID: UUID
    let audioFormat: InterpreterAudioFormat
    let inputAudioDurationMilliseconds: Double
    let sourceTranscript: String
    let translatedText: String
    let errors: [String]
    let reconnectCount: Int
    let interruptions: [String]
    let receivedAudioDurationMilliseconds: Double
    let providerUsageInputAudioSeconds: Double?
    let providerUsageOutputAudioSeconds: Double?
    let estimatedCostUSD: Double?
    let latency: InterpreterLatencyMetrics
}

/// Empty until blinded human review; no LLM judge is implemented in this phase.
struct InterpreterQualityScore: Codable, Sendable, Equatable {
    var sourceTranscriptionAccuracy: Int?
    var semanticTranslationAccuracy: Int?
    var naturalness: Int?
    var terminology: Int?
    var numbersAndDates: Int?
    var negationAndPolarity: Int?
    var overallUsefulness: Int?
    var severeSemanticFailure = false
    var polarityReversal = false
    var numberChanged = false
    var dateTimeChanged = false
    var omittedImportantContent = false
    var isValid: Bool {
        [sourceTranscriptionAccuracy, semanticTranslationAccuracy, naturalness, terminology, numbersAndDates, negationAndPolarity, overallUsefulness]
            .allSatisfy { $0 == nil || (0...5).contains($0!) }
    }
}

enum InterpreterBenchmarkExporter {
    static func sanitizedJSON(_ records: [InterpreterBenchmarkRecord]) throws -> Data {
        // Records intentionally have no auth/header fields; keep this guard when the schema evolves.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(records)
        let forbidden = ["authorization", "api_key", "apikey", "bearer", "token"]
        let lower = String(decoding: data, as: UTF8.self).lowercased()
        guard !forbidden.contains(where: lower.contains) else { throw ExportError.containsSensitiveField }
        return data
    }
    enum ExportError: Error { case containsSensitiveField }
}

struct InterpreterRecordedFixture: Codable, Sendable, Identifiable {
    let id: UUID
    let createdAt: Date
    let format: InterpreterAudioFormat
    let byteCount: Int
}

enum InterpreterFixtureStore {
    private static var directory: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("OrbitInterpreterLabFixtures", isDirectory: true) }
    static func save(_ pcm: Data, format: InterpreterAudioFormat) throws -> InterpreterRecordedFixture {
        let fixture = InterpreterRecordedFixture(id: UUID(), createdAt: Date(), format: format, byteCount: pcm.count)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try pcm.write(to: directory.appendingPathComponent(fixture.id.uuidString).appendingPathExtension("pcm"), options: .atomic)
        try JSONEncoder().encode(fixture).write(to: directory.appendingPathComponent(fixture.id.uuidString).appendingPathExtension("json"), options: .atomic)
        return fixture
    }
    static func load(_ fixture: InterpreterRecordedFixture) throws -> Data { try Data(contentsOf: directory.appendingPathComponent(fixture.id.uuidString).appendingPathExtension("pcm")) }
}
#endif
