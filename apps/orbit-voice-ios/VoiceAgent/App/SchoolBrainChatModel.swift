import Foundation
import Observation

/// Pure (UI-free) logic for the "Запитати про школу" chat so it can be tested without a simulator.

enum SchoolBrainEndpoints {
    static let conversation = "/api/school/brain/conversation"
    static let ask = "/api/school/brain/messages"
}

struct SchoolBrainHTTPError: Error, Equatable { let status: Int }
struct SchoolBrainNotSignedIn: Error, Equatable {}

enum SchoolBrainFailure: Equatable {
    case unauthorized, forbidden, server, offline, other

    static func classify(_ error: Error) -> SchoolBrainFailure {
        if error is SchoolBrainNotSignedIn { return .unauthorized }
        if let http = error as? SchoolBrainHTTPError {
            switch http.status {
            case 401: return .unauthorized
            case 403: return .forbidden
            case 500...: return .server
            default: return .other
            }
        }
        if let url = error as? URLError {
            switch url.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost, .cannotFindHost, .dataNotAllowed: return .offline
            default: return .other
            }
        }
        return .other
    }

    var message: String {
        switch self {
        case .unauthorized: "Сесію завершено. Увійдіть у Orbit знову."
        case .forbidden: "Немає доступу до шкільних даних цього профілю."
        case .server: "Сервіс тимчасово недоступний. Спробуйте за хвилину."
        case .offline: "Немає з’єднання з інтернетом."
        case .other: "Не вдалося отримати відповідь. Спробуйте ще раз."
        }
    }

    var loadMessage: String {
        switch self {
        case .other: "Не вдалося завантажити розмову."
        default: message
        }
    }

    var isRetryable: Bool { self != .unauthorized && self != .forbidden }
}

enum SchoolBrainStarters {
    static let all = [
        "Що важливого цього тижня?",
        "Що потрібно зробити?",
        "Які нові повідомлення?",
        "Які найближчі події?",
        "Чи є невиконані завдання?",
        "Що я міг пропустити?",
    ]
}

enum SchoolBrainLayout {
    /// Extra bottom padding needed so content ending at `contentMaxY` (global
    /// coordinates) does not sit under a dock whose top edge is `dockTopY`.
    /// Derived from measured geometry, so it adapts to any device, Dynamic Type
    /// and keyboard state without fixed offsets.
    static func dockOverlap(contentMaxY: CGFloat, dockTopY: CGFloat) -> CGFloat {
        guard contentMaxY.isFinite, dockTopY.isFinite else { return 0 }
        return max(0, contentMaxY - dockTopY)
    }
}

struct SchoolBrainSourceInfo: Equatable, Sendable {
    let id: String
    let type: String
    let title: String
    let date: Date?
}

struct SchoolBrainSourceRow: Identifiable, Equatable {
    let type: String
    let itemID: String
    let title: String?
    let date: Date?
    var id: String { "\(type):\(itemID)" }
    var typeLabel: String { type == "letter" ? "Лист" : "Повідомлення" }
    var displayTitle: String { title ?? typeLabel }
}

enum SchoolBrainSources {
    static let navigableTypes: Set<String> = ["letter", "message"]

    static func catalogKey(type: String, id: String) -> String { "\(type):\(id)" }

    static func rows(refs: [[String: String]], catalog: [String: SchoolBrainSourceInfo]) -> [SchoolBrainSourceRow] {
        var seen = Set<String>()
        var result: [SchoolBrainSourceRow] = []
        for ref in refs {
            guard let id = ref["id"], !id.isEmpty, let type = ref["type"], navigableTypes.contains(type) else { continue }
            guard seen.insert(catalogKey(type: type, id: id)).inserted else { continue }
            let info = catalog[catalogKey(type: type, id: id)]
            let title = info.flatMap { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0.title }
            result.append(SchoolBrainSourceRow(type: type, itemID: id, title: title, date: info?.date ?? parseDate(ref["sourceDate"])))
        }
        return result
    }

    static func parseDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let plain = ISO8601DateFormatter(); plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: value) { return date }
        let day = DateFormatter(); day.locale = Locale(identifier: "en_US_POSIX"); day.timeZone = TimeZone(identifier: "Europe/Berlin"); day.dateFormat = "yyyy-MM-dd"
        return day.date(from: String(value.prefix(10)))
    }

    static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "uk_UA"); formatter.timeZone = TimeZone(identifier: "Europe/Berlin"); formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: date)
    }
}

protocol SchoolBrainService: Sendable {
    func loadConversation() async throws -> [OrbitSchoolBrainMessage]
    func ask(_ question: String) async throws -> OrbitSchoolBrainMessage
    func loadSourceCatalog() async throws -> [SchoolBrainSourceInfo]
}

enum SchoolBrainLoadState: Equatable {
    case idle, loading, loaded, failed(SchoolBrainFailure)
}

@MainActor
@Observable
final class SchoolBrainChatModel {
    private(set) var messages: [OrbitSchoolBrainMessage] = []
    private(set) var loadState: SchoolBrainLoadState = .idle
    private(set) var isSending = false
    private(set) var sendFailure: SchoolBrainFailure?
    private(set) var failedQuestion: String?
    private(set) var pendingQuestion: String?
    private(set) var sourceCatalog: [String: SchoolBrainSourceInfo] = [:]
    var draft = ""

    @ObservationIgnored private let service: SchoolBrainService
    @ObservationIgnored private var catalogLoaded = false

    init(service: SchoolBrainService) { self.service = service }

    var trimmedDraft: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
    var canSend: Bool { !trimmedDraft.isEmpty && !isSending }
    var isEmptyConversation: Bool { messages.isEmpty && pendingQuestion == nil }

    func applyStarter(_ text: String) { draft = text; sendFailure = nil }

    func dismissError() { sendFailure = nil; failedQuestion = nil }

    func load() async {
        guard !isSending else { return }
        if messages.isEmpty { loadState = .loading }
        do {
            let loaded = try await service.loadConversation()
            guard !isSending else { return }
            messages = loaded
            loadState = .loaded
            await loadCatalogIfNeeded()
        } catch is CancellationError {
            if messages.isEmpty { loadState = .idle }
        } catch {
            loadState = messages.isEmpty ? .failed(SchoolBrainFailure.classify(error)) : .loaded
        }
    }

    func send() async {
        guard canSend else { return }
        let question = trimmedDraft
        await submit(question, restoreDraftOnFailure: true)
    }

    func retry() async {
        guard !isSending, let question = failedQuestion else { return }
        await submit(question, restoreDraftOnFailure: false)
    }

    private func submit(_ question: String, restoreDraftOnFailure: Bool) async {
        isSending = true
        pendingQuestion = question
        sendFailure = nil
        failedQuestion = nil
        if restoreDraftOnFailure { draft = "" }
        defer { isSending = false; pendingQuestion = nil }
        do {
            let reply = try await service.ask(question)
            messages.append(OrbitSchoolBrainMessage(id: "local-\(UUID().uuidString)", role: "user", content: question, sourceRefs: [], createdAt: Date()))
            if !messages.contains(where: { $0.id == reply.id }) { messages.append(reply) }
            if trimmedDraft == question { draft = "" }
            await loadCatalogIfNeeded()
        } catch is CancellationError {
            if restoreDraftOnFailure, draft.isEmpty { draft = question }
        } catch {
            sendFailure = SchoolBrainFailure.classify(error)
            failedQuestion = question
            if restoreDraftOnFailure, draft.isEmpty { draft = question }
        }
    }

    func sourceRows(for message: OrbitSchoolBrainMessage) -> [SchoolBrainSourceRow] {
        guard message.role == "assistant" else { return [] }
        return SchoolBrainSources.rows(refs: message.sourceRefs, catalog: sourceCatalog)
    }

    private func loadCatalogIfNeeded() async {
        guard !catalogLoaded, messages.contains(where: { !$0.sourceRefs.isEmpty }) else { return }
        guard let items = try? await service.loadSourceCatalog() else { return }
        catalogLoaded = true
        sourceCatalog = Dictionary(items.map { (SchoolBrainSources.catalogKey(type: $0.type, id: $0.id), $0) }, uniquingKeysWith: { first, _ in first })
    }
}
