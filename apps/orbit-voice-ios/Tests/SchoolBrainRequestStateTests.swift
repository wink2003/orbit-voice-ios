import SwiftUI

@main
struct SchoolBrainRequestStateTests {
    static func main() {
        var staleError: String? = "Не вдалося отримати відповідь School Brain."
        SchoolBrainRequestState.beginRequest(error: &staleError)
        precondition(staleError == nil)

        staleError = "Не вдалося отримати відповідь School Brain."
        SchoolBrainRequestState.completedSuccessfully(error: &staleError)
        precondition(staleError == nil)

        var alertError: String? = "Не вдалося отримати відповідь School Brain."
        let binding = SchoolBrainRequestState.alertBinding(error: Binding(
            get: { alertError },
            set: { alertError = $0 }
        ))
        precondition(binding.wrappedValue)
        binding.wrappedValue = false
        precondition(alertError == nil)

        print("school brain success clears stale error and dismisses alert state")
    }
}
