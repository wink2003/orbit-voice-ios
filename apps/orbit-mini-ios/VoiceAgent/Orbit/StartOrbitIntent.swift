import AppIntents

struct StartOrbitMiniIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Orbit Mini"
    static let description = IntentDescription("Opens Orbit Mini and starts a hands-free voice session.")
    // This is the same public foreground invocation used by the working main
    // Orbit app. iOS must foreground an app once before microphone capture.
    static let openAppWhenRun = true

    // On iOS 26 this explicitly asks App Intents to run Mini in the foreground
    // before its privacy-protected microphone startup. Earlier systems retain
    // the long-standing openAppWhenRun behaviour above.
    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .foreground(.immediate) }

    @MainActor
    func perform() async throws -> some IntentResult {
        let logger = OrbitMiniDiagnosticLogger.shared
        logger.notice("AppIntent perform begin")
        OrbitMiniVoiceCoordinator.shared.requestStartFromAppIntent()
        logger.notice("AppIntent perform end; voice start is queued after result")
        return .result()
    }
}

struct StopOrbitMiniIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Orbit Mini"
    static let description = IntentDescription("Ends the active Orbit Mini voice session.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        await OrbitMiniVoiceCoordinator.shared.stop(reason: "app-intent")
        return .result()
    }
}

struct OrbitMiniShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartOrbitMiniIntent(),
            phrases: ["Start \(.applicationName)", "Talk to \(.applicationName)", "Open \(.applicationName)"],
            shortTitle: "Start Orbit Mini",
            systemImageName: "waveform.circle.fill"
        )
        AppShortcut(
            intent: StopOrbitMiniIntent(),
            phrases: ["Stop \(.applicationName)", "End \(.applicationName)"],
            shortTitle: "Stop Orbit Mini",
            systemImageName: "stop.circle.fill"
        )
    }
}
