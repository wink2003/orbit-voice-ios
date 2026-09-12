import Foundation

private enum Status: String, Decodable { case released = "RELEASED" }
private enum EvidenceType: String, Decodable { case physical = "PHYSICALLY_VERIFIED" }
private struct Requirement: Decodable {
    let claimKey: String; let requiredEvidenceType: EvidenceType; let satisfaction: String
    enum CodingKeys: String, CodingKey { case claimKey = "claim_key"; case requiredEvidenceType = "required_evidence_type"; case satisfaction }
}
private struct Release: Decodable { let componentName: String; let versionLabel: String; let buildLabel: String; let status: Status
    enum CodingKeys: String, CodingKey { case componentName = "component_name"; case versionLabel = "version_label"; case buildLabel = "build_label"; case status }
}
private struct Detail: Decodable { let release: Release; let verification: [Requirement] }

@main
enum ProjectJournalReleaseDetailTests {
    static func main() throws {
        let data = #"{"release":{"component_name":"Orbit Mini","version_label":"1.0","build_label":"28","status":"RELEASED"},"items":[{"item_id":"item-28","item_key":"mini-interpreter","title":"Orbit Mini Interpreter","status":"DONE"}],"evidence":[],"verification":[{"claim_key":"spoken_translation_tts","required_evidence_type":"PHYSICALLY_VERIFIED","satisfaction":"UNSATISFIED"}]}"#.data(using: .utf8)!
        let detail = try JSONDecoder().decode(Detail.self, from: data)
        precondition(detail.release.componentName == "Orbit Mini")
        precondition(detail.release.versionLabel == "1.0" && detail.release.buildLabel == "28")
        precondition(detail.release.status == .released)
        precondition(detail.verification.count == 1)
        precondition(detail.verification[0].claimKey == "spoken_translation_tts")
        precondition(detail.verification[0].requiredEvidenceType == .physical)
        precondition(detail.verification[0].satisfaction == "UNSATISFIED")
        print("ProjectJournalReleaseDetailTests: PASS")
    }
}
