import Foundation
import LiveKit
import OSLog
import UIKit

/// A deliberately thin owner around the already-proven full Orbit `Session`.
/// Mini does not implement STT, VAD, TTS, or a second transport: LiveKit's
/// existing Orbit agent owns all of those behaviours.
@MainActor
final class OrbitMiniVoiceCoordinator: NSObject, ObservableObject {
    static let shared = OrbitMiniVoiceCoordinator()

    @Published private(set) var isStarting = false
    @Published private(set) var isTerminating = false
    @Published private(set) var lastError: String?

    private let runtime = OrbitRuntime.shared
    private let liveActivity = OrbitMiniLiveActivityManager.shared
    private let logger = Logger(subsystem: "net.opik.orbit.mini", category: "voice-session")

    private override init() {
        super.init()
        runtime.session.room.add(delegate: self)
    }

    var session: Session { runtime.session }
    var isVoiceActive: Bool { runtime.session.isConnected && !isTerminating }

    func start() async {
        guard runtime.authentication.isPaired else {
            lastError = "Спершу активуйте цей iPhone."
            return
        }
        guard !runtime.session.isConnected, !isStarting, !isTerminating else { return }
        isStarting = true
        lastError = nil
        await liveActivity.reconcileOrphans()
        logger.notice("voice start requested")
        await runtime.session.start()

        // Siri can still own the audio route for a moment after it has opened
        // Mini.  The normal Shortcuts path does not hit this case.  Retry only
        // the known transient audio-engine failure, and only while foreground.
        if !runtime.session.isConnected, isTransientAudioStartFailure {
            logger.notice("transient audio start failure; retrying once after foreground audio handoff")
            try? await Task.sleep(for: .milliseconds(350))
            guard UIApplication.shared.applicationState == .active, !Task.isCancelled else {
                isStarting = false
                return
            }
            runtime.session.dismissError()
            runtime.session.agent.dismissError()
            runtime.localMedia.dismissError()
            await runtime.session.start()
        }
        isStarting = false
        if runtime.session.isConnected {
            await liveActivity.begin(userName: runtime.authentication.displayName ?? "Orbit")
        } else {
            lastError = runtime.session.error?.localizedDescription ?? "Не вдалося підключити Orbit."
        }
    }

    func updateAgentState(_ description: String) async {
        guard isVoiceActive else { return }
        let normalized = description.lowercased()
        let state: OrbitMiniVoiceState
        if normalized.contains("speak") { state = .speaking }
        else if normalized.contains("think") { state = .thinking }
        else { state = .listening }
        await liveActivity.transition(to: state, userName: runtime.authentication.displayName ?? "Orbit")
    }

    func handleLatestUserMessage() async {
        guard isVoiceActive,
              let lastMessage = runtime.session.messages.last
        else { return }

        switch lastMessage.content {
        case let .userTranscript(text), let .userInput(text):
            guard OrbitMiniEndPhrases.matches(text) else { return }
            logger.notice("end phrase detected locally")
            await terminateSession(reason: "end-phrase")
        default:
            break
        }
    }

    func stop(reason: String = "user") async {
        await terminateSession(reason: reason)
    }

    /// One termination path for spoken end commands, UI controls, App Intents,
    /// transport disconnects, and fatal local failures.  Visible shutdown is
    /// deliberately independent from a potentially slow LiveKit handshake.
    func terminateSession(reason: String) async {
        guard !isTerminating else { return }
        isTerminating = true
        let started = ContinuousClock.now
        logger.notice("termination requested reason=\(reason, privacy: .public)")

        let session = runtime.session
        let disconnectTask = Task { @MainActor in
            logger.notice("LiveKit session.end started")
            await session.end()
            self.logger.notice("LiveKit session.end completed")
        }

        // Do not leave the user-facing state or Lock Screen implying that Orbit
        // is still available while the network transport winds down.
        runtime.session.restoreMessageHistory([])
        await liveActivity.end()
        logger.notice("Live Activity ended; visible session is idle")

        Task { @MainActor [weak self] in
            await disconnectTask.value
            guard let self else { return }
            self.isTerminating = false
            let elapsed = started.duration(to: .now)
            self.logger.notice("termination completed in \(String(describing: elapsed), privacy: .public)")
        }
    }

    func cleanOrphansAtLaunch() async {
        guard !runtime.session.isConnected else { return }
        await liveActivity.reconcileOrphans()
    }
}

private extension OrbitMiniVoiceCoordinator {
    var isTransientAudioStartFailure: Bool {
        let descriptions = [
            runtime.session.error?.localizedDescription,
            runtime.session.agent.error?.localizedDescription,
            runtime.localMedia.error?.localizedDescription,
        ].compactMap { $0?.lowercased() }
        return descriptions.contains { $0.contains("-3001") || $0.contains("audio engine") }
    }
}

extension OrbitMiniVoiceCoordinator: RoomDelegate {
    nonisolated func room(_ room: Room, didUpdateConnectionState connectionState: ConnectionState, from oldConnectionState: ConnectionState) {
        guard connectionState == .disconnected, oldConnectionState != .disconnected else { return }
        Task { @MainActor [weak self] in
            await self?.stop(reason: "transport-disconnected")
        }
    }
}
