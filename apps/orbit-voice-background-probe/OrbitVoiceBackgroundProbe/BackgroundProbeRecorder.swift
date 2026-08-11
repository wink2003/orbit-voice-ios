import ActivityKit
import AVFoundation
import Foundation
import UIKit

@MainActor
final class BackgroundProbeRecorder: ObservableObject {
    static let shared = BackgroundProbeRecorder()

    @Published private(set) var phase = "Idle"
    @Published private(set) var buffers = 0
    @Published private(set) var foregroundBuffers = 0
    @Published private(set) var backgroundBuffers = 0
    @Published private(set) var audioSessionActive = false
    @Published private(set) var detail = "No test has run."
    @Published private(set) var diagnostics: [String] = []
    @Published private(set) var destructionErrorDetails: String?
    @Published private(set) var updatedAt = "—"

    private let engine = AVAudioEngine()
    private var activity: Activity<ProbeAttributes>?
    private var activityStateTask: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?
    private var isRecording = false
    private var isInBackground = false
    private var destroySceneAfterFirstBuffer = false
    private var sceneDestructionRequested = false
    private var loggedBackgroundBufferAfterSceneDestruction = false
    private var sceneSessionPendingDestruction: UISceneSession?
    private weak var visibleProbeWindow: UIWindow?
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var liveActivityPhase = "starting"
    private var listeningAlertRequested = false

    private init() {
        loadPersistedStatus()
        let center = NotificationCenter.default
        lifecycleObservers = [
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.enteredBackground() }
            },
            center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.enteredForeground() }
            },
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.becameActive() }
            },
            center.addObserver(forName: UIScene.didDisconnectNotification, object: nil, queue: .main) { [weak self] notification in
                let scene = notification.object as? UIScene
                Task { @MainActor in self?.sceneDidDisconnect(scene) }
            },
        ]
    }

    deinit {
        lifecycleObservers.forEach(NotificationCenter.default.removeObserver)
    }

    func refresh() { loadPersistedStatus() }

    func showError(_ message: String) {
        publish(phase: "Error", buffers: buffers, detail: message)
    }

    func noteIntent(_ message: String) {
        appendDiagnostic(message)
        persistCurrentStatus()
    }

    func captureVisibleProbeWindow(_ window: UIWindow?) {
        guard let window else { return }
        visibleProbeWindow = window
        isInBackground = false
        appendDiagnostic("Visible Probe window captured; key=\(window.isKeyWindow); session=\(window.windowScene?.session.persistentIdentifier ?? "none"); state=\(window.windowScene?.activationState.rawValue ?? -1)")
        persistCurrentStatus()
        if destroySceneAfterFirstBuffer, buffers > 0 { requestSceneDestructionAfterFirstBuffer() }
    }

    func discardedSceneSessions(_ sessions: Set<UISceneSession>) {
        let identifiers = sessions.map(\.persistentIdentifier).joined(separator: ",")
        appendDiagnostic("application didDiscardSceneSessions; sessions=\(identifiers)")
        persistCurrentStatus()
    }

    func requestMicrophonePermission() async {
        let granted = await AVAudioApplication.requestRecordPermission()
        publish(
            phase: granted ? "Permission granted" : "Permission denied",
            buffers: 0,
            detail: granted ? "Microphone permission is ready for the background probe." : "Enable Microphone for Orbit Voice Probe in Settings before testing."
        )
    }

    func start(origin: String) async throws {
        try await begin(origin: origin, automaticStopAfter: .seconds(12))
    }

    func startForegroundBackgroundTest() async throws {
        try await begin(origin: "Foreground UI", automaticStopAfter: nil)
    }

    func startForegroundBootstrapSceneDestructionTest() async throws {
        try await begin(
            origin: "AppIntent.foregroundBootstrapSceneDestruction",
            automaticStopAfter: nil,
            requestSceneDestructionAfterFirstBuffer: true
        )
    }

    private func begin(
        origin: String,
        automaticStopAfter: Duration?,
        requestSceneDestructionAfterFirstBuffer: Bool = false
    ) async throws {
        guard !isRecording else {
            publish(phase: "Recording", buffers: buffers, detail: "Already recording; origin=\(origin)")
            return
        }

        diagnostics = []
        destructionErrorDetails = nil
        liveActivityPhase = "starting"
        listeningAlertRequested = false
        appendDiagnostic("Recorder begin; origin=\(origin); appState=\(UIApplication.shared.applicationState.rawValue)")
        publish(phase: "Starting", buffers: 0, detail: "Starting recorder; origin=\(origin)")
        foregroundBuffers = 0
        backgroundBuffers = 0
        // UIKit commonly reports .inactive while Shortcuts is handing off a visible app.
        // Only the actual background state counts as a background microphone buffer.
        isInBackground = UIApplication.shared.applicationState == .background
        destroySceneAfterFirstBuffer = requestSceneDestructionAfterFirstBuffer
        sceneDestructionRequested = false
        loggedBackgroundBufferAfterSceneDestruction = false
        sceneSessionPendingDestruction = nil
        if requestSceneDestructionAfterFirstBuffer {
            appendDiagnostic("Scene destruction armed; session will be resolved after first microphone buffer")
        }

        do {
            let attributes = ProbeAttributes(startedAt: Date())
            let content = ActivityContent(
                state: ProbeAttributes.ContentState(
                    phase: liveActivityPhase,
                    buffers: 0,
                    detail: "Requesting microphone"
                ),
                staleDate: nil
            )
            activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
            appendDiagnostic("Live Activity created; id=\(activity?.id ?? "unknown")")
            observeActivityState()
            publish(phase: "Live Activity active", buffers: 0, detail: "Live Activity requested successfully.")
        } catch {
            publish(phase: "Live Activity failed", buffers: 0, detail: "\(error.localizedDescription)")
            throw ProbeError.liveActivity(error.localizedDescription)
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.allowBluetooth])
            try session.setActive(true)
            audioSessionActive = true
            appendDiagnostic("AVAudioSession activated")
            publish(phase: "Audio session active", buffers: 0, detail: "category=record mode=measurement")

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] _, _ in
                Task { @MainActor in self?.receivedBuffer() }
            }
            engine.prepare()
            try engine.start()
            isRecording = true
            liveActivityPhase = "listening"
            appendDiagnostic("AVAudioEngine started")
            publish(phase: "Recording", buffers: 0, detail: "AVAudioEngine started; waiting for input buffers.")
            updateActivity()

            if let automaticStopAfter {
                stopTask?.cancel()
                stopTask = Task { [weak self] in
                    try? await Task.sleep(for: automaticStopAfter)
                    await self?.stop(reason: "Automatic timeout after 12 seconds")
                }
            }
        } catch {
            await stop(reason: "Audio failure: \(error.localizedDescription)")
            throw ProbeError.audio(error.localizedDescription)
        }
    }

    func stop(reason: String = "Stopped by intent") async {
        stopTask?.cancel()
        stopTask = nil
        activityStateTask?.cancel()
        activityStateTask = nil
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        isRecording = false
        destroySceneAfterFirstBuffer = false
        sceneSessionPendingDestruction = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        audioSessionActive = false
        appendDiagnostic("Recorder stopped; reason=\(reason)")
        liveActivityPhase = "ended"
        appendDiagnostic("Live Activity ending; id=\(activity?.id ?? "unknown")")
        await activity?.end(ActivityContent(state: .init(phase: liveActivityPhase, buffers: buffers, detail: reason), staleDate: nil), dismissalPolicy: .immediate)
        activity = nil
        publish(phase: "Stopped", buffers: buffers, detail: reason)
    }

    private func receivedBuffer() {
        guard isRecording else { return }
        buffers += 1
        if buffers == 1 || buffers % 25 == 0 {
            if isInBackground { backgroundBuffers += 1 } else { foregroundBuffers += 1 }
            publish(phase: "Recording", buffers: buffers, detail: "Received microphone buffers; foreground=\(foregroundBuffers), background=\(backgroundBuffers)")
            updateActivity()
        }
        if buffers > 1 && buffers % 25 != 0 {
            if isInBackground { backgroundBuffers += 1 } else { foregroundBuffers += 1 }
        }

        if buffers == 1, destroySceneAfterFirstBuffer {
            requestSceneDestructionAfterFirstBuffer()
        }
        if sceneDestructionRequested, isInBackground, !loggedBackgroundBufferAfterSceneDestruction {
            loggedBackgroundBufferAfterSceneDestruction = true
            appendDiagnostic("First background buffer after scene destruction; buffers=\(buffers); background=\(backgroundBuffers)")
            persistCurrentStatus()
        }
    }

    private func requestSceneDestructionAfterFirstBuffer() {
        guard let window = visibleProbeWindow, let scene = window.windowScene else {
            appendDiagnostic("Scene destruction pending: visible Probe window has not been captured")
            persistCurrentStatus()
            return
        }
        guard scene.activationState == .foregroundActive else {
            appendDiagnostic("Scene destruction pending: target scene state=\(scene.activationState.rawValue), requires foregroundActive")
            persistCurrentStatus()
            return
        }
        let session = scene.session
        // Keep the request armed until the real, active UIWindowScene is available.
        // This avoids losing the one-shot request if the first audio buffer arrives
        // during the Shortcuts handoff before UIKit has attached the visible window.
        destroySceneAfterFirstBuffer = false
        sceneSessionPendingDestruction = session
        sceneDestructionRequested = true
        appendDiagnostic(sceneInventory(targetWindow: window, targetScene: scene))
        appendDiagnostic("Requesting scene destruction; session=\(session.persistentIdentifier); buffersBefore=\(buffers)")
        persistCurrentStatus()
        UIApplication.shared.requestSceneSessionDestruction(session, options: nil) { [weak self] error in
            Task { @MainActor in
                let nsError = error as NSError
                let fullError = "domain=\(nsError.domain); code=\(nsError.code); description=\(nsError.localizedDescription); userInfo=\(nsError.userInfo)"
                self?.destructionErrorDetails = fullError
                self?.appendDiagnostic("Scene destruction error: \(fullError)")
                self?.persistCurrentStatus()
            }
        }
    }

    private func updateActivity() {
        guard let activity else { return }
        let state = ProbeAttributes.ContentState(phase: liveActivityPhase, buffers: buffers, detail: detail)
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    private func observeActivityState() {
        activityStateTask?.cancel()
        guard let activity else { return }
        activityStateTask = Task { [weak self, activity] in
            for await state in activity.activityStateUpdates {
                guard let self else { return }
                self.appendDiagnostic("Live Activity state=\(String(describing: state)); id=\(activity.id)")
                self.persistCurrentStatus()
            }
        }
    }

    private func requestListeningAlertAfterBackgroundTransition() {
        guard isRecording, buffers > 0 else {
            appendDiagnostic("Listening alert deferred: recording=\(isRecording); buffers=\(buffers)")
            persistCurrentStatus()
            return
        }
        guard !listeningAlertRequested, let activity else { return }

        listeningAlertRequested = true
        liveActivityPhase = "listening"
        let content = ActivityContent(
            state: ProbeAttributes.ContentState(
                phase: liveActivityPhase,
                buffers: buffers,
                detail: "Microphone recording is active"
            ),
            staleDate: nil
        )
        let alert = AlertConfiguration(title: "ORBIT", body: "Слухаю…", sound: .default)
        appendDiagnostic("Listening alert update requested; id=\(activity.id); buffers=\(buffers)")
        persistCurrentStatus()

        Task { [weak self, activity] in
            await activity.update(content, alertConfiguration: alert)
            guard let self else { return }
            self.appendDiagnostic("Listening alert update completed; id=\(activity.id); state=\(String(describing: activity.activityState))")
            self.persistCurrentStatus()
        }
    }

    private func publish(phase: String, buffers: Int, detail: String) {
        self.phase = phase
        self.buffers = buffers
        self.detail = detail
        updatedAt = ISO8601DateFormatter().string(from: Date())
        persistCurrentStatus()
    }

    private func appendDiagnostic(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        diagnostics.append("\(timestamp)  \(message)")
        if diagnostics.count > 20 { diagnostics.removeFirst(diagnostics.count - 20) }
    }

    private func persistCurrentStatus() {
        ProbeStatusStore.write(
            phase: phase,
            buffers: buffers,
            detail: detail,
            foregroundBuffers: foregroundBuffers,
            backgroundBuffers: backgroundBuffers,
            diagnostics: diagnostics,
            destructionErrorDetails: destructionErrorDetails
        )
    }

    private func enteredBackground() {
        isInBackground = true
        appendDiagnostic("Scene entered background")
        if isRecording { publish(phase: "Recording", buffers: buffers, detail: "Probe entered background; counting input buffers.") }
        requestListeningAlertAfterBackgroundTransition()
    }

    private func enteredForeground() {
        isInBackground = false
        appendDiagnostic("Scene entered foreground")
        if isRecording { publish(phase: "Recording", buffers: buffers, detail: "Probe returned to foreground; recording continues.") }
    }

    private func becameActive() {
        isInBackground = false
        appendDiagnostic("Application became active")
        persistCurrentStatus()
        if destroySceneAfterFirstBuffer, buffers > 0 { requestSceneDestructionAfterFirstBuffer() }
    }

    private func sceneDidDisconnect(_ scene: UIScene?) {
        let identifier = scene?.session.persistentIdentifier ?? "unknown"
        appendDiagnostic("sceneDidDisconnect; session=\(identifier); recording=\(isRecording); buffers=\(buffers)")
        // The recorder is a process-level singleton. Scene loss must not stop an active audio test.
        persistCurrentStatus()
    }

    private func sceneInventory(targetWindow: UIWindow, targetScene: UIWindowScene) -> String {
        let connected = UIApplication.shared.connectedScenes.map { scene in
            "id=\(scene.session.persistentIdentifier),state=\(scene.activationState.rawValue)"
        }.sorted().joined(separator: " | ")
        let open = UIApplication.shared.openSessions.map(\.persistentIdentifier).sorted().joined(separator: ",")
        let ownsKeyWindow = targetWindow.isKeyWindow || targetScene.windows.contains(where: \.isKeyWindow)
        return "Destruction target; appState=\(UIApplication.shared.applicationState.rawValue); targetState=\(targetScene.activationState.rawValue); targetSession=\(targetScene.session.persistentIdentifier); ownsVisibleKeyWindow=\(ownsKeyWindow); connected=[\(connected)]; open=[\(open)]"
    }

    private func loadPersistedStatus() {
        let value = ProbeStatusStore.read()
        phase = value.phase
        buffers = value.buffers
        foregroundBuffers = value.foregroundBuffers
        backgroundBuffers = value.backgroundBuffers
        detail = value.detail
        diagnostics = value.diagnostics
        destructionErrorDetails = value.destructionErrorDetails
        updatedAt = value.updatedAt
    }
}

enum ProbeError: LocalizedError {
    case liveActivity(String)
    case audio(String)
    case foregroundUnavailable

    var errorDescription: String? {
        switch self {
        case let .liveActivity(message): return "Live Activity failed: \(message)"
        case let .audio(message): return "Audio failed: \(message)"
        case .foregroundUnavailable: return "Foreground transition is unavailable in this App Intent context."
        }
    }
}
