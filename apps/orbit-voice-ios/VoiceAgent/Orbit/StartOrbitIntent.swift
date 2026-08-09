import AppIntents

struct StartOrbitIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Orbit"
    static let description = IntentDescription("Starts an Orbit voice call in the background.")
    static let openAppWhenRun = false

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .background }

    func perform() async throws -> some IntentResult {
        try await OrbitRuntime.shared.callManager.startCall()
        return .result()
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
