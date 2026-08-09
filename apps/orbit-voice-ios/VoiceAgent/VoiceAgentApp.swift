import LiveKit
import SwiftUI

@main
struct VoiceAgentApp: App {
    @StateObject private var authentication: OrbitAuthentication
    private let session: Session
    private let localMedia: LocalMedia
    private let audioOptions: AudioOptions

    init() {
        _authentication = StateObject(wrappedValue: OrbitAuthentication())
        // The audio options panel applies its selection when the microphone
        // track is created. To guarantee that the very first captured frames
        // already use custom processing options, set them as room defaults
        // here instead, e.g.
        // RoomOptions(defaultAudioCaptureOptions: AudioCaptureOptions(echoCancellationMode: .software, ...))
        session = Session(
            tokenSource: OrbitTokenSource(),
            options: SessionOptions(room: Room(roomOptions: RoomOptions(
                defaultScreenShareCaptureOptions: ScreenShareCaptureOptions(useBroadcastExtension: true)
            )))
        )
        localMedia = LocalMedia(session: session)
        audioOptions = AudioOptions(localMedia: localMedia)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if authentication.isPaired {
                    AppView()
                } else {
                    PairingView()
                }
            }
                .environmentObject(session)
                .environmentObject(localMedia)
                .environmentObject(audioOptions)
                .environmentObject(authentication)
                .environment(\.voiceEnabled, true)
                .environment(\.videoEnabled, false)
                .environment(\.textEnabled, true)
        }
        #if os(macOS)
        .defaultSize(width: 900, height: 900)
        #endif
        #if os(visionOS)
        .windowStyle(.plain)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1500, height: 500)
        #endif
    }
}
