#if DEBUG
import AVFoundation
import Combine
import Foundation

@MainActor
final class InterpreterFixtureRecorder: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var lastFixtureID: String?
    @Published private(set) var lastFileURL: URL?
    @Published private(set) var lastDirection: InterpreterDirection?
    @Published private(set) var lastSourceText: String?
    @Published private(set) var startedAt: Date?
    @Published private(set) var endedAt: Date?
    private var recorder: AVAudioRecorder?

    func start(fixtureID: String, direction: InterpreterDirection, sourceText: String) throws {
        guard !fixtureID.isEmpty, !isRecording else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("interpreter-\(fixtureID)-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.allowBluetooth])
        try session.setActive(true)
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.record()
        self.recorder = recorder
        lastFixtureID = fixtureID
        lastDirection = direction
        lastSourceText = sourceText
        lastFileURL = url
        startedAt = Date()
        endedAt = nil
        isRecording = true
    }

    func stop() {
        recorder?.stop()
        recorder = nil
        endedAt = Date()
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func deleteLast() {
        stop()
        if let url = lastFileURL { try? FileManager.default.removeItem(at: url) }
        lastFileURL = nil
        lastFixtureID = nil
        lastDirection = nil
        lastSourceText = nil
        startedAt = nil
        endedAt = nil
    }
}
#endif
