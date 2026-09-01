import AppIntents

// Retained for compatibility with any existing user-created shortcuts, but
// intentionally not exposed through the app's default shortcut list.
struct StartOrbitMiniIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Orbit Mini"
    static let description = IntentDescription("Opens Orbit Mini and starts a hands-free voice session.")
    static let openAppWhenRun = true

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .foreground(.immediate) }

    @MainActor
    func perform() async throws -> some IntentResult {
        OrbitMiniVoiceCoordinator.shared.requestStartFromAppIntent()
        return .result()
    }
}

// Retained as an implementation for existing shortcuts; not advertised as an
// AppShortcut so the default external surface stays minimal.
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

/// Starts Mini through the existing foreground-activation and voice-session path.
struct StartOrbitMiniHandsFreeIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Orbit Mini Hands-Free"
    static let description = IntentDescription("Opens Orbit Mini and starts a hands-free voice session.")
    static let openAppWhenRun = true

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .foreground(.immediate) }

    @MainActor
    func perform() async throws -> some IntentResult {
        let logger = OrbitMiniDiagnosticLogger.shared
        logger.notice("AppIntent hands-free perform begin")
        OrbitMiniVoiceCoordinator.shared.requestStartFromAppIntent()
        logger.notice("AppIntent hands-free perform end; external Shortcuts may handle return")
        return .result()
    }
}

struct OrbitMiniShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartOrbitMiniHandsFreeIntent(),
            phrases: ["Start hands-free \(.applicationName)"],
            shortTitle: "Start Orbit Mini Hands-Free",
            systemImageName: "arrow.uturn.backward.circle.fill"
        )
    }
}
