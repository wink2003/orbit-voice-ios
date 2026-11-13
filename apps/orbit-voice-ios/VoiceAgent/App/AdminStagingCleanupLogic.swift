import Foundation

/// Pure helpers for the manual release-staging cleanup in the Admin panel (no networking, no UI): unit-tested in CI.
enum AdminStagingCleanupLogic {
    static func message(forError code: String?) -> String {
        switch code {
        case "nothing_to_prune": return "Нічого прибирати: усе свіже або захищене."
        case "plan_changed": return "План змінився. Закрийте вікно і спробуйте ще раз."
        case "cleanup_already_running": return "Очищення вже виконується."
        case "cleanup_action_expired": return "Підтвердження прострочилось. Підготуйте очищення ще раз."
        case "refused": return "Сервер відмовив: триває реліз або церемонія. Спробуйте пізніше."
        case "staging_preview_unavailable": return "Не вдалося підготувати план очищення."
        case "forbidden": return "Недоступно для цього профілю."
        default: return "Не вдалося виконати очищення."
        }
    }

    static func categoryTitle(_ id: String) -> String {
        switch id {
        case "oci-staging": return "Образи релізів (OCI)"
        case "ipa-staging": return "Збірки iOS (IPA)"
        default: return id
        }
    }

    static func bytesText(_ value: Double) -> String {
        if value <= 0 { return "0 МБ" }
        let mb = value / 1_048_576
        if mb < 1024 { return String(format: "%.0f МБ", mb) }
        return String(format: "%.2f ГБ", mb / 1024)
    }

    /// "56 каталогів · 2.48 ГБ"
    static func summary(count: Int, bytes: Double) -> String {
        "\(count) \(AdminHealthLogic.plural(count, "каталог", "каталоги", "каталогів")) · \(bytesText(bytes))"
    }

    /// Body of the server error JSON → code (nil when not parseable).
    static func errorCode(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["error"] as? String
    }
}

/// Labels for the Agent card (fixed Ukrainian wording; unknown codes are shown as-is, they are code-like and bounded).
enum AdminAgentLabels {
    static func failure(_ code: String) -> String {
        switch code {
        case "planner_invalid_output": return "модель дала неприпустиму відповідь"
        case "planner_provider_error": return "помилка провайдера моделі"
        case "planner_timeout": return "таймаут моделі"
        case "step_budget_exceeded": return "вичерпано бюджет кроків"
        default: return code
        }
    }
    static func model(_ binding: String) -> String {
        if binding.hasPrefix("google_gemini") { return "Gemini" }
        if binding.hasPrefix("openrouter") { return "OpenRouter (резерв)" }
        return binding
    }
}
