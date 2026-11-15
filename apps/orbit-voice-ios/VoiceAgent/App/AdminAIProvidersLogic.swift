import Foundation

/// AI providers state + wording (pure, unit-tested in CI; networking lives in AdminAIProvidersViews.swift).
struct AIProviderState: Decodable, Equatable {
    let provider: String
    let open: Bool
    let openedAt: Date?
    let lastStatus: Int?

    enum CodingKeys: String, CodingKey { case provider, open, openedAt = "opened_at", lastStatus = "last_status" }
}

/// Pure helpers (unit-tested): wording only, no networking.
enum AdminAIProvidersLogic {
    static func title(_ provider: String) -> String { provider == "openrouter" ? "OpenRouter" : provider }

    static func statusText(_ state: AIProviderState) -> String {
        guard state.open else { return "Працює" }
        switch state.lastStatus {
        case 402: return "Зупинено: немає кредитів або модель платна (HTTP 402)"
        case 401, 403: return "Зупинено: ключ доступу відхилено (HTTP \(state.lastStatus ?? 0))"
        default: return "Зупинено"
        }
    }

    /// Admin attention line for the dashboard list; nil when everything works.
    static func attention(_ states: [AIProviderState]) -> String? {
        let stopped = states.filter(\.open).map { title($0.provider) }
        return stopped.isEmpty ? nil : "\(stopped.joined(separator: ", ")): фонові задачі зупинено, натисніть «Старт»"
    }
}

