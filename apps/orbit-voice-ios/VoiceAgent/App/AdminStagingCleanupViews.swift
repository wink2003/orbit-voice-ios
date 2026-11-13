import SwiftUI

/// Manual cleanup of release staging (owner-only, guarded): propose (server computes the plan) -> confirm sheet -> apply -> result.
struct StagingCleanupProposal: Decodable {
    struct Category: Decodable { let dirs: Int; let bytes: Double; let eligibleDirs: Int; let eligibleBytes: Double }
    let actionId: String
    let status: String
    let expiresAt: Date
    let eligibleCount: Int
    let eligibleBytes: Double
    let categories: [String: Category]
}

struct StagingCleanupResult: Decodable {
    let actionId: String?
    let status: String
    let removedCount: Int?
    let freedBytes: Double?
    let error: String?
}

@MainActor final class StagingCleanupStore: ObservableObject {
    @Published private(set) var proposal: StagingCleanupProposal?
    @Published private(set) var result: StagingCleanupResult?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?

    func propose() async {
        guard !isLoading else { return }
        isLoading = true; error = nil; result = nil
        defer { isLoading = false }
        do { proposal = try await request(path: "proposals", decode: StagingCleanupProposal.self) }
        catch let failure as Failure { error = AdminStagingCleanupLogic.message(forError: failure.code) }
        catch { self.error = AdminStagingCleanupLogic.message(forError: nil) }
    }

    func confirm() async {
        guard let proposal, !isLoading else { return }
        isLoading = true; error = nil
        defer { isLoading = false }
        do { result = try await request(path: "proposals/\(proposal.actionId)/confirm", decode: StagingCleanupResult.self) }
        catch let failure as Failure { error = AdminStagingCleanupLogic.message(forError: failure.code) }
        catch { self.error = AdminStagingCleanupLogic.message(forError: nil) }
    }

    func cancel() async {
        guard let proposal else { return }
        _ = try? await request(path: "proposals/\(proposal.actionId)/cancel", decode: StagingCleanupResult.self)
        self.proposal = nil
    }

    func clear() { proposal = nil; result = nil; error = nil }

    private struct Failure: Error { let code: String? }

    private func request<T: Decodable>(path: String, decode: T.Type) async throws -> T {
        guard let token = KeychainStore.readMainBearerToken(), let url = URL(string: "https://voice.orbit.opik.net/api/server/overview/staging-cleanup/\(path)") else { throw Failure(code: nil) }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = Data("{}".utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw Failure(code: nil) }
        guard (200..<300).contains(status) else { throw Failure(code: AdminStagingCleanupLogic.errorCode(from: data)) }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }
}

struct AdminStagingCleanupCard: View {
    @ObservedObject var store: StagingCleanupStore
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Staging релізів", systemImage: "tray.full").font(.headline)
            Text("Старі копії кандидатів завершених релізів. Прибираються лише завершені операції старші за 2 дні; щонеділі це робить таймер, тут можна запустити вручну.")
                .font(.caption).foregroundStyle(Routes05Tokens.secondary).fixedSize(horizontal: false, vertical: true)
            Button { Task { await store.propose() } } label: {
                Label(store.isLoading && store.proposal == nil ? "Підготовка…" : "Підготувати очищення", systemImage: "trash.slash").frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(.bordered).disabled(store.isLoading)
            if let error = store.error { Text(error).font(.caption).foregroundStyle(.red) }
            if let result = store.result, result.status == "completed" {
                Text("Очищено: \(AdminStagingCleanupLogic.summary(count: result.removedCount ?? 0, bytes: result.freedBytes ?? 0))").font(.caption).foregroundStyle(.green)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
        .background(Routes05Tokens.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Routes05Tokens.rule, lineWidth: 1))
    }
}

struct StagingCleanupConfirmationView: View {
    @ObservedObject var store: StagingCleanupStore
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if let result = store.result {
                    let done = result.status == "completed"
                    Label(done ? "Очищено" : "Не виконано", systemImage: done ? "checkmark.circle.fill" : "exclamationmark.triangle.fill").font(.title3.weight(.semibold)).foregroundStyle(done ? .green : .orange)
                    if done { Text("Видалено: \(AdminStagingCleanupLogic.summary(count: result.removedCount ?? 0, bytes: result.freedBytes ?? 0))") }
                    else { Text(AdminStagingCleanupLogic.message(forError: result.error)).foregroundStyle(.secondary) }
                    Spacer()
                    Button("Готово") { store.clear() }.buttonStyle(.borderedProminent)
                } else if let proposal = store.proposal {
                    Text("Буде видалено \(AdminStagingCleanupLogic.summary(count: proposal.eligibleCount, bytes: proposal.eligibleBytes)).").font(.headline)
                    ForEach(proposal.categories.keys.sorted(), id: \.self) { key in
                        if let c = proposal.categories[key], c.eligibleDirs > 0 {
                            LabeledContent(AdminStagingCleanupLogic.categoryTitle(key), value: AdminStagingCleanupLogic.summary(count: c.eligibleDirs, bytes: c.eligibleBytes))
                        }
                    }
                    Text("Лише завершені операції старші за 2 дні; найновіші 5 образів і 3 збірки iOS, а також усе незавершене чи невизначене залишаються. Відновити видалене не можна, але відкат релізів спирається на окремі архіви поза хостом.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let error = store.error { Text(error).font(.caption).foregroundStyle(.red) }
                    Spacer()
                    HStack {
                        Button("Скасувати") { Task { await store.cancel() } }.buttonStyle(.bordered)
                        Spacer()
                        Button(store.isLoading ? "Виконується…" : "Видалити") { Task { await store.confirm() } }.buttonStyle(.borderedProminent).tint(.red).disabled(store.isLoading)
                    }
                }
            }.padding(20).navigationTitle("Staging релізів").navigationBarTitleDisplayMode(.inline)
        }
    }
}
