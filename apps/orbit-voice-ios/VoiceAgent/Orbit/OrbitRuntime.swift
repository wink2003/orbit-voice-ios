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

        // Orbit is an in-app LiveKit voice experience.  We deliberately keep
        // it outside CallKit: the app is lightweight, works as a normal app
        // and does not create a fake phone call in iOS.
        AudioManager.shared.audioSession.isAutomaticConfigurationEnabled = true
        try? AudioManager.shared.setEngineAvailability(.default)
    }
}
