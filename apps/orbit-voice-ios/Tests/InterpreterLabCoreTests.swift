import Foundation
import XCTest
@testable import VoiceAgent

final class InterpreterLabCoreTests: XCTestCase {
    func testDirectionsUseExplicitLocalesAndTargets() {
        XCTAssertEqual(InterpreterDirection.ukrainianToGerman.sourceLocale, "uk-UA")
        XCTAssertEqual(InterpreterDirection.ukrainianToGerman.azureTargetLanguage, "de")
        XCTAssertEqual(InterpreterDirection.germanToUkrainian.sourceLocale, "de-DE")
        XCTAssertEqual(InterpreterDirection.germanToUkrainian.geminiTargetLanguage, "uk")
    }

    func testMetricsRecordMonotonicMilestones() {
        var metrics = InterpreterLatencyMetrics(firstInputPCM: 100, firstSourceTranscript: nil, finalSourceTranscript: nil, firstTranslatedText: nil, firstTranslatedAudio: nil, firstAudioPlayed: 500, playbackFinished: 700)
        metrics.record(.sourceTranscript(text: "x", isFinal: false, receivedAtNanoseconds: 200))
        metrics.record(.sourceTranscript(text: "x", isFinal: true, receivedAtNanoseconds: 300))
        metrics.record(.translatedText(text: "y", isFinal: true, receivedAtNanoseconds: 350))
        metrics.record(.translatedAudio(data: Data(), format: .canonical, receivedAtNanoseconds: 400))
        XCTAssertTrue(metrics.timestampsAreOrdered)
        XCTAssertEqual(metrics.milliseconds(from: metrics.firstInputPCM, to: metrics.firstTranslatedAudio), 0.0003, accuracy: 0.00001)
    }

    func testFixtureDraftContainsThirtyHumanReviewFixtures() throws {
        let path = #filePath.replacingOccurrences(of: "/Tests/InterpreterLabCoreTests.swift", with: "/VoiceAgent/InterpreterLab/interpreter-fixtures-draft.json")
        let document = try JSONDecoder().decode(InterpreterFixtureDocument.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        XCTAssertEqual(document.status, "DRAFT_FOR_HUMAN_REVIEW")
        XCTAssertEqual(document.fixtures.count, 30)
        XCTAssertEqual(Set(document.fixtures.map(\.direction)), Set(InterpreterDirection.allCases))
        XCTAssertTrue(document.fixtures.allSatisfy(\.humanReviewRequired))
        XCTAssertTrue(document.fixtures.contains { $0.criticalFacts.contains("NEGATION_PRESENT") && $0.severity == "severe" })
    }

    func testExportContainsNoCredentialFields() throws {
        let record = InterpreterBenchmarkRecord(provider: .azure, direction: .ukrainianToGerman, mode: .fixtureReplay, fixtureID: "fixture", sessionID: UUID(), audioFormat: .canonical, inputAudioDurationMilliseconds: 100, sourceTranscript: "test", translatedText: "test", errors: [], reconnectCount: 0, interruptions: [], receivedAudioDurationMilliseconds: 0, providerUsageInputAudioSeconds: nil, providerUsageOutputAudioSeconds: nil, estimatedCostUSD: nil, latency: .init())
        let exported = try InterpreterBenchmarkExporter.sanitizedJSON([record])
        let text = String(decoding: exported, as: UTF8.self).lowercased()
        XCTAssertFalse(text.contains("authorization")); XCTAssertFalse(text.contains("token")); XCTAssertFalse(text.contains("api_key"))
    }

    func testExpiredAuthIsRejected() async {
        let provider = MockInterpreterProvider(kind: .gemini)
        let expired = InterpreterAuthorization(provider: .gemini, token: "mock", endpoint: URL(string: "https://mock.invalid")!, region: nil, expiresAt: .distantPast)
        do { try await provider.prepare(authorization: expired); XCTFail("Expected expired authorization") }
        catch { XCTAssertEqual((error as? InterpreterAuthError)?.localizedDescription, InterpreterAuthError.expired.localizedDescription) }
    }

    func testQualityScoreAcceptsOnlyZeroThroughFive() {
        XCTAssertTrue(InterpreterQualityScore(semanticTranslationAccuracy: 5).isValid)
        XCTAssertFalse(InterpreterQualityScore(semanticTranslationAccuracy: 6).isValid)
    }
}
