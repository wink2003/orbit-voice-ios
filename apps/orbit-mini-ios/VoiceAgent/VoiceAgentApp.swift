import LiveKit
import SwiftUI

@main
struct VoiceAgentApp: App {
    @StateObject private var authentication: OrbitAuthentication
    private let session: Session
    private let localMedia: LocalMedia
    private let audioOptions: AudioOptions

    init() {
        let runtime = OrbitRuntime.shared
        // Install the public AVAudioSession interruption observer as the app
        // starts, before an App Intent requests a microphone session.
        _ = OrbitMiniVoiceCoordinator.shared
        _authentication = StateObject(wrappedValue: runtime.authentication)
        session = runtime.session
        localMedia = runtime.localMedia
        audioOptions = runtime.audioOptions
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
                // Persistent conversations live in the native «Чати» tab.
                // The temporary LiveKit transcript UI is intentionally hidden.
                .environment(\.textEnabled, false)
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
