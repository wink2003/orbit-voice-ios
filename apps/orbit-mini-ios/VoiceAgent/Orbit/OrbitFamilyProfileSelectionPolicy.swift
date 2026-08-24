import Foundation

/// Pure policy for Mini's family-profile selector. It deliberately returns
/// only IDs supplied by the authenticated family API; it can never create an
/// assistant/product identity such as "Orbit".
enum OrbitFamilyProfileSelectionPolicy {
    static func resolvedPersonID(persistedPersonID: String?, availablePersonIDs: [String]) -> String? {
        guard !availablePersonIDs.isEmpty else { return nil }
        if let persistedPersonID, availablePersonIDs.contains(persistedPersonID) {
            return persistedPersonID
        }
        return availablePersonIDs[0]
    }
}
