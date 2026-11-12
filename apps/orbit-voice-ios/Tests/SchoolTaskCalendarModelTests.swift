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

        // Undated tasks default to today (owner decision) and stay editable.
        let undated = SchoolTaskCalendarModel(itemID: "i1", taskKey: "i1:x", title: "X", notes: "", knownDeadline: nil, service: service)
        precondition(undated.hasDate && undated.canSave && undated.dayKey == SchoolHubLogic.dayKey(of: Date()))
        undated.hasDate = false
        precondition(!undated.canSave)
        await undated.save()
        precondition(service.requests.isEmpty && undated.state == .editing, "save without a date does nothing")

        // A timed deadline carries its time into the event; the range end is optional and must be after the start.
        let timed = SchoolTaskCalendarModel(itemID: "i1", taskKey: "i1:t", title: "T", notes: "", knownDeadline: "2026-10-20", knownTime: "14:30", service: service)
        precondition(timed.hasTime && timed.timeText == "14:30" && timed.endTimeText == nil && timed.endIsValid)
        timed.hasEndTime = true
        precondition(timed.endTimeText == "15:30" && timed.endIsValid)
        timed.endTime = timed.time.addingTimeInterval(-1800)
        precondition(!timed.endIsValid && !timed.canSave)
        timed.endTime = timed.time.addingTimeInterval(5400)
        precondition(timed.endTimeText == "16:00" && timed.canSave)

        // Timed deadlines are read literally ("...T09:00:00.000Z" means 09:00 as written), never shifted by the UTC offset.
        precondition(SchoolHubLogic.literalTimeKey("2026-11-21T09:00:00.000Z") == "09:00")
        precondition(SchoolHubLogic.literalTimeKey("2026-11-21T14:30:00") == "14:30")
        precondition(SchoolHubLogic.literalTimeKey("2026-11-21T00:00:00.000Z") == nil && SchoolHubLogic.literalTimeKey("2026-11-21") == nil)

        // A school-stated range end is carried; an invalid/earlier end is ignored.
        let ranged = SchoolTaskCalendarModel(itemID: "i1", taskKey: "i1:r", title: "R", notes: "", knownDeadline: "2026-11-21", knownTime: "09:00", knownEndTime: "12:00", service: service)
        precondition(ranged.timeText == "09:00" && ranged.hasEndTime && ranged.endTimeText == "12:00" && ranged.endIsValid)
        let badRange = SchoolTaskCalendarModel(itemID: "i1", taskKey: "i1:r2", title: "R", notes: "", knownDeadline: "2026-11-21", knownTime: "09:00", knownEndTime: "08:00", service: service)
        precondition(!badRange.hasEndTime && badRange.endTimeText == nil)

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
