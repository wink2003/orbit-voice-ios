import SwiftUI

@main
struct OrbitVoiceApp: App {
    @StateObject private var session = OrbitVoiceSession()

    var body: some Scene {
        WindowGroup {
            Group {
                if session.isPaired {
                    VoiceView(session: session)
                } else {
                    PairingView(session: session)
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}
