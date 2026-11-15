import SwiftUI

/// Admin «AI-моделі» (owner-only): per task the current model chain, price and 7-day usage; «Порівняти» runs a synthetic benchmark on chosen
/// candidates; a switch is proposed only for models that PASSED, and applied after an in-app confirmation (no Passkey, owner decision 2026-11-15).
@MainActor final class AIModelsStore: ObservableObject {
    @Published private(set) var overview: AIModelsOverview?
    @Published private(set) var job: AIBenchJob?
    @Published private(set) var proposal: AIModelProposal?
    @Published private(set) var message: String?
    @Published private(set) var isBusy = false
    @Published private(set) var appliedNotice: String?

    private struct Failure: Error { let code: String? }

    func load() async {
        do { overview = try await request("", method: "GET", body: nil, decode: AIModelsOverview.self); job = overview?.lastJob; message = nil }
        catch let failure as Failure { message = AdminAIModelsLogic.message(forError: failure.code) }
        catch { message = AdminAIModelsLogic.message(forError: nil) }
    }

    /// Starts a benchmark and polls until it finishes (at most ~6 minutes).
    func compare(models: [String]) async {
        guard !isBusy, !models.isEmpty else { return }
        isBusy = true; message = nil; defer { isBusy = false }
        do {
            var current = try await request("/compare", method: "POST", body: ["models": models], decode: AIBenchJob.self)
            job = current
            var polls = 0
            while current.status == "running" && polls < 120 {
                try await Task.sleep(nanoseconds: 3_000_000_000)
                current = try await request("/compare/\(current.id)", method: "GET", body: nil, decode: AIBenchJob.self)
                job = current; polls += 1
            }
            if current.status == "failed" { message = AdminAIModelsLogic.message(forError: nil) }
        } catch let failure as Failure { message = AdminAIModelsLogic.message(forError: failure.code) }
        catch { message = AdminAIModelsLogic.message(forError: nil) }
    }

    func propose(taskId: String, primary: String, fallbacks: [String]) async {
        guard !isBusy else { return }
        isBusy = true; message = nil; defer { isBusy = false }
        do { proposal = try await request("/proposals", method: "POST", body: ["task_id": taskId, "primary": primary, "fallbacks": fallbacks], decode: AIModelProposal.self) }
        catch let failure as Failure { message = AdminAIModelsLogic.message(forError: failure.code) }
        catch { message = AdminAIModelsLogic.message(forError: nil) }
    }

    func confirm() async {
        guard let proposal, !isBusy else { return }
        isBusy = true; message = nil; defer { isBusy = false }
        do {
            _ = try await request("/proposals/\(proposal.id)/confirm", method: "POST", body: [:], decode: Applied.self)
            appliedNotice = "Модель змінено: \(AdminAIModelsLogic.taskTitle(proposal.taskId))"
            self.proposal = nil
            await load()
        } catch let failure as Failure { message = AdminAIModelsLogic.message(forError: failure.code) }
        catch { message = AdminAIModelsLogic.message(forError: nil) }
    }

    func cancelProposal() async {
        guard let proposal else { return }
        _ = try? await request("/proposals/\(proposal.id)/cancel", method: "POST", body: [:], decode: Cancelled.self)
        self.proposal = nil
    }

    func rollback(taskId: String) async {
        guard !isBusy else { return }
        isBusy = true; message = nil; defer { isBusy = false }
        do {
            _ = try await request("/rollback", method: "POST", body: ["task_id": taskId], decode: Applied.self)
            appliedNotice = "Відкат виконано: \(AdminAIModelsLogic.taskTitle(taskId))"
            await load()
        } catch let failure as Failure { message = AdminAIModelsLogic.message(forError: failure.code) }
        catch { message = AdminAIModelsLogic.message(forError: nil) }
    }

    func clearNotice() { appliedNotice = nil }

    private struct Applied: Decodable { let policyVersion: Int? }
    private struct Cancelled: Decodable { let cancelled: Bool? }

    private func request<T: Decodable>(_ path: String, method: String, body: [String: Any]?, decode: T.Type) async throws -> T {
        guard let token = KeychainStore.readMainBearerToken(), let url = URL(string: "https://voice.orbit.opik.net/api/server/overview/ai-models\(path)") else { throw Failure(code: nil) }
        var request = URLRequest(url: url); request.httpMethod = method; request.timeoutInterval = 60
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body { request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw Failure(code: nil) }
        guard (200..<300).contains(status) else { throw Failure(code: AdminAIModelsLogic.errorCode(from: data)) }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

struct AdminAIModelsCard: View {
    @ObservedObject var store: AIModelsStore
    @State private var comparing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("AI-моделі", systemImage: "cpu").font(.headline)
            if let overview = store.overview {
                ForEach(overview.tasks) { task in taskBlock(task) }
                Button { comparing = true } label: {
                    Label("Порівняти моделі", systemImage: "chart.bar.doc.horizontal").frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.bordered).disabled(store.isBusy)
            } else if store.message == nil {
                Text("Завантаження…").font(.caption).foregroundStyle(Routes05Tokens.secondary)
            }
            if let notice = store.appliedNotice { Text(notice).font(.caption).foregroundStyle(.green) }
            if let message = store.message { Text(message).font(.caption).foregroundStyle(.red) }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
        .background(Routes05Tokens.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Routes05Tokens.rule, lineWidth: 1))
        .task { await store.load() }
        .sheet(isPresented: $comparing) { AIModelsCompareSheet(store: store, isPresented: $comparing) }
        .sheet(isPresented: Binding(get: { store.proposal != nil }, set: { if !$0 { Task { await store.cancelProposal() } } })) { AIModelsConfirmSheet(store: store) }
    }

    @ViewBuilder private func taskBlock(_ task: AIModelTask) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(AdminAIModelsLogic.taskTitle(task.taskId)).font(.subheadline.weight(.semibold))
            Text(AdminAIModelsLogic.chainText(primary: task.primary, fallbacks: task.fallbacks)).font(.caption)
            Text(AdminAIModelsLogic.priceText(inPerM: task.primary.inPerM, outPerM: task.primary.outPerM)).font(.caption).foregroundStyle(Routes05Tokens.secondary)
            Text(AdminAIModelsLogic.usageText(task.usage7d)).font(.caption2).foregroundStyle(Routes05Tokens.secondary)
            if task.switchable {
                Button("Відкотити до попередньої версії") { Task { await store.rollback(taskId: task.taskId) } }
                    .font(.caption).disabled(store.isBusy)
            }
        }
    }
}

struct AIModelsCompareSheet: View {
    @ObservedObject var store: AIModelsStore
    @Binding var isPresented: Bool
    @State private var selected: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                if let overview = store.overview {
                    Section("Кандидати (структурований вивід, найдешевші першими; максимум 6)") {
                        ForEach(overview.candidates) { c in
                            Button {
                                if selected.contains(c.id) { selected.remove(c.id) } else if selected.count < 6 { selected.insert(c.id) }
                            } label: {
                                HStack {
                                    Image(systemName: selected.contains(c.id) ? "checkmark.circle.fill" : "circle")
                                    VStack(alignment: .leading) {
                                        Text(c.id).font(.subheadline)
                                        Text(AdminAIModelsLogic.priceText(inPerM: c.inPerM, outPerM: c.outPerM)).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                    Section("Тест") {
                        Button(store.isBusy ? "Тест виконується…" : "Запустити тест (синтетичні дані, до $0.10 на модель)") { Task { await store.compare(models: Array(selected)) } }
                            .disabled(selected.isEmpty || store.isBusy)
                        if let job = store.job {
                            ForEach(job.results) { r in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(r.model).font(.subheadline.weight(.semibold))
                                    Text(AdminAIModelsLogic.resultText(r)).font(.caption).foregroundStyle(r.pass ? .green : .orange)
                                    if r.pass {
                                        HStack {
                                            ForEach(overview.tasks.filter(\.switchable)) { task in
                                                Button("Основна: \(AdminAIModelsLogic.taskTitle(task.taskId))") { Task { await store.propose(taskId: task.taskId, primary: r.model, fallbacks: task.fallbacks.compactMap(\.model)) } }
                                                    .font(.caption2).buttonStyle(.bordered).disabled(store.isBusy)
                                            }
                                        }
                                    }
                                }
                            }
                            if job.status == "running" { ProgressView("Порівняння…") }
                        }
                    }
                }
                if let message = store.message { Text(message).font(.caption).foregroundStyle(.red) }
            }
            .navigationTitle("Порівняння моделей").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { isPresented = false } } }
        }
    }
}

struct AIModelsConfirmSheet: View {
    @ObservedObject var store: AIModelsStore
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                if let p = store.proposal {
                    Text(AdminAIModelsLogic.taskTitle(p.taskId)).font(.title3.weight(.semibold))
                    LabeledContent("Було", value: ([p.current.primary] + p.current.fallbacks).joined(separator: " → "))
                    ForEach(p.proposed) { item in
                        LabeledContent(item.model, value: AdminAIModelsLogic.priceText(inPerM: item.inPerM, outPerM: item.outPerM))
                        if let per1000 = AdminAIModelsLogic.per1000Text(item.costPer1000) { Text(per1000).font(.caption).foregroundStyle(.secondary) }
                    }
                    Text("Тест: \(p.summary)").font(.footnote).foregroundStyle(.secondary)
                    Text("Зміна створює нову версію політики; попередню можна повернути кнопкою «Відкотити».").font(.footnote).foregroundStyle(.secondary)
                    if let message = store.message { Text(message).font(.caption).foregroundStyle(.red) }
                    Spacer()
                    HStack {
                        Button("Скасувати") { Task { await store.cancelProposal() } }.buttonStyle(.bordered)
                        Spacer()
                        Button(store.isBusy ? "Застосування…" : "Застосувати") { Task { await store.confirm() } }.buttonStyle(.borderedProminent).disabled(store.isBusy)
                    }
                }
            }.padding(20).navigationTitle("Зміна моделі").navigationBarTitleDisplayMode(.inline)
        }
    }
}
