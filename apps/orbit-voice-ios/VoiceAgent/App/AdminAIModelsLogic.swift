import Foundation

/// AI model manager models + wording (pure, unit-tested in CI; networking lives in AdminAIModelsViews.swift).
/// Server: /api/server/overview/ai-models (owner-only). All dates are display strings (the server sends fractional seconds).
struct AIModelRef: Decodable, Equatable {
    let bindingId: String?
    let model: String?
    let name: String?
    let inPerM: Double?
    let outPerM: Double?
}

struct AIModelUsage: Decodable, Equatable {
    let calls: Int
    let ok: Int
    let cost: Double
    let p95: Int?
}

struct AIModelTask: Decodable, Equatable, Identifiable {
    let taskId: String
    let policyVersion: Int
    let fallbackMode: String
    let switchable: Bool
    let primary: AIModelRef
    let fallbacks: [AIModelRef]
    let usage7d: AIModelUsage
    var id: String { taskId }
}

struct AIModelCandidate: Decodable, Equatable, Identifiable {
    let id: String
    let name: String
    let inPerM: Double
    let outPerM: Double
    let context: Int
    let free: Bool
}

struct AIBenchResult: Decodable, Equatable, Identifiable {
    let model: String
    let pass: Bool
    let rel: String
    let intel: String
    let validRate: Double
    let seconds: Int
    let costUsd: Double?
    let costPer1000: Double?
    let capped: Bool
    var id: String { model }
}

struct AIBenchJob: Decodable, Equatable {
    let id: String
    let status: String
    let models: [String]
    let results: [AIBenchResult]
    let error: String?
}

struct AIModelsOverview: Decodable, Equatable {
    let tasks: [AIModelTask]
    let candidates: [AIModelCandidate]
    let lastJob: AIBenchJob?
}

struct AIModelProposal: Decodable, Equatable {
    struct Item: Decodable, Equatable, Identifiable {
        let model: String
        let name: String
        let inPerM: Double
        let outPerM: Double
        let costPer1000: Double?
        var id: String { model }
    }
    struct Current: Decodable, Equatable {
        let primary: String
        let fallbacks: [String]
        let policyVersion: Int
    }
    let id: String
    let taskId: String
    let current: Current
    let proposed: [Item]
    let summary: String
}

enum AdminAIModelsLogic {
    static func taskTitle(_ id: String) -> String {
        switch id {
        case "school.calendar_relevance": return "School: релевантність подій"
        case "school.intelligence": return "School: аналіз листів"
        default: return id
        }
    }

    /// "$0.04 / $0.08 за 1M" or "безкоштовно".
    static func priceText(inPerM: Double?, outPerM: Double?) -> String {
        guard let inPerM, let outPerM else { return "ціна невідома" }
        if inPerM == 0 && outPerM == 0 { return "безкоштовно" }
        return "\(money(inPerM)) / \(money(outPerM)) за 1M"
    }

    static func money(_ value: Double) -> String {
        if value >= 1 { return String(format: "$%.2f", value) }
        if value >= 0.1 { return String(format: "$%.3f", value) }
        return String(format: "$%.4f", value)
    }

    /// "$2.53 за 1000 викликів" (benchmark projection) or nil.
    static func per1000Text(_ value: Double?) -> String? {
        guard let value else { return nil }
        return value == 0 ? "$0 за 1000 викликів" : "\(money(value)) за 1000 викликів"
    }

    /// Paid models first (cheapest first, server order kept), then free ones.
    static func orderedCandidates(_ list: [AIModelCandidate]) -> [AIModelCandidate] {
        list.filter { !$0.free } + list.filter(\.free)
    }

    /// " · основна" / " · резерв" when the model is in a task's current chain.
    static func currentMark(_ model: String, tasks: [AIModelTask]) -> String {
        if tasks.contains(where: { $0.primary.model == model }) { return " · основна" }
        if tasks.contains(where: { $0.fallbacks.contains { $0.model == model } }) { return " · резерв" }
        return ""
    }

    static func chainText(primary: AIModelRef, fallbacks: [AIModelRef]) -> String {
        let main = primary.model ?? primary.name ?? "—"
        guard !fallbacks.isEmpty else { return main }
        return main + " → " + fallbacks.map { $0.model ?? $0.name ?? "—" }.joined(separator: " → ")
    }

    static func usageText(_ usage: AIModelUsage) -> String {
        guard usage.calls > 0 else { return "за 7 днів викликів не було" }
        let percent = Int((Double(usage.ok) / Double(usage.calls) * 100).rounded())
        var parts = ["\(usage.calls) викликів", "\(percent)% успішно", money(usage.cost)]
        if let p95 = usage.p95 { parts.append("p95 \(p95 / 1000) с") }
        return parts.joined(separator: " · ")
    }

    static func resultText(_ r: AIBenchResult) -> String {
        let verdict = r.pass ? "проходить" : "не проходить"
        var parts = [verdict, "події \(r.rel)", "листи \(r.intel)", "\(r.seconds) с"]
        if let c = per1000Text(r.costPer1000) { parts.append(c) }
        if r.capped { parts.append("зупинено за лімітом витрат") }
        return parts.joined(separator: " · ")
    }

    /// Models a task can be switched to: only those with a PASSING result in the last job.
    static func passingModels(_ job: AIBenchJob?) -> [String] {
        (job?.results ?? []).filter(\.pass).map(\.model)
    }

    static func message(forError code: String?) -> String {
        switch code {
        case "benchmark_required": return "Спершу пройдіть порівняння: для моделі потрібен успішний тест (не старший за 24 год)."
        case "benchmark_already_running": return "Порівняння вже виконується."
        case "model_not_in_catalog": return "Моделі немає в каталозі."
        case "invalid_models": return "Оберіть від 1 до 6 моделей."
        case "invalid_chain": return "Некоректний ланцюжок моделей."
        case "task_not_switchable": return "Для цієї задачі модель змінити не можна."
        case "proposal_expired": return "Підтвердження прострочилось. Підготуйте зміну ще раз."
        case "nothing_to_roll_back_to": return "Немає попередньої версії, до якої можна відкотити."
        case "forbidden": return "Недоступно для цього профілю."
        default: return "Не вдалося виконати. Спробуйте ще раз."
        }
    }

    static func errorCode(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["error"] as? String
    }
}
