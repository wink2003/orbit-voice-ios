import Foundation

@main
enum OrbitMiniProfileSelectionTests {
    static func main() {
        let profiles = ["oleksii", "oleksandr", "viktoriia"]
        expect(
            OrbitFamilyProfileSelectionPolicy.resolvedPersonID(
                persistedPersonID: "viktoriia",
                availablePersonIDs: profiles
            ) == "viktoriia",
            "a valid persisted profile is restored"
        )
        expect(
            OrbitFamilyProfileSelectionPolicy.resolvedPersonID(
                persistedPersonID: nil,
                availablePersonIDs: profiles
            ) == "oleksii",
            "no persisted profile uses the first server-provided family profile"
        )
        expect(
            OrbitFamilyProfileSelectionPolicy.resolvedPersonID(
                persistedPersonID: "removed-profile",
                availablePersonIDs: profiles
            ) == "oleksii",
            "a stale profile falls back to an available family profile"
        )
        expect(
            OrbitFamilyProfileSelectionPolicy.resolvedPersonID(
                persistedPersonID: "Orbit",
                availablePersonIDs: profiles
            ) == "oleksii",
            "Orbit is never selected unless supplied by the family API"
        )
        expect(
            OrbitFamilyProfileSelectionPolicy.resolvedPersonID(
                persistedPersonID: "oleksii",
                availablePersonIDs: []
            ) == nil,
            "an empty response has no selected profile"
        )
        print("OrbitMiniProfileSelectionTests: PASS")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
