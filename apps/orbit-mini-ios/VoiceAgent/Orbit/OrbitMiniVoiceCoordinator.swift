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

private enum OrbitMiniLifecycleWaitResult: Sendable, Equatable {
    case active(trigger: String)
    case timedOut
    case cancelled
}

/// UIApplication/UIScene activation and the lifecycle deadline race to
/// complete this continuation. Exactly one result wins.
private final class OrbitMiniLifecycleSignalWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<OrbitMiniLifecycleWaitResult, Never>?

    init(_ continuation: CheckedContinuation<OrbitMiniLifecycleWaitResult, Never>) {
        self.continuation = continuation
    }

    func resume(_ result: OrbitMiniLifecycleWaitResult) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: result)
    }
}

private enum OrbitMiniShortcutReadinessWaitResult: Sendable, Equatable {
    case ready
    case failed
    case cancelled
    case timedOut
}

/// A Wait AppIntent is resumed only by one terminal readiness state or its
/// bounded deadline. It never starts audio and cannot release Open App early.
private final class OrbitMiniShortcutReadinessWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<OrbitMiniShortcutReadinessWaitResult, Never>?

    init(_ continuation: CheckedContinuation<OrbitMiniShortcutReadinessWaitResult, Never>) {
        self.continuation = continuation
    }

    func resume(_ result: OrbitMiniShortcutReadinessWaitResult) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: result)
    }
}

/// Passive capture diagnostics. It deliberately never starts, stops, resets,
/// or otherwise owns the ADM; LiveKit Session owns that lifecycle.
private final class OrbitMiniSessionPCMObserver: AudioRenderer, @unchecked Sendable {
    private let lock = NSLock()
    private let source: String
    private let startID: String
    private let onFirstFrame: @Sendable () -> Void
    private let logger = OrbitMiniDiagnosticLogger.shared
    private var hasLoggedFirstFrame = false

    init(source: String, startID: String, onFirstFrame: @escaping @Sendable () -> Void) {
        self.source = source
        self.startID = startID
        self.onFirstFrame = onFirstFrame
    }

    func render(pcmBuffer _: AVAudioPCMBuffer) {
        let shouldLog = lock.withLock {
            guard !hasLoggedFirstFrame else { return false }
            hasLoggedFirstFrame = true
            return true
        }
        if shouldLog {
            logger.notice("audio capture first PCM source=\(source) id=\(startID) engineRunning=\(AudioManager.shared.isEngineRunning)")
            onFirstFrame()
        }
    }
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
    private var lifecycleSignalWaiters: [UUID: OrbitMiniLifecycleSignalWaiter] = [:]
    private var audioHandoff: OrbitMiniAudioHandoffStateMachine?
    private var shortcutReturnReadiness = OrbitMiniShortcutReturnReadinessStateMachine()
    private var shortcutReadinessWaiters: [UUID: OrbitMiniShortcutReadinessWaiter] = [:]
    private var activeStartID: String?
    private var lastStartupError: String?
    private var didLifecycleTimeout = false
    private var sessionPCMObserver: OrbitMiniSessionPCMObserver?

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
        NotificationCenter.default.addObserver(
            forName: UIScene.didActivateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleSceneDidActivate()
            }
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleLifecycleBecameInactive(trigger: "UIApplication.willResignActive")
            }
        }
        NotificationCenter.default.addObserver(
            forName: UIScene.willDeactivateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleLifecycleBecameInactive(trigger: "UIScene.willDeactivate")
            }
        }
    }

    var session: Session { runtime.session }
    var isVoiceActive: Bool { runtime.session.isConnected && !isTerminating }

    /// Used only by an explicit, subsequent Shortcut action. Returning false
    /// makes that action fail and therefore prevents Open App [PreviousApp]
    /// from racing a still-starting Mini session.
    func waitForShortcutReturnReadiness() async -> Bool {
        switch shortcutReturnReadiness.phase {
        case .ready:
            logger.notice("shortcut return readiness immediate result=ready")
            return true
        case .failed, .cancelled, .idle:
            logger.notice("shortcut return readiness immediate result=not-ready phase=\(String(describing: shortcutReturnReadiness.phase))")
            return false
        case .starting:
            break
        }

        let token = UUID()
        logger.notice("shortcut return readiness wait begin id=\(shortcutReturnReadiness.activeStartID ?? "none") timeoutSeconds=35")
        let result = await withCheckedContinuation { continuation in
            let waiter = OrbitMiniShortcutReadinessWaiter(continuation)
            shortcutReadinessWaiters[token] = waiter
            Task {
                try? await Task.sleep(for: .seconds(35))
                guard !Task.isCancelled else { return }
                waiter.resume(.timedOut)
            }
        }
        shortcutReadinessWaiters.removeValue(forKey: token)
        logger.notice("shortcut return readiness wait end result=\(String(describing: result)) id=\(shortcutReturnReadiness.activeStartID ?? "none")")
        return result == .ready
    }

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
        lastStartupError = nil
        didLifecycleTimeout = false
        activeStartID = String(UUID().uuidString.prefix(8))
        if source == "app-intent", let startID = activeStartID {
            _ = shortcutReturnReadiness.begin(id: startID)
            logger.notice("shortcut return readiness begin id=\(startID)")
        }
        logger.notice("coordinator start requested id=\(activeStartID ?? "none") source=\(source)")
        return true
    }

    private func beginPreparedStart(source: String) async {
        let startID = activeStartID ?? "none"
        await liveActivity.reconcileOrphans()
        await foregroundBootstrap()
        logAudioReadiness()

        // The button and AppIntent both start the same LiveKit Session. The
        // AppIntent adds only the lifecycle gate above; Session's own
        // PreConnectAudioBuffer is the sole microphone/ADM owner.
        if source == "app-intent" {
            guard await performAppIntentAudioHandoff(startID: startID) else {
                finishShortcutReturnReadiness(id: startID, result: .failed)
                isStarting = false
                activeStartID = nil
                audioHandoff = nil
                lastError = didLifecycleTimeout
                    ? "Orbit Mini не отримав активний стан після Siri. Закрийте Siri та спробуйте ще раз."
                    : lastStartupError ?? "Мікрофон ще зайнятий системою. Спробуйте ще раз."
                logger.error("audio handoff terminal failure id=\(startID) error=\(lastError ?? "unknown")")
                return
            }
        }
        guard !Task.isCancelled, !isTerminating else {
            finishShortcutReturnReadiness(id: startID, result: .cancelled)
            isStarting = false
            activeStartID = nil
            logger.notice("LiveKit start cancelled before audio activation")
            return
        }

        installSessionPCMDiagnostics(source: source, startID: startID)
        let sessionReady = source == "app-intent"
            ? await startAppIntentSessionWithRetry(startID: startID)
            : await startDirectSession(startID: startID, source: source)
        isStarting = false
        activeStartID = nil
        audioHandoff = nil
        if sessionReady {
            await liveActivity.begin(userName: runtime.authentication.displayName ?? "Orbit")
            markShortcutReturnPresentationEstablished(id: startID, source: source)
            if runtime.session.room.connectionState == .connected {
                markShortcutReturnRoomConnected(id: startID, source: source)
            }
        } else {
            clearSessionPCMDiagnostics()
            finishShortcutReturnReadiness(id: startID, result: .failed)
            lastError = lastStartupError ?? runtime.session.error?.localizedDescription ?? "Не вдалося підключити Orbit."
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
        let startID = activeStartID
        activeStartID = nil
        guard !isTerminating else { return }
        isTerminating = true
        let waiters = audioSignalWaiters
        audioSignalWaiters.removeAll()
        waiters.values.forEach { $0.resume(signalled: false) }
        let lifecycleWaiters = lifecycleSignalWaiters
        lifecycleSignalWaiters.removeAll()
        lifecycleWaiters.values.forEach { $0.resume(.cancelled) }
        if let startID {
            finishShortcutReturnReadiness(id: startID, result: .cancelled)
        }
        clearSessionPCMDiagnostics()
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
    var applicationStateDescription: String {
        switch UIApplication.shared.applicationState {
        case .active: "active"
        case .inactive: "inactive"
        case .background: "background"
        @unknown default: "unknown"
        }
    }

    var sceneStateDescription: String {
        let states = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .map { scene in
                switch scene.activationState {
                case .foregroundActive: "foregroundActive"
                case .foregroundInactive: "foregroundInactive"
                case .background: "background"
                case .unattached: "unattached"
                @unknown default: "unknown"
                }
            }
        return states.isEmpty ? "none" : states.joined(separator: ",")
    }

    var isUsableForegroundActive: Bool {
        UIApplication.shared.applicationState == .active
            && UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .contains { $0.activationState == .foregroundActive }
    }

    /// `openAppWhenRun` / supportedModes have already asked the system to
    /// foreground Mini. Yield once so that transition work can progress, but
    /// never infer the result from a transient connected-scene snapshot.
    func foregroundBootstrap() async {
        logger.notice("voice foreground bootstrap requested app=\(self.applicationStateDescription) scene=\(self.sceneStateDescription) usableActive=\(self.isUsableForegroundActive)")
        await Task.yield()
    }

    /// LiveKit owns the audio-session configuration. This check is
    /// observational. UIKit lifecycle-active is the prerequisite; after that,
    /// ADM running plus a real PCM buffer is the audio-readiness proof.
    func logAudioReadiness() {
        let audioSession = AVAudioSession.sharedInstance()
        let inputs = audioSession.currentRoute.inputs.map(\.portType.rawValue).joined(separator: ",")
        let outputs = audioSession.currentRoute.outputs.map(\.portType.rawValue).joined(separator: ",")
        let availableInputs = audioSession.availableInputs?.map(\.portType.rawValue).joined(separator: ",") ?? "none"
        logger.notice("audio readiness app=\(self.applicationStateDescription) scene=\(self.sceneStateDescription) usableActive=\(self.isUsableForegroundActive) category=\(audioSession.category.rawValue) mode=\(audioSession.mode.rawValue) permission=\(String(describing: audioSession.recordPermission)) interrupted=\(self.audioInterrupted) inputAvailable=\(audioSession.isInputAvailable) otherAudio=\(audioSession.isOtherAudioPlaying) silencedHint=\(audioSession.secondaryAudioShouldBeSilencedHint) input=\(inputs) availableInputs=\(availableInputs) output=\(outputs) engineRunning=\(AudioManager.shared.isEngineRunning)")
    }

    func attemptLiveKitStart(number: Int, source: String) async {
        logger.notice("LiveKit session.start begin attempt=\(number) source=\(source) app=\(self.applicationStateDescription) scene=\(self.sceneStateDescription) category=\(AVAudioSession.sharedInstance().category.rawValue) mode=\(AVAudioSession.sharedInstance().mode.rawValue) engineAvailability=\(String(describing: AudioManager.shared.engineAvailability)) engineRunningBefore=\(AudioManager.shared.isEngineRunning)")
        await runtime.session.start()
        if runtime.session.isConnected {
            logger.notice("LiveKit session connected attempt=\(number) engineRunning=\(AudioManager.shared.isEngineRunning)")
        } else {
            logger.error("LiveKit session.start failed attempt=\(number) error=\(self.currentAudioErrorDescription) engineRunningAfter=\(AudioManager.shared.isEngineRunning) roomState=\(String(describing: self.runtime.session.room.connectionState))")
        }
    }

    /// Voice Siri and manually run Shortcuts can invoke an AppIntent while Mini
    /// is visible but inactive. This waits for lifecycle and any observed
    /// interruption, then hands directly to the normal Session.start path.
    func performAppIntentAudioHandoff(startID: String) async -> Bool {
        var machine = OrbitMiniAudioHandoffStateMachine()
        machine.handle(.requested(
            appIsActive: isUsableForegroundActive,
            interruptionActive: audioInterrupted
        ))
        audioHandoff = machine
        logger.notice("audio handoff begin id=\(startID) phase=\(String(describing: machine.phase))")

        while !Task.isCancelled, !isTerminating {
            guard let current = audioHandoff else { return false }
            logger.notice("audio handoff state id=\(startID) phase=\(String(describing: current.phase))")

            switch current.phase {
            case .waitingForForeground:
                let result = await waitForUsableForegroundActive(timeout: .seconds(20))
                switch result {
                case let .active(trigger):
                    logger.notice("lifecycle wait accepted trigger=\(trigger) app=\(self.applicationStateDescription) scene=\(self.sceneStateDescription)")
                    mutateAudioHandoff(.appBecameActive)
                case .timedOut:
                    didLifecycleTimeout = true
                    lastStartupError = "Lifecycle timeout: application/scene did not become foreground-active"
                    logger.error("lifecycle wait timeout id=\(startID) app=\(self.applicationStateDescription) scene=\(self.sceneStateDescription) sessionStarts=0")
                    mutateAudioHandoff(.lifecycleWaitExpired)
                case .cancelled:
                    mutateAudioHandoff(.cancel)
                }

            case .waitingForAudioRelease:
                let signalled = await waitForAudioSignalOrTimeout(reason: "interruption-release", timeout: .milliseconds(900))
                if !signalled { mutateAudioHandoff(.audioReleaseWaitExpired) }

            case .readyForSession:
                guard isUsableForegroundActive else {
                    logger.notice("Session.start prevented before active id=\(startID) app=\(self.applicationStateDescription) scene=\(self.sceneStateDescription)")
                    mutateAudioHandoff(.appBecameInactive)
                    continue
                }
                logger.notice("audio handoff ready for Session.start id=\(startID) engineRunning=\(AudioManager.shared.isEngineRunning)")
                return true

            case .lifecycleTimedOut:
                logger.error("audio handoff lifecycle timeout id=\(startID) sessionStarts=0")
                return false

            case .cancelled, .idle:
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

    func installSessionPCMDiagnostics(source: String, startID: String) {
        clearSessionPCMDiagnostics()
        let observer = OrbitMiniSessionPCMObserver(source: source, startID: startID) { [weak self] in
            Task { @MainActor [weak self] in
                self?.markShortcutReturnFirstPCM(id: startID)
            }
        }
        sessionPCMObserver = observer
        AudioManager.shared.add(localAudioRenderer: observer)
        logger.notice("audio capture diagnostics attached source=\(source) id=\(startID)")
    }

    func clearSessionPCMDiagnostics() {
        guard let observer = sessionPCMObserver else { return }
        AudioManager.shared.remove(localAudioRenderer: observer)
        sessionPCMObserver = nil
        logger.notice("audio capture diagnostics detached")
    }

    func markShortcutReturnRoomConnected(id: String, source: String) {
        guard source == "app-intent" else { return }
        shortcutReturnReadiness.roomConnected(id: id)
        logger.notice("shortcut return readiness room-connected id=\(id) phase=\(String(describing: shortcutReturnReadiness.phase))")
        releaseShortcutReadinessWaitersIfTerminal()
    }

    func markShortcutReturnFirstPCM(id: String) {
        shortcutReturnReadiness.receivedFirstPCM(id: id)
        logger.notice("shortcut return readiness first-pcm id=\(id) phase=\(String(describing: shortcutReturnReadiness.phase))")
        releaseShortcutReadinessWaitersIfTerminal()
    }

    func markShortcutReturnPresentationEstablished(id: String, source: String) {
        guard source == "app-intent" else { return }
        shortcutReturnReadiness.presentationEstablished(id: id)
        logger.notice("shortcut return readiness presentation-established id=\(id) phase=\(String(describing: shortcutReturnReadiness.phase))")
        releaseShortcutReadinessWaitersIfTerminal()
    }

    func finishShortcutReturnReadiness(id: String, result: OrbitMiniShortcutReadinessWaitResult) {
        switch result {
        case .failed:
            shortcutReturnReadiness.fail(id: id)
        case .cancelled:
            shortcutReturnReadiness.cancel(id: id)
        case .ready, .timedOut:
            return
        }
        logger.notice("shortcut return readiness terminal id=\(id) result=\(String(describing: result))")
        releaseShortcutReadinessWaitersIfTerminal()
    }

    func releaseShortcutReadinessWaitersIfTerminal() {
        let result: OrbitMiniShortcutReadinessWaitResult?
        switch shortcutReturnReadiness.phase {
        case .ready: result = .ready
        case .failed: result = .failed
        case .cancelled: result = .cancelled
        case .idle, .starting: result = nil
        }
        guard let result else { return }
        let waiters = shortcutReadinessWaiters
        shortcutReadinessWaiters.removeAll()
        waiters.values.forEach { $0.resume(result) }
    }

    func startDirectSession(startID: String, source: String) async -> Bool {
        await attemptLiveKitStart(number: 1, source: source)
        let ready = runtime.session.isConnected && AudioManager.shared.isEngineRunning
        if !ready {
            lastStartupError = runtime.session.error?.localizedDescription
            await cleanUpFailedSessionAttempt(startID: startID, attempt: 1, reason: "direct-session-failed")
        }
        return ready
    }

    func startAppIntentSessionWithRetry(startID: String) async -> Bool {
        var retry = OrbitMiniSessionStartRetryStateMachine(maximumAttempts: 3)
        retry.begin()
        let retryTimeouts: [Duration] = [.milliseconds(250), .milliseconds(750)]

        while !Task.isCancelled, !isTerminating {
            guard isUsableForegroundActive else {
                lastStartupError = "Lifecycle changed before Session.start"
                logger.notice("Session.start retry paused before active id=\(startID)")
                return false
            }
            guard let attempt = retry.claimAttempt() else { break }
            await attemptLiveKitStart(number: attempt, source: "shortcut-appintent")
            let ready = runtime.session.isConnected && AudioManager.shared.isEngineRunning
            if ready {
                retry.succeeded()
                logger.notice("AppIntent Session.start success id=\(startID) attempt=\(attempt) engineRunning=true")
                return true
            }

            let detail = currentAudioErrorDescription
            lastStartupError = detail.isEmpty ? "Не вдалося запустити голосову сесію." : detail
            let transient = isTransientAudioFailure(detail)
            logger.error("AppIntent Session.start failure id=\(startID) attempt=\(attempt) transient=\(transient) error=\(lastStartupError ?? "unknown")")
            await cleanUpFailedSessionAttempt(startID: startID, attempt: attempt, reason: "session-start-failed")
            retry.failed(transient: transient)

            guard case let .waitingForRetry(failedAttempt) = retry.phase else { break }
            let timeout = retryTimeouts[min(max(failedAttempt - 1, 0), retryTimeouts.count - 1)]
            let signalled = await waitForAudioSignalOrTimeout(reason: "transient-session-retry-\(failedAttempt)", timeout: timeout)
            logger.notice("Session.start retry gate id=\(startID) attempt=\(failedAttempt) signal=\(signalled)")
            retry.retryDelayElapsed()
        }

        if Task.isCancelled || isTerminating {
            retry.cancel()
        }
        return false
    }

    func cleanUpFailedSessionAttempt(startID: String, attempt: Int, reason: String) async {
        if runtime.session.room.connectionState != .disconnected {
            logger.notice("LiveKit Session cleanup begin id=\(startID) attempt=\(attempt) reason=\(reason) state=\(String(describing: runtime.session.room.connectionState))")
            await runtime.session.end()
            logger.notice("LiveKit Session cleanup end id=\(startID) attempt=\(attempt) roomState=\(String(describing: runtime.session.room.connectionState))")
        } else {
            logger.notice("LiveKit Session cleanup no-room id=\(startID) attempt=\(attempt) reason=\(reason)")
        }
        runtime.session.dismissError()
        runtime.localMedia.dismissError()
    }

    /// Registered before its timeout task, so notification and timeout races
    /// are one-shot and can never launch competing Session retries.
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

    /// Waits only for authoritative UIKit activation. Audio/route events do
    /// not wake this gate, and its deadline never promotes an inactive app.
    func waitForUsableForegroundActive(timeout: Duration) async -> OrbitMiniLifecycleWaitResult {
        if isUsableForegroundActive {
            return .active(trigger: "initial-reconciliation")
        }

        let token = UUID()
        logger.notice("lifecycle wait begin timeoutSeconds=20 app=\(self.applicationStateDescription) scene=\(self.sceneStateDescription)")
        let result = await withCheckedContinuation { continuation in
            let waiter = OrbitMiniLifecycleSignalWaiter(continuation)
            if isUsableForegroundActive {
                waiter.resume(.active(trigger: "registration-reconciliation"))
                return
            }
            lifecycleSignalWaiters[token] = waiter
            Task {
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                waiter.resume(.timedOut)
            }
        }
        lifecycleSignalWaiters.removeValue(forKey: token)
        logger.notice("lifecycle wait end result=\(String(describing: result)) app=\(self.applicationStateDescription) scene=\(self.sceneStateDescription)")
        return result
    }

    func signalAudioHandoff(_ event: OrbitMiniAudioHandoffStateMachine.Event, reason: String) {
        mutateAudioHandoff(event)
        signalAudioWaiters(reason: reason)
    }

    func signalAudioWaiters(reason: String) {
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
        signalAudioWaiters(reason: "route-changed")
    }

    func handleAvailableInputsChange() {
        logger.notice("AVAudioSession available inputs changed")
        logAudioReadiness()
        signalAudioWaiters(reason: "available-inputs-changed")
    }

    func handleApplicationDidBecomeActive() {
        reconcileLifecycleActivation(trigger: "UIApplication.didBecomeActive")
    }

    func handleSceneDidActivate() {
        reconcileLifecycleActivation(trigger: "UIScene.didActivate")
    }

    func reconcileLifecycleActivation(trigger: String) {
        logger.notice("lifecycle activation signal trigger=\(trigger) app=\(self.applicationStateDescription) scene=\(self.sceneStateDescription) usableActive=\(self.isUsableForegroundActive)")
        guard isUsableForegroundActive else { return }
        mutateAudioHandoff(.appBecameActive)
        let waiters = lifecycleSignalWaiters
        lifecycleSignalWaiters.removeAll()
        waiters.values.forEach { $0.resume(.active(trigger: trigger)) }
    }

    func handleLifecycleBecameInactive(trigger: String) {
        logger.notice("lifecycle inactive signal trigger=\(trigger) app=\(self.applicationStateDescription) scene=\(self.sceneStateDescription)")
        mutateAudioHandoff(.appBecameInactive)
    }

    func handleMediaServicesReset() {
        logger.error("AVAudioSession media services were reset")
        signalAudioWaiters(reason: "media-services-reset")
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
        if connectionState == .connected {
            Task { @MainActor [weak self] in
                guard let self, let startID = self.shortcutReturnReadiness.activeStartID else { return }
                self.markShortcutReturnRoomConnected(id: startID, source: "app-intent")
            }
        }
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
