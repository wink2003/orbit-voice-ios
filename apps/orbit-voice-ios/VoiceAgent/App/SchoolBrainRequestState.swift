import Foundation

enum SchoolBrainRequestState {
    static func beginRequest(error: inout String?) {
        error = nil
    }

    static func completedSuccessfully(error: inout String?) {
        error = nil
    }
}
