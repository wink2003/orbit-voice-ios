import Foundation

/// Effective permissions contract (`orbit.effective_permissions.v1`) returned by `GET /api/me`.
/// Informational UX state only: the backend is authoritative and enforces every rule, so hiding a control here
/// is never a security boundary. Missing/unknown data fails closed for a child and keeps today's behaviour for an adult.
struct OrbitEffectivePermissions: Decodable, Equatable, Sendable {
    struct Resource: Decodable, Equatable, Sendable { let read: Bool; let write: Bool }
    struct Resources: Decodable, Equatable, Sendable { let calendar: Resource; let contacts: Resource; let school: Resource; let tasks: Resource }
    struct Memory: Decodable, Equatable, Sendable {
        let readOwnPrivate: Bool
        let readSharedFamily: Bool
        let proposeSharedFact: Bool
        let proposeSharedFactCorrection: Bool
        let reviewProposals: Bool
        let mutateApprovedSharedFact: Bool
    }
    let version: String
    let actorClass: String
    let resources: Resources
    let memory: Memory

    var isChild: Bool { actorClass != "adult" }

    /// Used when the server did not send a contract (older backend) or it could not be decoded.
    static func fallback(isMinor: Bool) -> OrbitEffectivePermissions {
        let adult = !isMinor
        return OrbitEffectivePermissions(
            version: "fallback", actorClass: adult ? "adult" : "child",
            resources: Resources(calendar: .init(read: true, write: adult), contacts: .init(read: true, write: adult), school: .init(read: true, write: adult), tasks: .init(read: true, write: adult)),
            memory: Memory(readOwnPrivate: true, readSharedFamily: true, proposeSharedFact: false, proposeSharedFactCorrection: false, reviewProposals: adult, mutateApprovedSharedFact: adult))
    }
}

enum OrbitWritePermission: Sendable { case calendarWrite, contactsWrite, proposeSharedFact, reviewProposals }

extension OrbitEffectivePermissions {
    func allows(_ permission: OrbitWritePermission) -> Bool {
        switch permission {
        case .calendarWrite: return resources.calendar.write
        case .contactsWrite: return resources.contacts.write
        case .proposeSharedFact: return memory.proposeSharedFactCorrection
        case .reviewProposals: return memory.reviewProposals
        }
    }
}

/// Pure decision used by the UI store: no contract yet (not resolved) keeps today's behaviour; the backend still decides.
enum OrbitPermissionPolicy {
    static func allows(_ permission: OrbitWritePermission, permissions: OrbitEffectivePermissions?) -> Bool {
        guard let permissions else { return true }
        return permissions.allows(permission)
    }
    static func resolved(contract: OrbitEffectivePermissions?, isMinor: Bool?) -> OrbitEffectivePermissions? {
        if let contract { return contract }
        if let isMinor { return .fallback(isMinor: isMinor) }
        return nil
    }
}

/// Friendly, non-alarming copy for the backend's fail-closed answers.
enum OrbitPermissionCopy {
    static let readOnlyProfile = "Цей профіль лише переглядає. Змінювати це можуть дорослі члени родини."
}


