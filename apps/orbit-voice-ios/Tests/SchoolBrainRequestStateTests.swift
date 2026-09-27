import Foundation

var staleError: String? = "Не вдалося отримати відповідь School Brain."
SchoolBrainRequestState.beginRequest(error: &staleError)
precondition(staleError == nil)

staleError = "Не вдалося отримати відповідь School Brain."
SchoolBrainRequestState.completedSuccessfully(error: &staleError)
precondition(staleError == nil)

print("school brain success clears stale error state")
