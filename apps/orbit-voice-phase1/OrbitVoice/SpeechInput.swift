import AVFoundation
import Speech

final class SpeechInput: NSObject, SFSpeechRecognizerDelegate {
    var onState: ((Bool) -> Void)?
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "uk-UA"))!
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceWork: DispatchWorkItem?
    private var continuation: CheckedContinuation<String, Error>?
    private var latestText = ""

    func listen() async throws -> String {
        stop()
        recognizer.delegate = self
        request = SFSpeechAudioBufferRecognitionRequest()
        request?.shouldReportPartialResults = true
        request?.requiresOnDeviceRecognition = false
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.latestText = ""
            task = recognizer.recognitionTask(with: request!) { [weak self] result, error in
                if let result {
                    self?.latestText = result.bestTranscription.formattedString
                    self?.scheduleStop()
                    if result.isFinal { self?.finish(returning: self?.latestText ?? "") }
                }
                if let error, self?.latestText.isEmpty == true {
                    self?.finish(throwing: error)
                }
            }
            input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
                self?.request?.append(buffer)
            }
            do {
                engine.prepare(); try engine.start(); onState?(true)
            } catch { finish(throwing: error) }
        }
    }

    func stop() { finish() }

    private func scheduleStop() {
        silenceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.latestText.isEmpty { self.finish() } else { self.finish(returning: self.latestText) }
        }
        silenceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
    }

    private func finish(returning value: String? = nil, throwing error: Error? = nil) {
        silenceWork?.cancel(); silenceWork = nil
        engine.stop(); engine.inputNode.removeTap(onBus: 0)
        request?.endAudio(); request = nil
        task?.cancel(); task = nil
        onState?(false)
        if let continuation {
            self.continuation = nil
            if let error { continuation.resume(throwing: error) }
            else { continuation.resume(returning: value ?? latestText) }
        }
    }
}
