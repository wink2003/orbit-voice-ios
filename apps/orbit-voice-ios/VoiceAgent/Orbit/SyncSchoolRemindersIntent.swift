import AppIntents

/// Shortcut / automation trigger: runs the School ↔ Reminders mirror once (owner request 2026-11-19).
/// Use it in Shortcuts → Automation (e.g. «Коли відкривається застосунок», at a time of day, or on arrival) → «Sync School Reminders».
/// Does nothing unless the user switched the mirror on in Orbit Settings (the permission prompt lives there).
struct SyncSchoolRemindersIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Sync School Reminders"
    nonisolated static let description = IntentDescription("Mirrors Orbit School tasks with the iCloud Reminders list «Школа» (both ways) once.")
    nonisolated static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let mirror = SchoolRemindersMirror.shared
        guard mirror.isEnabled else { return .result(dialog: "Дзеркало вимкнене. Увімкніть його в Orbit → Налаштування → Нагадування iCloud.") }
        await mirror.sync()
        switch mirror.phase {
        case .denied: return .result(dialog: "Немає доступу до Нагадувань. Дозвольте його в Налаштуваннях iPhone.")
        case let .failed(text): return .result(dialog: "Не вдалося синхронізувати: \(text)")
        default: return .result(dialog: "Готово. \(mirror.lastSummary)")
        }
    }
}

struct OrbitMainShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: SyncSchoolRemindersIntent(), phrases: ["Sync School reminders in \(.applicationName)"], shortTitle: "Школа ↔ Нагадування", systemImageName: "arrow.triangle.2.circlepath")
    }
}
