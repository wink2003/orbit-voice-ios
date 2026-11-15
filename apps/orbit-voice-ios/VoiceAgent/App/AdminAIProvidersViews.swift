import SwiftUI

/// AI providers card (owner-only): shows whether a background provider was stopped after a billing/auth refusal and lets the owner
/// press «Старт» after fixing it (owner decision 2026-11-15: notify in Orbit + a start button instead of a silent timer).
/// Server: GET /api/server/overview/ai-providers, POST /api/server/overview/ai-providers/<provider>/resume.
private struct AIProvidersResponse: Decodable { let providers: [AIProviderState] }

@MainActor final class AIProvidersStore: ObservableObject {
    @Published private(set) var providers: [AIProviderState] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?

    func load() async {
        do { providers = try await request(path: "", method: "GET").providers; error = nil }
        catch { self.error = "Не вдалося отримати стан провайдерів." }
    }

    func resume(_ provider: String) async {
        guard !isLoading else { return }
        isLoading = true; defer { isLoading = false }
        do { providers = try await request(path: "/\(provider)/resume", method: "POST").providers; error = nil }
        catch { self.error = "Не вдалося запустити. Спробуйте ще раз." }
    }

    private func request(path: String, method: String) async throws -> AIProvidersResponse {
        guard let token = KeychainStore.readMainBearerToken(), let url = URL(string: "https://voice.orbit.opik.net/api/server/overview/ai-providers\(path)") else { throw URLError(.userAuthenticationRequired) }
        var request = URLRequest(url: url); request.httpMethod = method; request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if method == "POST" { request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = Data("{}".utf8) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else { throw URLError(.badServerResponse) }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AIProvidersResponse.self, from: data)
    }
}

struct AdminAIProvidersCard: View {
    @ObservedObject var store: AIProvidersStore
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("AI-провайдери", systemImage: "bolt.horizontal.circle").font(.headline)
            if store.providers.isEmpty && store.error == nil { Text("Завантаження…").font(.caption).foregroundStyle(Routes05Tokens.secondary) }
            ForEach(store.providers, id: \.provider) { state in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(AdminAIProvidersLogic.title(state.provider)).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(AdminAIProvidersLogic.statusText(state)).font(.caption).foregroundStyle(state.open ? .orange : .green).multilineTextAlignment(.trailing)
                    }
                    if state.open {
                        Text("Фонові задачі School Brain (релевантність подій, аналіз листів) не викликають цього провайдера, доки ви не натиснете «Старт».")
                            .font(.caption).foregroundStyle(Routes05Tokens.secondary).fixedSize(horizontal: false, vertical: true)
                        Button { Task { await store.resume(state.provider) } } label: {
                            Label(store.isLoading ? "Запуск…" : "Старт", systemImage: "play.fill").frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.borderedProminent).disabled(store.isLoading)
                    }
                }
            }
            if let error = store.error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
        .background(Routes05Tokens.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Routes05Tokens.rule, lineWidth: 1))
        .task { await store.load() }
    }
}
