import Foundation
import Observation

/// Pure (UI-free) state machine for "Додати до календаря" from a school task.
/// Success is only ever reported after the server confirmed creation (or reported a duplicate).

struct SchoolTaskCalendarRequest: Equatable, Sendable {
    let itemID: String
    let taskKey: String
    let title: String
    let date: String
    let time: String?
    /// Optional range end ("HH:mm", same day, after `time`).
    var endTime: String? = nil
    let notes: String
    /// nil = the Orbit family calendar; otherwise the id of the chosen iCloud calendar.
    var targetId: String? = nil
    var attendees: [String] = []
}

struct SchoolTaskCalendarOutcome: Equatable, Sendable {
    let created: Bool
    let duplicate: Bool
    let eventID: String?
    /// Set when the server refused or could not complete the write (user-facing text).
    var failure: String? = nil
}

protocol SchoolTaskCalendarService: Sendable {
    func createEvent(_ request: SchoolTaskCalendarRequest) async throws -> SchoolTaskCalendarOutcome
}

enum SchoolTaskCalendarState: Equatable {
    case editing
    case saving
    case saved(eventID: String?, duplicate: Bool)
    case failed(String)
}

enum SchoolTaskCalendarFailure {
    static func message(for error: Error) -> String {
        if let url = error as? URLError {
            switch url.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost, .cannotFindHost, .dataNotAllowed:
                return "Немає з’єднання. Подію не створено — спробуйте ще раз."
            default: break
            }
        }
        if let status = (error as? OrbitHTTPResponseFailure)?.status {
            switch status {
            case 401: return "Сесію завершено. Увійдіть у Orbit знову."
            case 403, 404: return "Немає доступу до цієї справи."
            case 400: return "Перевірте дату й час."
            default: break
            }
        }
        return "Не вдалося створити подію. Спробуйте ще раз."
    }
}

@MainActor
@Observable
final class SchoolTaskCalendarModel {
    let taskTitle: String
    let itemID: String
    let taskKey: String
    let knownDeadline: String?
    var title: String
    var notes: String
    var hasDate: Bool
    var date: Date
    var hasTime = false
    var time: Date
    var hasEndTime = false
    var endTime: Date
    var targetId = "orbit_local"
    var invitees = Set<String>()
    private(set) var state: SchoolTaskCalendarState = .editing

    @ObservationIgnored private let service: SchoolTaskCalendarService

    init(itemID: String, taskKey: String, title: String, notes: String, knownDeadline: String?, knownTime: String? = nil, knownEndTime: String? = nil, service: SchoolTaskCalendarService, now: Date = Date()) {
        self.itemID = itemID
        self.taskKey = taskKey
        self.taskTitle = title
        self.title = title
        self.notes = notes
        self.knownDeadline = knownDeadline
        self.service = service
        let prefilled = knownDeadline.flatMap { SchoolHubLogic.date(fromDayKey: $0) }
        // No known date -> today (owner decision); the user can still change it.
        self.hasDate = true
        self.date = prefilled ?? now
        let defaultTime = SchoolHubLogic.date(fromDayKey: SchoolHubLogic.dayKey(of: now)).map { $0.addingTimeInterval(-3 * 3600) } ?? now
        // An exact time from the school source is carried into the event.
        let day = SchoolHubLogic.date(fromDayKey: SchoolHubLogic.dayKey(of: prefilled ?? now))   // civil day (noon anchor)
        let known = knownTime.flatMap { SchoolHubLogic.minutes(fromTimeKey: $0) }
        let at = { (minutes: Int) -> Date? in day.flatMap { SchoolHubLogic.calendar().date(bySettingHour: minutes / 60 % 24, minute: minutes % 60, second: 0, of: $0) } }
        if let known, let start = at(known), let end = at(min(known + 60, 23 * 60 + 59)) {
            self.hasTime = true
            self.time = start
            // A range end stated by the school ("09:00-12:00") is carried too; otherwise the default one-hour end stays optional.
            if let endKnown = knownEndTime.flatMap({ SchoolHubLogic.minutes(fromTimeKey: $0) }), endKnown > known, let rangeEnd = at(endKnown) {
                self.endTime = rangeEnd
                self.hasEndTime = true
            } else {
                self.endTime = end
            }
        } else {
            self.time = defaultTime
            self.endTime = defaultTime.addingTimeInterval(3600)
        }
    }

    var dayKey: String? { hasDate ? SchoolHubLogic.dayKey(of: date) : nil }
    var timeText: String? {
        guard hasTime else { return nil }
        let parts = SchoolHubLogic.calendar().dateComponents([.hour, .minute], from: time)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
    var endTimeText: String? {
        guard hasTime, hasEndTime else { return nil }
        let parts = SchoolHubLogic.calendar().dateComponents([.hour, .minute], from: endTime)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
    /// The range end must be after the start (same day).
    var endIsValid: Bool { guard let start = timeText, let end = endTimeText else { return true }; return end > start }
    var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    var canSave: Bool { hasDate && !trimmedTitle.isEmpty && endIsValid && state != .saving && !isSaved }
    var isSaved: Bool { if case .saved = state { return true } else { return false } }
    var isSaving: Bool { state == .saving }

    func save() async {
        guard canSave, let day = dayKey else { return }
        state = .saving
        let request = SchoolTaskCalendarRequest(itemID: itemID, taskKey: taskKey, title: trimmedTitle, date: day, time: timeText, endTime: endTimeText, notes: notes.trimmingCharacters(in: .whitespacesAndNewlines), targetId: targetId == "orbit_local" ? nil : targetId, attendees: targetId == "orbit_local" ? [] : Array(invitees).sorted())
        do {
            let outcome = try await service.createEvent(request)
            if let failure = outcome.failure { state = .failed(failure); return }
            guard outcome.created || outcome.duplicate else { state = .failed("Сервер не підтвердив створення події."); return }
            state = .saved(eventID: outcome.eventID, duplicate: outcome.duplicate && !outcome.created)
        } catch is CancellationError {
            state = .editing
        } catch {
            state = .failed(SchoolTaskCalendarFailure.message(for: error))
        }
    }

    func dismissError() { if case .failed = state { state = .editing } }
}
