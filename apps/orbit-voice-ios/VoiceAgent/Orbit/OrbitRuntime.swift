import LiveKit

@MainActor
final class OrbitRuntime {
    static let shared = OrbitRuntime()

    let authentication: OrbitAuthentication
    let session: Session
    let localMedia: LocalMedia
    let audioOptions: AudioOptions

    private init() {
        authentication = OrbitAuthentication()

        let session = Session(
            tokenSource: OrbitTokenSource(),
            options: SessionOptions(room: Room(roomOptions: RoomOptions(
                defaultScreenShareCaptureOptions: ScreenShareCaptureOptions(useBroadcastExtension: true)
            )))
        )
        self.session = session

        let localMedia = LocalMedia(session: session)
        self.localMedia = localMedia
        audioOptions = AudioOptions(localMedia: localMedia)

        // Main Orbit must be a quiet citizen until the person explicitly
        // starts Voice. Configuring LiveKit's engine as available here can
        // activate the shared AVAudioSession during ordinary app launch and
        // duck playback from another app.
        configureAudioForIdle()
    }

    /// Starts the Main-only voice session after an explicit user/AppIntent
    /// request. No Main screen should call `session.start()` directly.
    func startVoiceSession() async {
        configureAudioForVoiceStart()
        await session.start()
    }

    /// Releases Main Orbit's LiveKit audio ownership after a normal stop.
    /// LiveKit ends the active session first; disabling the engine afterwards
    /// prevents idle Chat/Family/Settings use from retaining an audio session.
    func endVoiceSession() async {
        await session.end()
        session.restoreMessageHistory([])
        configureAudioForIdle()
    }

    private func configureAudioForVoiceStart() {
        AudioManager.shared.audioSession.isAutomaticConfigurationEnabled = true
        try? AudioManager.shared.setEngineAvailability(.default)
    }

    private func configureAudioForIdle() {
        AudioManager.shared.audioSession.isAutomaticConfigurationEnabled = false
        try? AudioManager.shared.setEngineAvailability(.none)
    }
}
