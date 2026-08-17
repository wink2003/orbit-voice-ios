import LiveKit
import SwiftUI

struct AppView: View {
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var localMedia: LocalMedia
    @FocusState private var keyboardFocus: Bool
    @Namespace private var namespace
    @AppStorage("orbit.appearance") private var appearance = "system"

    var body: some View {
        TabView {
            OrbitChatsView()
                .tabItem { Label("Чат", systemImage: "message") }
            voice()
                .tabItem { Label("Голос", systemImage: "waveform") }
            FamilyHubView()
                .tabItem { Label("Сім’я", systemImage: "person.3") }
            OrbitCalendarView()
                .tabItem { Label("Календар", systemImage: "calendar") }
            OrbitSettingsView()
                .tabItem { Label("Налаштування", systemImage: "gearshape") }
        }
        .environment(\.namespace, namespace)
        .preferredColorScheme(preferredColorScheme)
    }

    private var preferredColorScheme: ColorScheme? {
        switch appearance {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    private func voice() -> some View {
        ZStack(alignment: .top) {
            if session.isConnected {
                VoiceInteractionView()
                    .overlay(alignment: .bottom) {
                        agentListening().padding()
                    }
            } else {
                StartView(isConnectingAutomatically: false)
            }
            errors()
        }
        .safeAreaInset(edge: .bottom) {
            if session.isConnected, !keyboardFocus {
                ControlBar(chat: .constant(false))
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
        .background(.bg1)
        .animation(.default, value: session.isConnected)
        .animation(.default, value: session.error?.localizedDescription)
        .animation(.default, value: session.agent.error?.localizedDescription)
    }

    @ViewBuilder
    private func errors() -> some View {
        if let error = session.error {
            ErrorView(error: error) { session.dismissError() }
        }
        if let agentError = session.agent.error {
            ErrorView(error: agentError) { Task { await OrbitRuntime.shared.endVoiceSession() } }
        }
        if let mediaError = localMedia.error {
            ErrorView(error: mediaError) { localMedia.dismissError() }
        }
    }

    private func agentListening() -> some View {
        ZStack {
            if session.messages.isEmpty,
               !localMedia.isCameraEnabled,
               !localMedia.isScreenShareEnabled
            {
                Group {
                    if session.agent.isConnected {
                        Text("agent.listening")
                    } else {
                        Text("agent.waiting")
                    }
                }
                .font(.system(size: 15))
                .shimmering()
                .transition(.blurReplace)
            }
        }
        .animation(.default, value: session.messages.isEmpty)
        .animation(.default, value: session.agent.isConnected)
    }
}
