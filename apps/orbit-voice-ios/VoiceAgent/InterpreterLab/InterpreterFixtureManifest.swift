#if DEBUG
import Foundation

enum InterpreterFixtureManifest {
    static let status = "DRAFT_FOR_HUMAN_REVIEW"
    static let resourceName = "interpreter-fixtures-draft"
    static func load() throws -> [InterpreterFixture] {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "json") else { throw FixtureError.missing }
        let document = try JSONDecoder().decode(InterpreterFixtureDocument.self, from: Data(contentsOf: url))
        guard document.status == status, document.fixtures.count == 30 else { throw FixtureError.invalid }
        return document.fixtures
    }
    enum FixtureError: Error { case missing, invalid }
}

struct InterpreterFixtureDocument: Codable, Sendable { let schemaVersion: Int; let status: String; let fixtures: [InterpreterFixture] }
struct InterpreterFixture: Codable, Sendable, Identifiable {
    let id: String
    let direction: InterpreterDirection
    let category: String
    let sourceText: String
    let referenceTranslation: String
    let criticalFacts: [String]
    let severity: String
    let humanReviewRequired: Bool
    let allowedParaphraseNotes: String
}
#endif
