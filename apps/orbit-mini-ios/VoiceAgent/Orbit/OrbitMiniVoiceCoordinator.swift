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
    private var intentStartTask: Task<Void, Never>?
    private var audioReleaseWaiters: [UUID: CheckedContinuation<Bool, Never>] = [:]

    private override init() {
        super.init()
        runtime.session.room.add(delegate: self)
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            let interruptionType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt ?? 0
            let interruptionOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor [weak self] in
                self?.handleAudioInterruption(interruptionType, options: interruptionOptions)
            }
        }
    }

    var session: Session { runtime.session }
    var isVoiceActive: Bool { runtime.session.isConnected && !isTerminating }

    func start() async {
        guard prepareStart(source: "button") else { return }
        await beginPreparedStart(source: "button")
    }

    /// An App Intent must return before it competes with Siri for microphone
    /// ownership. `Task.yield()` schedules the attempt after `perform()` has
    /// completed; it is not a timed delay and does not inspect scene state.
    func requestStartFromAppIntent() {
        guard prepareStart(source: "app-intent") else { return }
        logger.notice("app-intent start queued; perform may now complete")
        intentStartTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self else { return }
            self.intentStartTask = nil
            guard !self.isTerminating else {
                self.isStarting = false
                self.logger.notice("app-intent start cancelled during termination")
                return
            }
            await self.beginPreparedStart(source: "app-intent")
        }
    }

    private func prepareStart(source: String) -> Bool {
        guard runtime.authentication.isPaired else {
            lastError = "Спершу активуйте цей iPhone."
            return false
        }
        guard !runtime.session.isConnected, !isStarting, !isTerminating else {
            logger.notice("voice start ignored source=\(source, privacy: .public) connected=\(self.runtime.session.isConnected, privacy: .public) starting=\(self.isStarting, privacy: .public) terminating=\(self.isTerminating, privacy: .public)")
            return false
        }
        isStarting = true
        lastError = nil
        logger.notice("coordinator start requested source=\(source, privacy: .public)")
        return true
    }

    private func beginPreparedStart(source: String) async {
        await liveActivity.reconcileOrphans()
        await foregroundBootstrap()
        logAudioReadiness()

        // If Mini has observed Siri's interruption, do not ask LiveKit to
        // activate the microphone until the corresponding public end event.
        if audioInterrupted {
            logger.notice("LiveKit start deferred: AVAudioSession interruption is active")
            let released = await waitForAudioReleaseOrTimeout(reason: "pre-start interruption")
            logger.notice("audio release wait completed released=\(released, privacy: .public)")
            if released { await Task.yield() }
        }
        guard !Task.isCancelled, !isTerminating else {
            isStarting = false
            logger.notice("LiveKit start cancelled before audio activation")
            return
        }

        await attemptLiveKitStart(number: 1, source: source)

        // A -3001 after `perform()` has returned is the only fallback case.
        // Wait for an observed interruption end, or one bounded timeout if
        // that notification raced before registration; never spin retries.
        if !runtime.session.isConnected, isTransientAudioStartFailure {
            await retryTransientAudioStart(source: source)
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
        intentStartTask?.cancel()
        intentStartTask = nil
        guard !isTerminating else { return }
        isTerminating = true
        let waiters = audioReleaseWaiters
        audioReleaseWaiters.removeAll()
        waiters.values.forEach { $0.resume(returning: false) }
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

    /// `openAppWhenRun` / supportedModes have already asked the system to
    /// foreground Mini. Yield once so that transition work can progress, but
    /// never infer the result from a transient connected-scene snapshot.
    func foregroundBootstrap() async {
        logger.notice("voice foreground bootstrap requested app=\(UIApplication.shared.applicationState.rawValue, privacy: .public) scene=\(self.sceneStateDescription, privacy: .public)")
        await Task.yield()
    }

    /// LiveKit owns the audio-session configuration. This independent check is
    /// intentionally observational; the actual readiness signal is whether its
    /// audio engine can start, not an App/UIScene lifecycle state.
    func logAudioReadiness() {
        let audioSession = AVAudioSession.sharedInstance()
        let inputs = audioSession.currentRoute.inputs.map(\.portType.rawValue).joined(separator: ",")
        let outputs = audioSession.currentRoute.outputs.map(\.portType.rawValue).joined(separator: ",")
        logger.notice("AVAudioSession before LiveKit activation category=\(audioSession.category.rawValue, privacy: .public) mode=\(audioSession.mode.rawValue, privacy: .public) permission=\(String(describing: audioSession.recordPermission), privacy: .public) interrupted=\(self.audioInterrupted, privacy: .public) otherAudio=\(audioSession.isOtherAudioPlaying, privacy: .public) silencedHint=\(audioSession.secondaryAudioShouldBeSilencedHint, privacy: .public) input=\(inputs, privacy: .public) output=\(outputs, privacy: .public)")
    }

    func attemptLiveKitStart(number: Int, source: String) async {
        logger.notice("LiveKit start attempt=\(number, privacy: .public) source=\(source, privacy: .public); automatic AVAudioSession activation is owned by LiveKit")
        await runtime.session.start()
        if runtime.session.isConnected {
            logger.notice("LiveKit start attempt=\(number, privacy: .public) succeeded")
        } else {
            logger.error("LiveKit start attempt=\(number, privacy: .public) failed error=\(self.currentAudioErrorDescription, privacy: .public)")
        }
    }

    func retryTransientAudioStart(source: String) async {
        guard !Task.isCancelled, !isTerminating else { return }
        logger.notice("-3001/audio-engine failure: waiting for AVAudioSession release before one bounded retry")
        let released = await waitForAudioReleaseOrTimeout(reason: "-3001 fallback")
        guard !Task.isCancelled, !isTerminating else { return }
        logger.notice("-3001 retry reason=\(released ? "interruption-ended" : "bounded-timeout", privacy: .public)")
        if released { await Task.yield() }
        runtime.session.dismissError()
        runtime.localMedia.dismissError()
        await attemptLiveKitStart(number: 2, source: source)
        if !runtime.session.isConnected {
            logger.error("bounded audio startup fallback failed error=\(self.currentAudioErrorDescription, privacy: .public)")
        }
    }

    /// A waiter is registered on the MainActor before the timeout is started,
    /// so an interruption-end notification cannot race into a duplicate start.
    /// The timeout is a single recovery fallback for a notification that was
    /// already in flight before app launch; it is not a polling loop.
    func waitForAudioReleaseOrTimeout(reason: String) async -> Bool {
        let token = UUID()
        logger.notice("waiting for AVAudioSession interruption release reason=\(reason, privacy: .public) active=\(self.audioInterrupted, privacy: .public)")
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                audioReleaseWaiters[token] = continuation
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(1.5))
                    guard !Task.isCancelled else { return }
                    self?.resumeAudioReleaseWaiter(token, released: false)
                }
            }
        } onCancel: { [weak self] in
            Task { @MainActor in
                self?.resumeAudioReleaseWaiter(token, released: false)
            }
        }
    }

    func resumeAudioReleaseWaiter(_ token: UUID, released: Bool) {
        audioReleaseWaiters.removeValue(forKey: token)?.resume(returning: released)
    }

    func handleAudioInterruption(_ raw: UInt, options rawOptions: UInt) {
        guard let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            audioInterrupted = true
            logger.notice("AVAudioSession interruption began")
        case .ended:
            audioInterrupted = false
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
            logger.notice("AVAudioSession interruption ended shouldResume=\(options.contains(.shouldResume), privacy: .public)")
            let waiters = audioReleaseWaiters
            audioReleaseWaiters.removeAll()
            waiters.values.forEach { $0.resume(returning: true) }
        @unknown default:
            break
        }
    }

    var currentAudioErrorDescription: String {
        [
            runtime.session.error?.localizedDescription,
            runtime.session.agent.error?.localizedDescription,
            runtime.localMedia.error?.localizedDescription,
        ].compactMap { $0 }.joined(separator: " | ")
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
