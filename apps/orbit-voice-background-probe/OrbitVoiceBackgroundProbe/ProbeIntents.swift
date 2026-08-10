import AppIntents

@available(iOS 26.0, *)
struct StartBackgroundMicrophoneTestIntent: AudioRecordingIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Start Background Microphone Test"
    static let description = IntentDescription("Attempts a background microphone capture without opening Orbit Voice Probe.")
    static var supportedModes: IntentModes { [.background] }

    func perform() async throws -> some IntentResult {
        try await BackgroundProbeRecorder.shared.start(origin: "AppIntent.background")
        return .result()
    }
}

@available(iOS 26.0, *)
struct StopBackgroundMicrophoneTestIntent: AudioRecordingIntent {
    static let title: LocalizedStringResource = "Stop Background Microphone Test"
    static let description = IntentDescription("Stops the Orbit Voice Probe microphone test.")
    static var supportedModes: IntentModes { [.background] }

    func perform() async throws -> some IntentResult {
        await BackgroundProbeRecorder.shared.stop(reason: "Stopped by App Intent")
        return .result()
    }
}

@available(iOS 26.0, *)
struct ProbeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartBackgroundMicrophoneTestIntent(),
            phrases: ["Start background microphone test in \(.applicationName)"],
            shortTitle: "Start background test",
            systemImageName: "mic.fill"
        )
        AppShortcut(
            intent: StopBackgroundMicrophoneTestIntent(),
            phrases: ["Stop background microphone test in \(.applicationName)"],
            shortTitle: "Stop background test",
            systemImageName: "stop.fill"
        )
    }
}
