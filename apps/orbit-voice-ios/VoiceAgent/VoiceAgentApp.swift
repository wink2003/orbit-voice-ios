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
        _authentication = StateObject(wrappedValue: runtime.authentication)
        session = runtime.session
        localMedia = runtime.localMedia
        audioOptions = runtime.audioOptions
    }

    var body: some Scene {
        WindowGroup {
            rootContent
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

    @ViewBuilder
    private var rootContent: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--orbit-interpreter-lab") {
            InterpreterLabView()
        } else {
            mainOrbitContent
        }
        #else
        mainOrbitContent
        #endif
    }

    private var mainOrbitContent: some View {
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
}
