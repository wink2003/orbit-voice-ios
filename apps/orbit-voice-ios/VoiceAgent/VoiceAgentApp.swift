import LiveKit
import SwiftUI

@main
struct VoiceAgentApp: App {
    @State private var schoolWidgetDeepLink: SchoolTasksWidgetDeepLink?
    @StateObject private var authentication: OrbitAuthentication
    @StateObject private var appLock: OrbitAppLock
    private let session: Session
    private let localMedia: LocalMedia
    private let audioOptions: AudioOptions

    init() {
        _ = SchoolNotificationCoordinator.shared
        let runtime = OrbitRuntime.shared
        _authentication = StateObject(wrappedValue: runtime.authentication)
        _appLock = StateObject(wrappedValue: runtime.appLock)
        session = runtime.session
        localMedia = runtime.localMedia
        audioOptions = runtime.audioOptions
    }

    var body: some Scene {
        WindowGroup {
            rootContent
                .onOpenURL(perform: handleOpenURL)
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
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--routes05-") }) {
            Routes05DebugRoot()
                .environmentObject(session)
                .environmentObject(localMedia)
                .environmentObject(audioOptions)
                .environmentObject(authentication)
                .environmentObject(appLock)
                .environment(\.voiceEnabled, true)
                .environment(\.videoEnabled, false)
                .environment(\.textEnabled, false)
        } else if ProcessInfo.processInfo.arguments.contains("--orbit-nova-fixture") {
            OrbitTodayView(open: { _ in }, displayName: "Олена", fixture: .demo)
        } else if ProcessInfo.processInfo.arguments.contains("--orbit-interpreter-lab") {
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
            if authentication.isPaired && appLock.isLocked {
                OrbitAppLockView()
            } else if authentication.isPaired {
                AppView(schoolWidgetDeepLink: $schoolWidgetDeepLink)
            } else {
                PairingView()
            }
        }
            .environmentObject(session)
            .environmentObject(localMedia)
            .environmentObject(audioOptions)
            .environmentObject(authentication)
            .environmentObject(appLock)
            .environment(\.voiceEnabled, true)
            .environment(\.videoEnabled, false)
            // Persistent conversations live in the native «Чати» tab.
            // The temporary LiveKit transcript UI is intentionally hidden.
            .environment(\.textEnabled, false)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await SchoolRemindersMirror.shared.syncIfEnabled() } }   // School ↔ Reminders mirror (opt-in)
                guard phase == .background || phase == .inactive else { return }
                appLock.lockForBackground(isVoiceActive: session.isConnected)
            }
            .onChange(of: session.isConnected) { was, connected in
                // A voice call may have changed tasks on the server (complete / reopen / move the day): reload School data when it ends.
                if was && !connected { NotificationCenter.default.post(name: .orbitSchoolMirrorApplied, object: nil) }
            }
            .task(id: session.isConnected) {
                // While a call is running the School lists may be on screen: a task changed by voice must show up within seconds, not only after hang-up.
                guard session.isConnected else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 6_000_000_000)
                    if Task.isCancelled { break }
                    NotificationCenter.default.post(name: .orbitSchoolMirrorApplied, object: nil)
                }
            }
            .onChange(of: authentication.isPaired) { _, paired in
                if !paired {
                    schoolWidgetDeepLink = nil
                    appLock.disable()
                }
            }
    }

    private func handleOpenURL(_ url: URL) {
        if let route = SchoolTasksWidgetDeepLink.parse(url) {
            schoolWidgetDeepLink = route
        }
    }

    @Environment(\.scenePhase) private var scenePhase
}

private struct OrbitAppLockView: View {
    @EnvironmentObject private var appLock: OrbitAppLock

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("Main Orbit заблоковано")
                    .font(.title2.weight(.semibold))
                Text("Розблокуйте застосунок, щоб продовжити.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Розблокувати") {
                    Task { _ = await appLock.unlock() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(appLock.isAuthenticating)
                if let lastError = appLock.lastError {
                    Text(lastError)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(32)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Main Orbit заблоковано")
    }
}
