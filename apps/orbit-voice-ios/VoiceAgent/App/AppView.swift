import LiveKit
import SwiftUI

struct AppView: View {
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var localMedia: LocalMedia
    @Environment(\.scenePhase) private var scenePhase

    @State private var chat: Bool = false
    @State private var isAutoStarting = false
    @State private var hasScheduledAutomaticStart = false
    @FocusState private var keyboardFocus: Bool
    @Namespace private var namespace

    var body: some View {
        ZStack(alignment: .top) {
            if session.isConnected {
                interactions()
            } else {
                start()
            }

            errors()
        }
        .environment(\.namespace, namespace)
        .task {
            await autoStartIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await autoStartIfNeeded() }
        }
        #if os(visionOS)
            .ornament(attachmentAnchor: .scene(.bottom)) {
                if session.isConnected {
                    ControlBar(chat: $chat)
                        .glassBackgroundEffect()
                }
            }
            .alert(session.error?.localizedDescription ?? "error.title", isPresented: .constant(session.error != nil)) {
                Button("error.ok") { session.dismissError() }
            }
            .alert(
                session.agent.error?.localizedDescription ?? "error.title",
                isPresented: .constant(session.agent.error != nil)
            ) {
                Button("error.ok") { Task { await OrbitRuntime.shared.callManager.endCall() } }
            }
            .alert(
                localMedia.error?.localizedDescription ?? "error.title",
                isPresented: .constant(localMedia.error != nil)
            ) {
                Button("error.ok") { localMedia.dismissError() }
            }
        #else
            .safeAreaInset(edge: .bottom) {
                    if session.isConnected, !keyboardFocus {
                        ControlBar(chat: $chat)
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }
                }
        #endif
                .background(.bg1)
                .animation(.default, value: chat)
                .animation(.default, value: session.isConnected)
                .animation(.default, value: session.error?.localizedDescription)
                .animation(.default, value: session.agent.error?.localizedDescription)
                .animation(.default, value: localMedia.isCameraEnabled)
                .animation(.default, value: localMedia.isScreenShareEnabled)
                .animation(.default, value: localMedia.error?.localizedDescription)
    }

    private func start() -> some View {
        StartView(isConnectingAutomatically: isAutoStarting)
            .onAppear {
                chat = false
            }
    }

    @MainActor
    private func autoStartIfNeeded() async {
        guard !session.isConnected,
              !isAutoStarting,
              !hasScheduledAutomaticStart
        else { return }

        // On an iPhone, the app needs a moment to become active before a
        // CallKit transaction or microphone session can start reliably.
        // Starting immediately made the automatic launch race the scene
        // activation, while pressing the visible button later worked.
        hasScheduledAutomaticStart = true
        isAutoStarting = true
        defer { isAutoStarting = false }

        try? await Task.sleep(for: .milliseconds(750))
        guard !Task.isCancelled, !session.isConnected else { return }
        try? await OrbitRuntime.shared.callManager.startCall()
    }

    @ViewBuilder
    private func interactions() -> some View {
        #if os(visionOS)
            VisionInteractionView(chat: chat, keyboardFocus: $keyboardFocus)
                .overlay(alignment: .bottom) {
                    agentListening()
                        .padding(16 * .grid)
                }
        #else
            if chat {
                TextInteractionView(keyboardFocus: $keyboardFocus)
            } else {
                VoiceInteractionView()
                    .overlay(alignment: .bottom) {
                        agentListening()
                            .padding()
                    }
            }
        #endif
    }

    @ViewBuilder
    private func errors() -> some View {
        #if !os(visionOS)
            if let error = session.error {
                ErrorView(error: error) { session.dismissError() }
            }

            if let agentError = session.agent.error {
                ErrorView(error: agentError) { Task { await OrbitRuntime.shared.callManager.endCall() }}
            }

            if let mediaError = localMedia.error {
                ErrorView(error: mediaError) { localMedia.dismissError() }
            }
        #endif
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
