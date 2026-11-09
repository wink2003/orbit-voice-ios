import Foundation

@main
struct OrbitPermissionsTests {
    static let contract = #"""
    {"version":"orbit.effective_permissions.v1","actorClass":"%@","chat":{"privateChat":true,"familyChat":true,"voice":true},
     "memory":{"readOwnPrivate":true,"readSharedFamily":true,"proposeSharedFact":true,"proposeSharedFactCorrection":true,"reviewProposals":%@,"mutateApprovedSharedFact":%@},
     "resources":{"calendar":{"read":true,"write":%@},"school":{"read":true,"write":%@,"markOwnItemsRead":true},"exams":{"read":true,"write":%@},"tasks":{"read":true,"write":%@},"contacts":{"read":true,"write":%@},"familySettings":{"read":false,"write":false}},
     "note":"x"}
    """#

    static func decode(_ klass: String, adult: Bool) throws -> OrbitEffectivePermissions {
        let b = adult ? "true" : "false"
        let json = String(format: contract, klass, b, b, b, b, b, b, b)
        return try JSONDecoder().decode(OrbitEffectivePermissions.self, from: Data(json.utf8))
    }

    static func main() throws {
        let child = try decode("child", adult: false)
        precondition(child.isChild, "child contract is a child")
        for p in [OrbitWritePermission.calendarWrite, .contactsWrite, .reviewProposals] { precondition(!child.allows(p), "child cannot \(p)") }
        precondition(child.allows(.proposeSharedFact), "child may propose a correction")
        precondition(child.resources.calendar.read && child.resources.school.read && child.memory.readOwnPrivate && child.memory.readSharedFamily, "read access stays")

        let adult = try decode("adult", adult: true)
        precondition(!adult.isChild, "adult contract")
        for p in [OrbitWritePermission.calendarWrite, .contactsWrite, .reviewProposals, .proposeSharedFact] { precondition(adult.allows(p), "adult keeps \(p)") }

        // Fail-closed / compatibility fallbacks
        precondition(!OrbitEffectivePermissions.fallback(isMinor: true).allows(.calendarWrite), "fallback child is read-only")
        precondition(OrbitEffectivePermissions.fallback(isMinor: false).allows(.calendarWrite), "fallback adult keeps writes")
        precondition(!OrbitEffectivePermissions.fallback(isMinor: true).allows(.proposeSharedFact), "old backend has no proposal API")
        precondition(OrbitPermissionPolicy.allows(.calendarWrite, permissions: nil), "unresolved identity keeps today's UI; backend decides")
        precondition(OrbitPermissionPolicy.resolved(contract: nil, isMinor: true)?.isChild == true, "isMinor without contract => child")
        precondition(OrbitPermissionPolicy.resolved(contract: nil, isMinor: nil) == nil, "nothing known => nil")
        precondition(OrbitPermissionPolicy.resolved(contract: child, isMinor: false)?.isChild == true, "contract wins over isMinor")
        // Unknown actor class is treated as a child
        let odd = try decode("martian", adult: true)
        precondition(odd.isChild, "unknown actorClass is not adult")
        // A malformed contract must not decode (caller falls back to isMinor)
        precondition((try? JSONDecoder().decode(OrbitEffectivePermissions.self, from: Data("{}".utf8))) == nil, "malformed contract rejected")
        precondition(OrbitPermissionCopy.readOnlyProfile.contains("лише переглядає"), "copy")
        print("OrbitPermissionsTests: PASS")
    }
}
