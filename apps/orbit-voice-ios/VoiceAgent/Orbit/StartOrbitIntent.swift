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

struct EndOrbitIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Orbit"
    static let description = IntentDescription("Ends the active Orbit voice call in the background.")
    static let openAppWhenRun = false

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .background }

    func perform() async throws -> some IntentResult {
        await OrbitRuntime.shared.callManager.endCall()
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
        AppShortcut(
            intent: EndOrbitIntent(),
            phrases: [
                "Stop \(.applicationName)",
                "End \(.applicationName)",
                "Hang up \(.applicationName)",
            ],
            shortTitle: "Stop Orbit",
            systemImageName: "phone.down.fill"
        )
    }
}
