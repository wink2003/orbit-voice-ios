import Foundation

/// Shared-fact proposals (backend: /api/memory/proposals*). A proposal never changes an approved fact; only an adult decision does.
struct OrbitMemoryProposal: Decodable, Identifiable, Hashable {
    let id: String
    let kind: String
    let predicate: String
    let value: String
    let status: String
    let proposerPersonId: String
    let targetAssertionId: String?
}
private struct OrbitMemoryProposalEnvelope: Decodable { let proposal: OrbitMemoryProposal }
private struct OrbitMemoryProposalList: Decodable { let proposals: [OrbitMemoryProposal] }

extension MainProductAPI {
    /// Idempotent per `clientRequestId`: a retry after a network error never creates a second proposal.
    func proposeMemoryCorrection(targetAssertionId: String, value: String, clientRequestId: String) async throws {
        struct Payload: Encodable { let kind: String; let targetAssertionId: String; let value: String; let clientRequestId: String }
        let body = try JSONEncoder().encode(Payload(kind: "correct", targetAssertionId: targetAssertionId, value: value, clientRequestId: clientRequestId))
        let _: OrbitMemoryProposalEnvelope = try await request(path: "/api/memory/proposals", method: "POST", body: body)
    }

    func pendingMemoryProposals() async throws -> [OrbitMemoryProposal] {
        let response: OrbitMemoryProposalList = try await request(path: "/api/memory/proposals?status=pending")
        return response.proposals
    }

    func decideMemoryProposal(id: String, approve: Bool) async throws {
        struct Payload: Encodable { let decision: String }
        let body = try JSONEncoder().encode(Payload(decision: approve ? "approve" : "reject"))
        let _: OrbitMemoryProposalEnvelope = try await request(path: "/api/memory/proposals/\(id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id)/decision", method: "POST", body: body)
    }
}
