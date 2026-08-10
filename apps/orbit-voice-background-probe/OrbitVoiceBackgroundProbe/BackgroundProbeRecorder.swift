import ActivityKit
import AVFoundation
import Foundation
import UIKit

@MainActor
final class BackgroundProbeRecorder: ObservableObject {
    static let shared = BackgroundProbeRecorder()

    @Published private(set) var phase = "Idle"
    @Published private(set) var buffers = 0
    @Published private(set) var detail = "No test has run."
    @Published private(set) var updatedAt = "—"

    private let engine = AVAudioEngine()
    private var activity: Activity<ProbeAttributes>?
    private var stopTask: Task<Void, Never>?
    private var isRecording = false

    private init() { loadPersistedStatus() }

    func refresh() { loadPersistedStatus() }

    func requestMicrophonePermission() async {
        let granted = await AVAudioApplication.requestRecordPermission()
        publish(
            phase: granted ? "Permission granted" : "Permission denied",
            buffers: 0,
            detail: granted ? "Microphone permission is ready for the background probe." : "Enable Microphone for Orbit Voice Probe in Settings before testing."
        )
    }

    func start(origin: String) async throws {
        guard !isRecording else {
            publish(phase: "Recording", buffers: buffers, detail: "Already recording; origin=\(origin)")
            return
        }

        publish(phase: "Starting", buffers: 0, detail: "Intent entered; origin=\(origin); appState=\(UIApplication.shared.applicationState.rawValue)")

        do {
            let attributes = ProbeAttributes(startedAt: Date())
            let content = ActivityContent(
                state: ProbeAttributes.ContentState(
                    phase: "Starting",
                    buffers: 0,
                    detail: "Requesting microphone"
                ),
                staleDate: nil
            )
            activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
            publish(phase: "Live Activity active", buffers: 0, detail: "Live Activity requested successfully.")
        } catch {
            publish(phase: "Live Activity failed", buffers: 0, detail: "\(error.localizedDescription)")
            throw ProbeError.liveActivity(error.localizedDescription)
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.allowBluetooth])
            try session.setActive(true)
            publish(phase: "Audio session active", buffers: 0, detail: "category=record mode=measurement")

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] _, _ in
                Task { @MainActor in self?.receivedBuffer() }
            }
            engine.prepare()
            try engine.start()
            isRecording = true
            publish(phase: "Recording", buffers: 0, detail: "AVAudioEngine started; waiting for input buffers.")
            updateActivity()

            stopTask?.cancel()
            stopTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(12))
                await self?.stop(reason: "Automatic timeout after 12 seconds")
            }
        } catch {
            await stop(reason: "Audio failure: \(error.localizedDescription)")
            throw ProbeError.audio(error.localizedDescription)
        }
    }

    func stop(reason: String = "Stopped by intent") async {
        stopTask?.cancel()
        stopTask = nil
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        await activity?.end(ActivityContent(state: .init(phase: "Stopped", buffers: buffers, detail: reason), staleDate: nil), dismissalPolicy: .immediate)
        activity = nil
        publish(phase: "Stopped", buffers: buffers, detail: reason)
    }

    private func receivedBuffer() {
        guard isRecording else { return }
        buffers += 1
        if buffers == 1 || buffers % 25 == 0 {
            publish(phase: "Recording", buffers: buffers, detail: "Received actual microphone input buffers.")
            updateActivity()
        }
    }

    private func updateActivity() {
        guard let activity else { return }
        let state = ProbeAttributes.ContentState(phase: phase, buffers: buffers, detail: detail)
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    private func publish(phase: String, buffers: Int, detail: String) {
        self.phase = phase
        self.buffers = buffers
        self.detail = detail
        updatedAt = ISO8601DateFormatter().string(from: Date())
        ProbeStatusStore.write(phase: phase, buffers: buffers, detail: detail)
    }

    private func loadPersistedStatus() {
        let value = ProbeStatusStore.read()
        phase = value.phase
        buffers = value.buffers
        detail = value.detail
        updatedAt = value.updatedAt
    }
}

enum ProbeError: LocalizedError {
    case liveActivity(String)
    case audio(String)

    var errorDescription: String? {
        switch self {
        case let .liveActivity(message): return "Live Activity failed: \(message)"
        case let .audio(message): return "Audio failed: \(message)"
        }
    }
}
