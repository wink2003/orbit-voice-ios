import Foundation

final class FakeCalendarService: SchoolTaskCalendarService, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [SchoolTaskCalendarRequest] = []
    var results: [Result<SchoolTaskCalendarOutcome, Error>] = []
    var requests: [SchoolTaskCalendarRequest] { lock.withLock { _requests } }
    func createEvent(_ request: SchoolTaskCalendarRequest) async throws -> SchoolTaskCalendarOutcome {
        lock.withLock { _requests.append(request) }
        let next = lock.withLock { results.isEmpty ? nil : results.removeFirst() }
        return try (next ?? .failure(URLError(.badServerResponse))).get()
    }
}

@main
struct SchoolTaskCalendarModelTests {
    @MainActor static func main() async {
        // Known deadline pre-fills the date; nothing is created by constructing the model.
        let service = FakeCalendarService()
        let dated = SchoolTaskCalendarModel(itemID: "i1", taskKey: "i1:form", title: "Formular", notes: "", knownDeadline: "2026-10-20", service: service)
        precondition(dated.hasDate && dated.dayKey == "2026-10-20" && dated.timeText == nil)
        precondition(dated.canSave && service.requests.isEmpty)

        // Undated tasks require the user to choose a date before saving.
        let undated = SchoolTaskCalendarModel(itemID: "i1", taskKey: "i1:x", title: "X", notes: "", knownDeadline: nil, service: service)
        precondition(!undated.hasDate && !undated.canSave)
        await undated.save()
        precondition(service.requests.isEmpty && undated.state == .editing, "save without a date does nothing")
        undated.hasDate = true
        precondition(undated.canSave)

        // Empty title cannot be saved.
        dated.title = "   "
        precondition(!dated.canSave)
        dated.title = "Formular"

        // Optional time is sent as HH:mm, no clock time is invented otherwise.
        service.results = [.success(SchoolTaskCalendarOutcome(created: true, duplicate: false, eventID: "ev1"))]
        dated.hasTime = true
        await dated.save()
        precondition(service.requests.count == 1 && service.requests[0].date == "2026-10-20" && service.requests[0].time != nil)
        precondition(service.requests[0].taskKey == "i1:i1:form" || service.requests[0].taskKey == "i1:form")
        precondition(dated.state == .saved(eventID: "ev1", duplicate: false))
        await dated.save()
        precondition(service.requests.count == 1, "a saved model never submits twice")

        // Failure never reports success; retry is possible and duplicate replies count as saved.
        let failing = SchoolTaskCalendarModel(itemID: "i1", taskKey: "i1:form", title: "Formular", notes: "n", knownDeadline: "2026-10-20", service: service)
        service.results = [.failure(URLError(.notConnectedToInternet)), .success(SchoolTaskCalendarOutcome(created: false, duplicate: true, eventID: "ev1"))]
        await failing.save()
        if case .failed(let message) = failing.state { precondition(message.contains("з’єднання")) } else { preconditionFailure("expected failure") }
        precondition(!failing.isSaved && failing.canSave)
        await failing.save()
        precondition(failing.state == .saved(eventID: "ev1", duplicate: true))

        // An unconfirmed server reply is not success.
        let unconfirmed = SchoolTaskCalendarModel(itemID: "i1", taskKey: "k", title: "T", notes: "", knownDeadline: "2026-10-20", service: service)
        service.results = [.success(SchoolTaskCalendarOutcome(created: false, duplicate: false, eventID: nil))]
        await unconfirmed.save()
        if case .failed = unconfirmed.state {} else { preconditionFailure("unconfirmed reply must not be success") }

        // Forbidden/not-found map to an access message, not a generic success.
        precondition(SchoolTaskCalendarFailure.message(for: OrbitHTTPResponseFailure(status: 404, code: nil)).contains("доступу"))
        precondition(SchoolTaskCalendarFailure.message(for: OrbitHTTPResponseFailure(status: 400, code: nil)).contains("дату"))

        print("school task calendar model tests passed")
    }
}
