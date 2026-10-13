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
    let notes: String
}

struct SchoolTaskCalendarOutcome: Equatable, Sendable {
    let created: Bool
    let duplicate: Bool
    let eventID: String?
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
    private(set) var state: SchoolTaskCalendarState = .editing

    @ObservationIgnored private let service: SchoolTaskCalendarService

    init(itemID: String, taskKey: String, title: String, notes: String, knownDeadline: String?, service: SchoolTaskCalendarService, now: Date = Date()) {
        self.itemID = itemID
        self.taskKey = taskKey
        self.taskTitle = title
        self.title = title
        self.notes = notes
        self.knownDeadline = knownDeadline
        self.service = service
        let prefilled = knownDeadline.flatMap { SchoolHubLogic.date(fromDayKey: $0) }
        self.hasDate = prefilled != nil
        self.date = prefilled ?? now
        self.time = SchoolHubLogic.date(fromDayKey: SchoolHubLogic.dayKey(of: now)).map { $0.addingTimeInterval(-3 * 3600) } ?? now
    }

    var dayKey: String? { hasDate ? SchoolHubLogic.dayKey(of: date) : nil }
    var timeText: String? {
        guard hasTime else { return nil }
        let parts = SchoolHubLogic.calendar().dateComponents([.hour, .minute], from: time)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
    var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    var canSave: Bool { hasDate && !trimmedTitle.isEmpty && state != .saving && !isSaved }
    var isSaved: Bool { if case .saved = state { return true } else { return false } }
    var isSaving: Bool { state == .saving }

    func save() async {
        guard canSave, let day = dayKey else { return }
        state = .saving
        let request = SchoolTaskCalendarRequest(itemID: itemID, taskKey: taskKey, title: trimmedTitle, date: day, time: timeText, notes: notes.trimmingCharacters(in: .whitespacesAndNewlines))
        do {
            let outcome = try await service.createEvent(request)
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
