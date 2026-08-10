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
struct StartForegroundBootstrapMicrophoneTestIntent: AudioRecordingIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Start Foreground Bootstrap Microphone Test"
    static let description = IntentDescription("Temporarily moves Orbit Voice Probe to the foreground to start microphone capture, then completes while recording continues.")
    static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }

    func perform() async throws -> some IntentResult {
        let initialMode = systemContext.currentMode
        await BackgroundProbeRecorder.shared.noteIntent("Intent entered; initialMode=\(initialMode)")

        if initialMode == .background {
            guard initialMode.canContinueInForeground else {
                await BackgroundProbeRecorder.shared.noteIntent("Foreground transition unavailable")
                throw ProbeError.foregroundUnavailable
            }
            await BackgroundProbeRecorder.shared.noteIntent("Requesting dynamic foreground transition")
            try await continueInForeground()
            await BackgroundProbeRecorder.shared.noteIntent("Foreground transition returned; currentMode=\(systemContext.currentMode)")
        } else {
            await BackgroundProbeRecorder.shared.noteIntent("Already executing in foreground")
        }

        try await BackgroundProbeRecorder.shared.startForegroundBackgroundTest()
        await BackgroundProbeRecorder.shared.noteIntent("Microphone capture confirmed; intent completing")
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
            intent: StartForegroundBootstrapMicrophoneTestIntent(),
            phrases: ["Start foreground bootstrap test in \(.applicationName)"],
            shortTitle: "Start foreground bootstrap",
            systemImageName: "mic.and.signal.meter"
        )
        AppShortcut(
            intent: StopBackgroundMicrophoneTestIntent(),
            phrases: ["Stop background microphone test in \(.applicationName)"],
            shortTitle: "Stop background test",
            systemImageName: "stop.fill"
        )
    }
}
