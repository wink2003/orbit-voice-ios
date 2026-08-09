import LiveKit

@MainActor
final class OrbitRuntime {
    static let shared = OrbitRuntime()

    let authentication: OrbitAuthentication
    let session: Session
    let localMedia: LocalMedia
    let audioOptions: AudioOptions
    let callManager: OrbitCallManager

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
        callManager = OrbitCallManager(session: session)
    }
}
