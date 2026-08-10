import LiveKit
import SwiftUI

struct AppView: View {
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var localMedia: LocalMedia
    @Environment(\.scenePhase) private var scenePhase

    @State private var isAutoStarting = false
    @State private var hasScheduledAutomaticStart = false
    @FocusState private var keyboardFocus: Bool
    @Namespace private var namespace

    var body: some View {
        TabView {
            voice()
                .tabItem { Label("Orbit", systemImage: "waveform") }
            OrbitChatsView()
                .tabItem { Label("Чати", systemImage: "message") }
        }
        .environment(\.namespace, namespace)
        .task {
            #if !ORBIT_CALLKIT_ONLY
            await autoStartIfNeeded()
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            #if !ORBIT_CALLKIT_ONLY
            guard phase == .active else { return }
            Task { await autoStartIfNeeded() }
            #endif
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
                StartView(isConnectingAutomatically: isAutoStarting)
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

    @MainActor
    private func autoStartIfNeeded() async {
        guard !session.isConnected,
              !isAutoStarting,
              !hasScheduledAutomaticStart
        else { return }

        // Give iOS a short moment to activate the audio session, then join
        // LiveKit directly.  This is intentionally not a CallKit transaction.
        hasScheduledAutomaticStart = true
        isAutoStarting = true
        defer { isAutoStarting = false }

        try? await Task.sleep(for: .milliseconds(750))
        guard !Task.isCancelled, !session.isConnected else { return }
        await session.start()
    }

    @ViewBuilder
    private func errors() -> some View {
        if let error = session.error {
            ErrorView(error: error) { session.dismissError() }
        }
        if let agentError = session.agent.error {
            ErrorView(error: agentError) { Task { await session.end() } }
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
