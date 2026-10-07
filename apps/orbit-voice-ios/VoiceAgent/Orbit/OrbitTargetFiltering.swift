import Foundation

enum OrbitTargetFiltering {
    static func selectableTargetIds(_ targetIds: [String], principalPersonId: String?) -> [String] {
        targetIds.filter { $0 != principalPersonId }
    }
}
