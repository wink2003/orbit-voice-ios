import SwiftUI

enum SchoolBrainRequestState {
    static func alertBinding(error: Binding<String?>) -> Binding<Bool> {
        Binding(
            get: { error.wrappedValue != nil },
            set: { isPresented in
                if !isPresented { error.wrappedValue = nil }
            }
        )
    }

    static func beginRequest(error: inout String?) {
        error = nil
    }

    static func completedSuccessfully(error: inout String?) {
        error = nil
    }
}
