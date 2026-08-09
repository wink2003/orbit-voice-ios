import LiveKit
import SwiftUI

@main
struct VoiceAgentApp: App {
    @StateObject private var authentication: OrbitAuthentication
    #if !ORBIT_CALLKIT_ONLY
    private let session: Session
    private let localMedia: LocalMedia
    private let audioOptions: AudioOptions
    #endif

    init() {
        #if ORBIT_CALLKIT_ONLY
        _authentication = StateObject(wrappedValue: OrbitAuthentication())
        _ = OrbitNativeCallManager.shared
        #else
        let runtime = OrbitRuntime.shared
        _authentication = StateObject(wrappedValue: runtime.authentication)
        session = runtime.session
        localMedia = runtime.localMedia
        audioOptions = runtime.audioOptions
        #endif
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if authentication.isPaired {
                    #if ORBIT_CALLKIT_ONLY
                    OrbitCallKitView()
                    #else
                    AppView()
                    #endif
                } else {
                    PairingView()
                }
            }
                #if !ORBIT_CALLKIT_ONLY
                .environmentObject(session)
                .environmentObject(localMedia)
                .environmentObject(audioOptions)
                #endif
                .environmentObject(authentication)
                #if !ORBIT_CALLKIT_ONLY
                .environment(\.voiceEnabled, true)
                .environment(\.videoEnabled, false)
                .environment(\.textEnabled, true)
                #endif
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
