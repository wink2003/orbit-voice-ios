import Foundation
import LiveKit
import OSLog
import UIKit
import AVFAudio

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
    private var audioInterrupted = false

    private override init() {
        super.init()
        runtime.session.room.add(delegate: self)
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleAudioInterruption(notification)
            }
        }
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
        logger.notice("voice start requested app=\(UIApplication.shared.applicationState.rawValue, privacy: .public) scene=\(self.sceneStateDescription, privacy: .public)")
        guard await waitForForegroundReadiness() else {
            isStarting = false
            lastError = "Orbit Mini не став активною програмою для мікрофона."
            return
        }
        logger.notice("voice start foreground/audio gate passed category=\(AVAudioSession.sharedInstance().category.rawValue, privacy: .public) mode=\(AVAudioSession.sharedInstance().mode.rawValue, privacy: .public)")
        await runtime.session.start()

        // Siri can retain the audio route briefly after it has foregrounded
        // Mini. Retry only the known transient engine failure, using actual
        // foreground/interruption state plus a small bounded window. Manual
        // Shortcuts never enter this loop when their first start succeeds.
        if !runtime.session.isConnected, isTransientAudioStartFailure {
            await retryTransientAudioStart()
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
    var sceneStateDescription: String {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .map { "\($0.session.persistentIdentifier):\($0.activationState.rawValue)" }
            .joined(separator: ",")
    }

    var isForegroundActive: Bool {
        UIApplication.shared.applicationState == .active
            && UIApplication.shared.connectedScenes.contains {
                ($0 as? UIWindowScene)?.activationState == .foregroundActive
            }
    }

    func waitForForegroundReadiness() async -> Bool {
        let deadline = Date().addingTimeInterval(1.2)
        while !Task.isCancelled {
            if isForegroundActive, !audioInterrupted { return true }
            guard Date() < deadline else { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        logger.error("foreground/audio gate timed out app=\(UIApplication.shared.applicationState.rawValue, privacy: .public) scene=\(self.sceneStateDescription, privacy: .public) interrupted=\(self.audioInterrupted, privacy: .public)")
        return false
    }

    func retryTransientAudioStart() async {
        let deadline = Date().addingTimeInterval(2.0)
        let delays: [Duration] = [.milliseconds(100), .milliseconds(180), .milliseconds(300), .milliseconds(450), .milliseconds(600)]
        for (index, delay) in delays.enumerated() {
            guard Date() < deadline, await waitForForegroundReadiness(), !Task.isCancelled else { break }
            try? await Task.sleep(for: delay)
            guard isForegroundActive, !audioInterrupted else { continue }
            logger.notice("transient audio retry \(index + 1, privacy: .public) elapsed=\(2.0 - max(0, deadline.timeIntervalSinceNow), privacy: .public)s")
            runtime.session.dismissError()
            runtime.localMedia.dismissError()
            await runtime.session.start()
            if runtime.session.isConnected {
                logger.notice("transient audio retry succeeded")
                return
            }
            guard isTransientAudioStartFailure else { return }
        }
        logger.error("transient audio startup retries exhausted")
    }

    func handleAudioInterruption(_ notification: Notification) {
        let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt ?? 0
        guard let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            audioInterrupted = true
            logger.notice("AVAudioSession interruption began")
        case .ended:
            audioInterrupted = false
            logger.notice("AVAudioSession interruption ended")
        @unknown default:
            break
        }
    }

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
