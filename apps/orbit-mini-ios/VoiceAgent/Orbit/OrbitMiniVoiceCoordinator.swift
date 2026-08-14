@preconcurrency import Foundation
import LiveKit
import os
import UIKit
import AVFAudio

/// Bounded, local-only export of the existing Siri/audio diagnostics. The
/// lock keeps audio callbacks non-blocking; persistence is queued separately.
final class OrbitMiniDiagnosticLogger: @unchecked Sendable {
    nonisolated(unsafe) static let shared = OrbitMiniDiagnosticLogger()

    private nonisolated(unsafe) let osLogger: os.Logger
    private nonisolated(unsafe) let lock = NSLock()
    private nonisolated(unsafe) let persistenceQueue = DispatchQueue(label: "net.opik.orbit.mini.diagnostics", qos: .utility)
    private nonisolated(unsafe) var entries: [String] = []
    private nonisolated(unsafe) let maxEntries = 350
    private nonisolated(unsafe) let storageKey = "mini.siriAudioDiagnostics.v1"

    nonisolated init(category: String = "siri-audio") {
        osLogger = os.Logger(subsystem: "net.opik.orbit.mini", category: category)
        if let saved = UserDefaults(suiteName: "net.opik.orbit.mini")?.stringArray(forKey: storageKey) {
            entries = Array(saved.suffix(maxEntries))
        }
    }

    nonisolated var eventCount: Int { persistenceQueue.sync { lock.withLock { entries.count } } }

    nonisolated func notice(_ message: String) {
        osLogger.notice("\(message, privacy: .public)")
        append(message)
    }

    nonisolated func error(_ message: String) {
        osLogger.error("\(message, privacy: .public)")
        append(message)
    }

    nonisolated func exportText() -> String {
        persistenceQueue.sync { lock.withLock { entries.joined(separator: "\n") } }
    }

    nonisolated func clear() {
        lock.withLock { entries.removeAll() }
        persistenceQueue.async { [storageKey] in UserDefaults(suiteName: "net.opik.orbit.mini")?.removeObject(forKey: storageKey) }
    }

    private nonisolated func append(_ message: String) {
        persistenceQueue.async { [weak self] in
            guard let self else { return }
            let safeMessage = Self.redact(message)
            let timestamp = String(format: "%.3f", Date().timeIntervalSince1970)
            let line = "\(timestamp) → siri-audio → \(safeMessage)"
            let snapshot: [String] = self.lock.withLock {
                self.entries.append(line)
                if self.entries.count > self.maxEntries { self.entries.removeFirst(self.entries.count - self.maxEntries) }
                return self.entries
            }
            UserDefaults(suiteName: "net.opik.orbit.mini")?.set(snapshot, forKey: self.storageKey)
        }
    }

    private nonisolated static func redact(_ message: String) -> String {
        var value = message
        for pattern in ["https?://\\S+", "(?i)bearer\\s+\\S+", "(?i)(token|api[_-]?key|secret|password)=[^\\s]+"] {
            value = value.replacingOccurrences(of: pattern, with: "[redacted]", options: .regularExpression)
        }
        return value
    }
}

private extension NSLock {
    nonisolated func withLock<T>(_ body: () -> T) -> T {
        lock(); defer { unlock() }
        return body()
    }
}

/// A continuation may be completed by either a lifecycle/audio notification
/// or its bounded timeout. The lock makes that race one-shot.
private final class OrbitMiniAudioSignalWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?

    init(_ continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    func resume(signalled: Bool) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: signalled)
    }
}

/// Observes the first actual local PCM buffer after the LiveKit ADM reports a
/// successful start. This distinguishes an engine object that merely exists
/// from a microphone capture path that is delivering data.
private final class OrbitMiniAudioFrameProbe: AudioRenderer, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?
    private var receivedFrame = false

    func render(pcmBuffer _: AVAudioPCMBuffer) {
        resume(received: true)
    }

    func waitForFrame(timeout: Duration) async -> Bool {
        await withCheckedContinuation { continuation in
            let resumeImmediately = lock.withLock {
                if receivedFrame { return true }
                self.continuation = continuation
                return false
            }
            if resumeImmediately {
                continuation.resume(returning: true)
                return
            }
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                self?.resume(received: false)
            }
        }
    }

    private func resume(received: Bool) {
        lock.lock()
        if received { receivedFrame = true }
        let continuation = continuation
        self.continuation = nil
        let result = receivedFrame
        lock.unlock()
        continuation?.resume(returning: result)
    }
}

private struct OrbitMiniAudioProbeResult {
    let succeeded: Bool
    let transient: Bool
    let detail: String
}

/// Diagnostics-only observer prepended to LiveKit's unchanged default chain.
/// It neither configures nor retains the engine and always forwards its result.
final class OrbitMiniAudioEngineDiagnostics: AudioEngineObserver, @unchecked Sendable {
    private let lock = NSLock()
    private var storedNext: (any AudioEngineObserver)?
    private nonisolated(unsafe) let logger = OrbitMiniDiagnosticLogger.shared

    var next: (any AudioEngineObserver)? {
        get { lock.withLock { storedNext } }
        set { lock.withLock { storedNext = newValue } }
    }

    func engineDidCreate(_ engine: AVAudioEngine) -> Int {
        logger.notice("audio-engine didCreate running=\(engine.isRunning)")
        return next?.engineDidCreate(engine) ?? 0
    }

    func engineWillEnable(_ engine: AVAudioEngine, isPlayoutEnabled: Bool, isRecordingEnabled: Bool) -> Int {
        logger.notice("audio-engine willEnable playout=\(isPlayoutEnabled) recording=\(isRecordingEnabled) running=\(engine.isRunning)")
        let result = next?.engineWillEnable(engine, isPlayoutEnabled: isPlayoutEnabled, isRecordingEnabled: isRecordingEnabled) ?? 0
        logger.notice("audio-engine willEnable downstreamResult=\(result) category=\(AVAudioSession.sharedInstance().category.rawValue) mode=\(AVAudioSession.sharedInstance().mode.rawValue)")
        return result
    }

    func engineWillStart(_ engine: AVAudioEngine, isPlayoutEnabled: Bool, isRecordingEnabled: Bool) -> Int {
        let format = engine.inputNode.inputFormat(forBus: 0)
        logger.notice("audio-engine willStart playout=\(isPlayoutEnabled) recording=\(isRecordingEnabled) inputSampleRate=\(format.sampleRate) inputChannels=\(format.channelCount)")
        let result = next?.engineWillStart(engine, isPlayoutEnabled: isPlayoutEnabled, isRecordingEnabled: isRecordingEnabled) ?? 0
        logger.notice("audio-engine willStart downstreamResult=\(result)")
        return result
    }

    func engineDidStop(_ engine: AVAudioEngine, isPlayoutEnabled: Bool, isRecordingEnabled: Bool) -> Int {
        logger.notice("audio-engine didStop playout=\(isPlayoutEnabled) recording=\(isRecordingEnabled)")
        return next?.engineDidStop(engine, isPlayoutEnabled: isPlayoutEnabled, isRecordingEnabled: isRecordingEnabled) ?? 0
    }

    func engineDidDisable(_ engine: AVAudioEngine, isPlayoutEnabled: Bool, isRecordingEnabled: Bool) -> Int {
        logger.notice("audio-engine didDisable playout=\(isPlayoutEnabled) recording=\(isRecordingEnabled)")
        return next?.engineDidDisable(engine, isPlayoutEnabled: isPlayoutEnabled, isRecordingEnabled: isRecordingEnabled) ?? 0
    }

    func engineWillRelease(_ engine: AVAudioEngine) -> Int {
        logger.notice("audio-engine willRelease running=\(engine.isRunning)")
        return next?.engineWillRelease(engine) ?? 0
    }
}

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
    private let logger = OrbitMiniDiagnosticLogger.shared
    private var audioInterrupted = false
    private var intentStartTask: Task<Void, Never>?
    private var audioSignalWaiters: [UUID: OrbitMiniAudioSignalWaiter] = [:]
    private var audioHandoff: OrbitMiniAudioHandoffStateMachine?
    private var activeStartID: String?
    private var lastAudioProbeError: String?

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
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0
            Task { @MainActor [weak self] in
                self?.handleAudioRouteChange(reason)
            }
        }
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleMediaServicesReset()
            }
        }
        if #available(iOS 26.0, *) {
            NotificationCenter.default.addObserver(
                forName: AVAudioSession.availableInputsChangeNotification,
                object: AVAudioSession.sharedInstance(),
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleAvailableInputsChange()
                }
            }
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleApplicationDidBecomeActive()
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
            logger.notice("voice start ignored source=\(source) connected=\(self.runtime.session.isConnected) starting=\(self.isStarting) terminating=\(self.isTerminating)")
            return false
        }
        isStarting = true
        lastError = nil
        lastAudioProbeError = nil
        activeStartID = String(UUID().uuidString.prefix(8))
        logger.notice("coordinator start requested id=\(activeStartID ?? "none") source=\(source)")
        return true
    }

    private func beginPreparedStart(source: String) async {
        let startID = activeStartID ?? "none"
        await liveActivity.reconcileOrphans()
        await foregroundBootstrap()
        logAudioReadiness()

        // Button startup remains on the proven direct path. AppIntent startup
        // first proves that the shared LiveKit ADM can own the microphone and
        // deliver PCM. This covers manual Shortcut, Type-to-Siri and voice-Siri
        // without relying on an invocation-type API that iOS doesn't expose.
        if source == "app-intent" {
            guard await performAppIntentAudioHandoff(startID: startID) else {
                isStarting = false
                activeStartID = nil
                lastError = lastAudioProbeError ?? "Мікрофон ще зайнятий системою. Спробуйте ще раз."
                logger.error("audio handoff terminal failure id=\(startID) error=\(lastError ?? "unknown")")
                return
            }
        }
        guard !Task.isCancelled, !isTerminating else {
            if source == "app-intent" { await resetFailedAudioProbe(reason: "start-cancelled") }
            isStarting = false
            activeStartID = nil
            logger.notice("LiveKit start cancelled before audio activation")
            return
        }

        await attemptLiveKitStart(number: 1, source: source)
        let sessionReady = runtime.session.isConnected && AudioManager.shared.isEngineRunning
        if runtime.session.isConnected, !sessionReady {
            logger.error("LiveKit connected without running microphone engine id=\(startID); cleaning partial start")
            await runtime.session.end()
        }
        if !sessionReady, runtime.session.room.connectionState != .disconnected {
            logger.notice("cleaning partial LiveKit room id=\(startID) state=\(String(describing: runtime.session.room.connectionState))")
            await runtime.session.end()
        }
        if !sessionReady, source == "app-intent" {
            await resetFailedAudioProbe(reason: "session-start-failed")
        }
        isStarting = false
        activeStartID = nil
        audioHandoff = nil
        if sessionReady {
            await liveActivity.begin(userName: runtime.authentication.displayName ?? "Orbit")
        } else {
            lastError = runtime.session.error?.localizedDescription ?? "Не вдалося підключити Orbit."
            logger.error("voice startup final failure id=\(startID) error=\(lastError ?? "unknown")")
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
        audioHandoff?.handle(.cancel)
        audioHandoff = nil
        activeStartID = nil
        guard !isTerminating else { return }
        isTerminating = true
        let waiters = audioSignalWaiters
        audioSignalWaiters.removeAll()
        waiters.values.forEach { $0.resume(signalled: false) }
        let started = ContinuousClock.now
        logger.notice("termination requested reason=\(reason)")

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
            self.logger.notice("termination completed in \(String(describing: elapsed))")
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
        logger.notice("voice foreground bootstrap requested app=\(UIApplication.shared.applicationState.rawValue) scene=\(self.sceneStateDescription)")
        await Task.yield()
    }

    /// LiveKit owns the audio-session configuration. This independent check is
    /// intentionally observational; the actual readiness signal is whether its
    /// audio engine can start, not an App/UIScene lifecycle state.
    func logAudioReadiness() {
        let audioSession = AVAudioSession.sharedInstance()
        let inputs = audioSession.currentRoute.inputs.map(\.portType.rawValue).joined(separator: ",")
        let outputs = audioSession.currentRoute.outputs.map(\.portType.rawValue).joined(separator: ",")
        let availableInputs = audioSession.availableInputs?.map(\.portType.rawValue).joined(separator: ",") ?? "none"
        logger.notice("audio readiness app=\(UIApplication.shared.applicationState.rawValue) category=\(audioSession.category.rawValue) mode=\(audioSession.mode.rawValue) permission=\(String(describing: audioSession.recordPermission)) interrupted=\(self.audioInterrupted) inputAvailable=\(audioSession.isInputAvailable) otherAudio=\(audioSession.isOtherAudioPlaying) silencedHint=\(audioSession.secondaryAudioShouldBeSilencedHint) input=\(inputs) availableInputs=\(availableInputs) output=\(outputs) engineRunning=\(AudioManager.shared.isEngineRunning)")
    }

    func attemptLiveKitStart(number: Int, source: String) async {
        logger.notice("LiveKit session.start begin attempt=\(number) source=\(source) engineRunningBefore=\(AudioManager.shared.isEngineRunning)")
        await runtime.session.start()
        if runtime.session.isConnected {
            logger.notice("LiveKit session connected attempt=\(number) engineRunning=\(AudioManager.shared.isEngineRunning)")
        } else {
            logger.error("LiveKit session.start failed attempt=\(number) error=\(self.currentAudioErrorDescription) engineRunningAfter=\(AudioManager.shared.isEngineRunning) roomState=\(String(describing: self.runtime.session.room.connectionState))")
        }
    }

    /// Voice Siri can foreground Mini after the interruption-began event was
    /// already emitted. Therefore notifications guide this loop, but only a
    /// successful ADM start plus a real PCM buffer authorizes Session.start().
    func performAppIntentAudioHandoff(startID: String) async -> Bool {
        var machine = OrbitMiniAudioHandoffStateMachine(maximumProbeAttempts: 4)
        machine.handle(.requested(
            appIsActive: UIApplication.shared.applicationState == .active,
            interruptionActive: audioInterrupted
        ))
        audioHandoff = machine
        logger.notice("audio handoff begin id=\(startID) phase=\(String(describing: machine.phase))")

        while !Task.isCancelled, !isTerminating {
            guard var current = audioHandoff else { return false }
            logger.notice("audio handoff state id=\(startID) phase=\(String(describing: current.phase)) attempts=\(current.probeAttempts)")

            switch current.phase {
            case .waitingForForeground:
                let signalled = await waitForAudioSignalOrTimeout(reason: "foreground", timeout: .milliseconds(700))
                if !signalled { mutateAudioHandoff(.boundedWaitExpired) }

            case .waitingForAudioRelease:
                let signalled = await waitForAudioSignalOrTimeout(reason: "interruption-release", timeout: .milliseconds(900))
                if !signalled { mutateAudioHandoff(.boundedWaitExpired) }

            case let .waitingForRetry(attempt):
                let timeouts: [Duration] = [.milliseconds(120), .milliseconds(280), .milliseconds(600), .milliseconds(900)]
                let timeout = timeouts[min(max(attempt - 1, 0), timeouts.count - 1)]
                let signalled = await waitForAudioSignalOrTimeout(reason: "transient-adm-retry-\(attempt)", timeout: timeout)
                if !signalled { mutateAudioHandoff(.boundedWaitExpired) }

            case .readyToProbe:
                guard let attempt = current.beginProbe() else {
                    logger.error("audio handoff invariant failure id=\(startID): probe claim rejected")
                    return false
                }
                audioHandoff = current
                let result = await probeMicrophoneCapture(attempt: attempt, startID: startID)
                lastAudioProbeError = result.detail
                if result.succeeded {
                    mutateAudioHandoff(.probeSucceeded)
                } else {
                    await resetFailedAudioProbe(reason: "probe-\(attempt)-failed")
                    mutateAudioHandoff(.probeFailed(transient: result.transient))
                }

            case .readyForSession:
                logger.notice("audio handoff ready id=\(startID) attempts=\(current.probeAttempts) engineRunning=\(AudioManager.shared.isEngineRunning)")
                return true

            case .failed:
                logger.error("audio handoff exhausted id=\(startID) attempts=\(current.probeAttempts) error=\(lastAudioProbeError ?? "unknown")")
                return false

            case .cancelled, .idle:
                return false

            case .probing:
                // The coordinator itself owns the only probe and never waits
                // concurrently while this phase is active.
                logger.error("audio handoff invariant failure id=\(startID): orphan probing phase")
                return false
            }
        }

        mutateAudioHandoff(.cancel)
        return false
    }

    func mutateAudioHandoff(_ event: OrbitMiniAudioHandoffStateMachine.Event) {
        guard var machine = audioHandoff else { return }
        machine.handle(event)
        audioHandoff = machine
    }

    func probeMicrophoneCapture(attempt: Int, startID: String) async -> OrbitMiniAudioProbeResult {
        let manager = AudioManager.shared
        let frameProbe = OrbitMiniAudioFrameProbe()
        manager.add(localAudioRenderer: frameProbe)
        defer { manager.remove(localAudioRenderer: frameProbe) }

        logger.notice("audio probe begin id=\(startID) attempt=\(attempt) interrupted=\(audioInterrupted) inputAvailable=\(AVAudioSession.sharedInstance().isInputAvailable) engineRunning=\(manager.isEngineRunning)")
        do {
            try manager.setEngineAvailability(.default)
            try manager.startLocalRecording()
            logger.notice("audio probe ADM start result id=\(startID) attempt=\(attempt) success=true engineRunning=\(manager.isEngineRunning)")
        } catch {
            let detail = error.localizedDescription
            let transient = isTransientAudioFailure(detail)
            logger.error("audio probe ADM start result id=\(startID) attempt=\(attempt) success=false transient=\(transient) error=\(detail)")
            return OrbitMiniAudioProbeResult(succeeded: false, transient: transient, detail: detail)
        }

        let receivedFrame = await frameProbe.waitForFrame(timeout: .milliseconds(650))
        let running = manager.isEngineRunning
        logger.notice("audio probe capture result id=\(startID) attempt=\(attempt) engineRunning=\(running) pcmFrame=\(receivedFrame)")
        if running, receivedFrame, !audioInterrupted {
            return OrbitMiniAudioProbeResult(succeeded: true, transient: false, detail: "ready")
        }

        let detail = audioInterrupted
            ? "AVAudioSession interruption became active during microphone probe"
            : "LiveKit audio engine started without a local PCM frame"
        return OrbitMiniAudioProbeResult(succeeded: false, transient: true, detail: detail)
    }

    /// Clears only the local ADM attempt. No Room exists yet on the normal
    /// handoff path, so a retry cannot stack over a partial LiveKit session.
    func resetFailedAudioProbe(reason: String) async {
        let manager = AudioManager.shared
        do {
            try manager.stopLocalRecording()
            logger.notice("audio probe cleanup stopRecording success reason=\(reason)")
        } catch {
            logger.notice("audio probe cleanup stopRecording result reason=\(reason) error=\(error.localizedDescription)")
        }
        do {
            try manager.setEngineAvailability(.none)
            logger.notice("audio probe cleanup engine disabled reason=\(reason)")
        } catch {
            logger.error("audio probe cleanup engine disable failed reason=\(reason) error=\(error.localizedDescription)")
        }
        await Task.yield()
        do {
            try manager.setEngineAvailability(.default)
            logger.notice("audio probe cleanup engine reset reason=\(reason)")
        } catch {
            logger.error("audio probe cleanup engine reset failed reason=\(reason) error=\(error.localizedDescription)")
        }
        runtime.session.dismissError()
        runtime.localMedia.dismissError()
    }

    /// Registered before its timeout task, so notification and timeout races
    /// are one-shot and can never launch competing probes.
    func waitForAudioSignalOrTimeout(reason: String, timeout: Duration) async -> Bool {
        let token = UUID()
        logger.notice("audio handoff wait reason=\(reason) interrupted=\(audioInterrupted)")
        let signalled = await withCheckedContinuation { continuation in
            let waiter = OrbitMiniAudioSignalWaiter(continuation)
            audioSignalWaiters[token] = waiter
            Task {
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                waiter.resume(signalled: false)
            }
        }
        audioSignalWaiters.removeValue(forKey: token)
        logger.notice("audio handoff wait completed reason=\(reason) signal=\(signalled)")
        return signalled
    }

    func signalAudioHandoff(_ event: OrbitMiniAudioHandoffStateMachine.Event, reason: String) {
        mutateAudioHandoff(event)
        guard !audioSignalWaiters.isEmpty else { return }
        logger.notice("audio handoff notification reason=\(reason)")
        let waiters = audioSignalWaiters
        audioSignalWaiters.removeAll()
        waiters.values.forEach { $0.resume(signalled: true) }
    }

    func handleAudioInterruption(_ raw: UInt, options rawOptions: UInt) {
        guard let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            audioInterrupted = true
            logger.notice("AVAudioSession interruption began")
            mutateAudioHandoff(.interruptionBegan)
        case .ended:
            audioInterrupted = false
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
            logger.notice("AVAudioSession interruption ended shouldResume=\(options.contains(.shouldResume))")
            signalAudioHandoff(.interruptionEnded, reason: "interruption-ended")
        @unknown default:
            break
        }
    }

    func handleAudioRouteChange(_ raw: UInt) {
        let reason = AVAudioSession.RouteChangeReason(rawValue: raw)
        logger.notice("AVAudioSession route changed reason=\(String(describing: reason))")
        logAudioReadiness()
        signalAudioHandoff(.audioReadinessChanged, reason: "route-changed")
    }

    func handleAvailableInputsChange() {
        logger.notice("AVAudioSession available inputs changed")
        logAudioReadiness()
        signalAudioHandoff(.audioReadinessChanged, reason: "available-inputs-changed")
    }

    func handleApplicationDidBecomeActive() {
        logger.notice("UIApplication didBecomeActive scene=\(self.sceneStateDescription)")
        signalAudioHandoff(.appBecameActive, reason: "application-active")
    }

    func handleMediaServicesReset() {
        logger.error("AVAudioSession media services were reset")
        signalAudioHandoff(.audioReadinessChanged, reason: "media-services-reset")
    }

    var currentAudioErrorDescription: String {
        [
            runtime.session.error?.localizedDescription,
            runtime.session.agent.error?.localizedDescription,
            runtime.localMedia.error?.localizedDescription,
        ].compactMap { $0 }.joined(separator: " | ")
    }

    func isTransientAudioFailure(_ description: String) -> Bool {
        let value = description.lowercased()
        return value.contains("-3001")
            || value.contains("-4010")
            || value.contains("audio engine")
            || value.contains("cannot start recording")
            || value.contains("resource") && value.contains("unavailable")
    }
}

extension OrbitMiniVoiceCoordinator: RoomDelegate {
    nonisolated func room(_ room: Room, didUpdateConnectionState connectionState: ConnectionState, from oldConnectionState: ConnectionState) {
        guard connectionState == .disconnected, oldConnectionState != .disconnected else { return }
        Task { @MainActor [weak self] in
            guard let self, !self.isStarting else {
                self?.logger.notice("transport disconnect handled by startup cleanup")
                return
            }
            await self.stop(reason: "transport-disconnected")
        }
    }
}
