import AppIntents

struct StartOrbitIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Orbit"
    static let description = IntentDescription("Opens Orbit and starts a voice conversation.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct OrbitShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartOrbitIntent(),
            phrases: [
                "Start \(.applicationName)",
                "Talk to \(.applicationName)",
                "Open \(.applicationName)",
            ],
            shortTitle: "Start Orbit",
            systemImageName: "waveform.circle.fill"
        )
    }
}
