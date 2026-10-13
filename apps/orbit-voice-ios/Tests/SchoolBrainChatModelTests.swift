import Foundation

final class FakeSchoolBrainService: SchoolBrainService, @unchecked Sendable {
    private let lock = NSLock()
    private var _asked: [String] = []
    private var _conversationCalls = 0
    var conversation: [OrbitSchoolBrainMessage] = []
    var conversationError: Error?
    var askResults: [Result<OrbitSchoolBrainMessage, Error>] = []
    var catalog: [SchoolBrainSourceInfo] = []
    var gate: (() async -> Void)?
    var asked: [String] { lock.withLock { _asked } }
    var conversationCalls: Int { lock.withLock { _conversationCalls } }

    func loadConversation() async throws -> [OrbitSchoolBrainMessage] {
        lock.withLock { _conversationCalls += 1 }
        if let conversationError { throw conversationError }
        return conversation
    }
    func ask(_ question: String) async throws -> OrbitSchoolBrainMessage {
        lock.withLock { _asked.append(question) }
        if let gate { await gate() }
        let next = lock.withLock { askResults.isEmpty ? nil : askResults.removeFirst() }
        return try (next ?? .failure(URLError(.badServerResponse))).get()
    }
    func loadSourceCatalog() async throws -> [SchoolBrainSourceInfo] { catalog }
}

func msg(_ id: String, _ role: String, _ text: String, refs: [[String: String]] = []) -> OrbitSchoolBrainMessage {
    OrbitSchoolBrainMessage(id: id, role: role, content: text, sourceRefs: refs, createdAt: Date(timeIntervalSince1970: 1_760_000_000))
}

@main
struct SchoolBrainChatModelTests {
    @MainActor static func main() async {
        starters()
        layout()
        classification()
        endpoints()
        sources()
        await emptyAndMultiline()
        await sendSuccess()
        await duplicateSend()
        await failureAndRetry()
        await history()
        await sourceResolutionThroughModel()
        print("school brain chat model tests passed")
    }

    static func starters() {
        precondition((4...6).contains(SchoolBrainStarters.all.count))
        precondition(Set(SchoolBrainStarters.all).count == SchoolBrainStarters.all.count)
        let joined = SchoolBrainStarters.all.joined(separator: " ")
        precondition(!joined.contains("5F") && !joined.contains("5Ф"), "starters must not hardcode a class")
    }

    static func layout() {
        // Small iPhone (SE-class, 667pt): content ends at screen bottom, dock top 599 -> 68pt overlap.
        precondition(SchoolBrainLayout.dockOverlap(contentMaxY: 667, dockTopY: 599) == 68)
        // Content already ends above the dock (safe area propagated): no extra padding.
        precondition(SchoolBrainLayout.dockOverlap(contentMaxY: 599, dockTopY: 599) == 0)
        precondition(SchoolBrainLayout.dockOverlap(contentMaxY: 500, dockTopY: 599) == 0)
        // Keyboard raised the content bottom; the overlap follows the measured geometry.
        precondition(SchoolBrainLayout.dockOverlap(contentMaxY: 400, dockTopY: 330) == 70)
        // No dock published / invalid measurement.
        precondition(SchoolBrainLayout.dockOverlap(contentMaxY: 667, dockTopY: .infinity) == 0)
        precondition(SchoolBrainLayout.dockOverlap(contentMaxY: .nan, dockTopY: 599) == 0)
    }

    static func classification() {
        precondition(SchoolBrainFailure.classify(SchoolBrainHTTPError(status: 401)) == .unauthorized)
        precondition(SchoolBrainFailure.classify(SchoolBrainNotSignedIn()) == .unauthorized)
        precondition(SchoolBrainFailure.classify(SchoolBrainHTTPError(status: 403)) == .forbidden)
        precondition(SchoolBrainFailure.classify(SchoolBrainHTTPError(status: 503)) == .server)
        precondition(SchoolBrainFailure.classify(SchoolBrainHTTPError(status: 500)) == .server)
        precondition(SchoolBrainFailure.classify(SchoolBrainHTTPError(status: 404)) == .other)
        precondition(SchoolBrainFailure.classify(URLError(.notConnectedToInternet)) == .offline)
        precondition(SchoolBrainFailure.classify(URLError(.timedOut)) == .offline)
        precondition(!SchoolBrainFailure.unauthorized.isRetryable && !SchoolBrainFailure.forbidden.isRetryable)
        precondition(SchoolBrainFailure.server.isRetryable && SchoolBrainFailure.offline.isRetryable)
        let all: [SchoolBrainFailure] = [.unauthorized, .forbidden, .server, .offline, .other]
        precondition(Set(all.map(\.message)).count == all.count)
    }

    static func endpoints() {
        // Routing evidence: interactive School questions stay on the School Brain endpoints
        // (person-scoped conversation + source-grounded answers), not generic /api/chats.
        precondition(SchoolBrainEndpoints.ask == "/api/school/brain/messages")
        precondition(SchoolBrainEndpoints.conversation == "/api/school/brain/conversation")
    }

    static func sources() {
        let refs: [[String: String]] = [
            ["type": "letter", "id": "L1", "sourceDate": "2026-10-01T08:00:00.000Z"],
            ["type": "letter", "id": "L1"],
            ["type": "message", "id": "M1"],
            ["type": "calendar", "id": "C1"],
            ["type": "letter", "id": ""],
            ["type": "message"],
        ]
        let catalog = ["letter:L1": SchoolBrainSourceInfo(id: "L1", type: "letter", title: "Wandertag", date: nil)]
        let rows = SchoolBrainSources.rows(refs: refs, catalog: catalog)
        precondition(rows.map(\.id) == ["letter:L1", "message:M1"])
        precondition(rows[0].displayTitle == "Wandertag")
        precondition(rows[0].date != nil)
        precondition(rows[1].title == nil && rows[1].displayTitle == "Повідомлення" && rows[1].date == nil)
        // Same id under different types stays distinct (exact identity preserved).
        let twin = SchoolBrainSources.rows(refs: [["type": "letter", "id": "X"], ["type": "message", "id": "X"]], catalog: [:])
        precondition(twin.count == 2)
        precondition(SchoolBrainSources.parseDate("2026-10-02") != nil)
        precondition(SchoolBrainSources.parseDate("garbage") == nil)
    }

    @MainActor static func emptyAndMultiline() async {
        let service = FakeSchoolBrainService()
        let model = SchoolBrainChatModel(service: service)
        precondition(!model.canSend)
        model.draft = "  \n \t "
        precondition(!model.canSend)
        await model.send()
        precondition(service.asked.isEmpty)
        model.draft = "\n Перший рядок\nДругий рядок \n"
        precondition(model.canSend)
        service.askResults = [.success(msg("a1", "assistant", "ок"))]
        await model.send()
        precondition(service.asked == ["Перший рядок\nДругий рядок"])
    }

    @MainActor static func sendSuccess() async {
        let service = FakeSchoolBrainService()
        service.askResults = [.success(msg("a1", "assistant", "Відповідь"))]
        let model = SchoolBrainChatModel(service: service)
        model.applyStarter("Що потрібно зробити?")
        precondition(service.asked.isEmpty, "choosing a starter must not spend AI tokens")
        precondition(model.draft == "Що потрібно зробити?")
        await model.send()
        precondition(service.asked == ["Що потрібно зробити?"])
        precondition(model.messages.map(\.role) == ["user", "assistant"])
        precondition(model.messages.map(\.content) == ["Що потрібно зробити?", "Відповідь"])
        precondition(model.draft.isEmpty && !model.isSending && model.sendFailure == nil && model.pendingQuestion == nil)
    }

    @MainActor static func duplicateSend() async {
        let service = FakeSchoolBrainService()
        service.askResults = [.success(msg("a1", "assistant", "Відповідь"))]
        let release = AsyncGate()
        service.gate = { await release.wait() }
        let model = SchoolBrainChatModel(service: service)
        model.draft = "Привіт"
        let first = Task { await model.send() }
        while !model.isSending { await Task.yield() }
        precondition(model.pendingQuestion == "Привіт" && model.draft.isEmpty)
        model.draft = "Привіт"
        precondition(!model.canSend)
        await model.send()
        precondition(service.asked.count == 1)
        await release.open()
        await first.value
        precondition(service.asked.count == 1)
        precondition(model.messages.count == 2)
    }

    @MainActor static func failureAndRetry() async {
        let service = FakeSchoolBrainService()
        service.askResults = [.failure(SchoolBrainHTTPError(status: 503)), .success(msg("a1", "assistant", "Готово"))]
        let model = SchoolBrainChatModel(service: service)
        model.draft = "Які нові повідомлення?"
        await model.send()
        precondition(model.sendFailure == .server)
        precondition(model.draft == "Які нові повідомлення?", "draft must be recoverable")
        precondition(model.messages.isEmpty, "no false-success or duplicate history")
        precondition(model.failedQuestion == "Які нові повідомлення?" && !model.isSending)
        await model.retry()
        precondition(model.sendFailure == nil && model.failedQuestion == nil)
        precondition(model.messages.map(\.content) == ["Які нові повідомлення?", "Готово"])
        precondition(model.draft.isEmpty, "draft cleared after the retried question was answered")
        precondition(service.asked == ["Які нові повідомлення?", "Які нові повідомлення?"])

        // A new draft typed after a failure is not overwritten by the restored one.
        let service2 = FakeSchoolBrainService()
        service2.askResults = [.failure(SchoolBrainHTTPError(status: 403))]
        let model2 = SchoolBrainChatModel(service: service2)
        model2.draft = "Перше"
        await model2.send()
        precondition(model2.sendFailure == .forbidden && !(model2.sendFailure?.isRetryable ?? true))
        model2.dismissError()
        precondition(model2.sendFailure == nil && model2.failedQuestion == nil)
    }

    @MainActor static func history() async {
        let service = FakeSchoolBrainService()
        service.conversation = [msg("1", "user", "Питання"), msg("2", "assistant", "Відповідь")]
        let model = SchoolBrainChatModel(service: service)
        await model.load()
        precondition(model.messages.count == 2 && model.loadState == .loaded)
        await model.load()
        precondition(model.messages.count == 2, "reload must not duplicate history")

        let failing = FakeSchoolBrainService()
        failing.conversationError = SchoolBrainHTTPError(status: 401)
        let fresh = SchoolBrainChatModel(service: failing)
        await fresh.load()
        precondition(fresh.loadState == .failed(.unauthorized))
        fresh.draft = "Можна писати"
        precondition(fresh.canSend, "composer stays usable when history failed to load")

        failing.conversationError = URLError(.notConnectedToInternet)
        let kept = SchoolBrainChatModel(service: service)
        await kept.load()
        service.conversationError = URLError(.notConnectedToInternet)
        await kept.load()
        precondition(kept.messages.count == 2 && kept.loadState == .loaded, "offline refresh keeps shown history")
    }

    @MainActor static func sourceResolutionThroughModel() async {
        let service = FakeSchoolBrainService()
        let refs: [[String: String]] = [["type": "letter", "id": "L1"], ["type": "letter", "id": "L1"], ["type": "message", "id": "M9"]]
        service.conversation = [msg("1", "user", "q", refs: refs), msg("2", "assistant", "a", refs: refs)]
        service.catalog = [SchoolBrainSourceInfo(id: "L1", type: "letter", title: "Elternbrief", date: Date(timeIntervalSince1970: 1_760_000_000))]
        let model = SchoolBrainChatModel(service: service)
        await model.load()
        precondition(model.sourceRows(for: model.messages[0]).isEmpty, "user messages have no sources")
        let rows = model.sourceRows(for: model.messages[1])
        precondition(rows.count == 2 && rows[0].displayTitle == "Elternbrief" && rows[0].date != nil)
        precondition(rows[1].title == nil)
    }
}

actor AsyncGate {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async { if opened { return }; await withCheckedContinuation { waiters.append($0) } }
    func open() { opened = true; waiters.forEach { $0.resume() }; waiters.removeAll() }
}
