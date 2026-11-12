import Foundation

/// Pure helpers for the School email channel (no UI, no networking): source titles, sender patterns, result wording.
nonisolated enum SchoolEmailLogic {
    /// "Schulmanager" for the provider, "Email" for the forwarded-mail channel; unknown sources are shown as they are.
    static func sourceTitle(_ source: String) -> String {
        switch source.lowercased() {
        case "schulmanager": return "Schulmanager"
        case "email": return "Email"
        default: return source
        }
    }

    /// "@school.de" for "Frau.A@School.de"; nil when the address has no usable domain.
    static func domainPattern(for address: String) -> String? {
        let a = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !a.contains(where: \.isWhitespace), let at = a.lastIndex(of: "@") else { return nil }
        let domain = a[a.index(after: at)...]
        guard domain.contains("."), !domain.hasPrefix("."), !domain.hasSuffix("."), !domain.contains(" "), !domain.contains("@") else { return nil }
        return "@" + domain
    }

    static func exactPattern(for address: String) -> String? {
        let a = address.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return a.contains("@") && a.contains(" ") == false && domainPattern(for: a) != nil ? a : nil
    }

    /// Result line after approving/blocking a sender.
    static func decisionSummary(status: String, released: Int, rejected: Int, failed: Int) -> String {
        if status == "blocked" { return rejected > 0 ? "Заблоковано. Відхилено листів: \(rejected)." : "Заблоковано." }
        var parts = ["Дозволено."]
        if released > 0 { parts.append("Додано листів: \(released).") }
        if failed > 0 { parts.append("Не вдалося забрати з пошти: \(failed).") }
        return parts.joined(separator: " ")
    }

    /// One short status line for the mailbox card.
    static func statusLine(enabled: Bool, configured: Bool, lastError: String?) -> String {
        if !enabled { return "Вимкнено" }
        if !configured { return "Скриньку ще не підключено" }
        if let lastError, !lastError.isEmpty { return "Помилка останнього опитування: \(lastError)" }
        return "Працює"
    }
}
