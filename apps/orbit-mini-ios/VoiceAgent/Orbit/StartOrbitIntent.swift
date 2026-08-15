import AppIntents
import Foundation

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
        // Get Current App / Open App [PreviousApp] belong to the enclosing
        // user Shortcut. App Intents does not pass that variable or its Open
        // App result to Mini, so record the boundary without inventing a
        // recipient or leaking app history.
        logger.notice("previous-app capture category=external-unobservable restore=owned-by-shortcuts")
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

/// Starts Mini hands-free. Returning to a previous app is intentionally an
/// external Shortcuts/Automation responsibility; Mini keeps its own scene
/// and only owns the voice session lifecycle.
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
            intent: StartOrbitMiniIntent(),
            phrases: ["Start \(.applicationName)", "Talk to \(.applicationName)", "Open \(.applicationName)"],
            shortTitle: "Start Orbit Mini",
            systemImageName: "waveform.circle.fill"
        )
        AppShortcut(
            intent: StartOrbitMiniHandsFreeIntent(),
            phrases: ["Start hands-free \(.applicationName)"],
            shortTitle: "Start Orbit Mini Hands-Free",
            systemImageName: "arrow.uturn.backward.circle.fill"
        )
        AppShortcut(
            intent: StopOrbitMiniIntent(),
            phrases: ["Stop \(.applicationName)", "End \(.applicationName)"],
            shortTitle: "Stop Orbit Mini",
            systemImageName: "stop.circle.fill"
        )
    }
}
