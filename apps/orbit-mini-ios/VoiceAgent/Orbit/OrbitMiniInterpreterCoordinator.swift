import AVFoundation
import Combine
import Foundation
import MicrosoftCognitiveServicesSpeech

/// Executor-neutral delivery point for callbacks raised by the Objective-C
/// Speech SDK. The SDK may invoke these closures on an arbitrary native
/// pthread, so they must not capture the MainActor coordinator directly.
private actor InterpreterRecognizerCallbackSink {
    weak var coordinator: OrbitMiniInterpreterCoordinator?

    init(coordinator: OrbitMiniInterpreterCoordinator) {
        self.coordinator = coordinator
    }

    func partial(_ text: String, generation: UInt64) async {
        await coordinator?.receivePartial(text, generation: generation)
    }

    func recognized(source: String, translation: String?, generation: UInt64) async {
        await coordinator?.receiveRecognized(source: source, translation: translation, generation: generation)
    }

    func canceled(generation: UInt64) async {
        await coordinator?.receiveCanceled(generation: generation)
    }
}

/// File-scope (therefore non-MainActor) callback registration. Keeping the
/// closure literals here is important: defining them inside the @MainActor
/// coordinator would attach that executor to the native SDK entry point.
private func installInterpreterRecognizerCallbacks(
    on recognizer: SPXTranslationRecognizer,
    sink: InterpreterRecognizerCallbackSink,
    generation: UInt64,
    targetLanguage: String
) {
    recognizer.addRecognizingEventHandler { (_: SPXTranslationRecognizer, event: SPXTranslationRecognitionEventArgs) in
        guard let text = event.result.text, !text.isEmpty else { return }
        Task { await sink.partial(text, generation: generation) }
    }
    recognizer.addRecognizedEventHandler { (_: SPXTranslationRecognizer, event: SPXTranslationRecognitionEventArgs) in
        let result = event.result
        guard let text = result.text, !text.isEmpty else { return }
        let translation = result.translations[targetLanguage] as? String
        Task { await sink.recognized(source: text, translation: translation, generation: generation) }
    }
    recognizer.addCanceledEventHandler { (_: SPXTranslationRecognizer, _: SPXTranslationRecognitionCanceledEventArgs) in
        Task { await sink.canceled(generation: generation) }
    }
}

@MainActor
final class OrbitMiniInterpreterCoordinator: NSObject, ObservableObject {
    @Published private(set) var state: InterpreterState = .idle
    @Published private(set) var sourceText = ""
    @Published private(set) var translatedText = ""
    @Published private(set) var isActive = false

    private let tokenClient = InterpreterTokenClient()
    private var recognizer: SPXTranslationRecognizer?
    private var credential: InterpreterCredential?
    private var direction: InterpreterDirection = .ukrainianToGerman
    private var refreshTask: Task<Void, Never>?
    private var callbackSink: InterpreterRecognizerCallbackSink?
    private var sessionGeneration: UInt64 = 0

    func start(direction: InterpreterDirection) async {
        guard !isActive else { return }
        guard !OrbitMiniVoiceCoordinator.shared.isVoiceActive else {
            state = .error("Спершу завершіть Orbit Voice.")
            return
        }
        self.direction = direction
        state = .requestingCredential
        do {
            let credential = try await tokenClient.requestCredential(for: direction)
            self.credential = credential
            try configureAndStart(credential: credential)
            isActive = true
            state = .listening
            scheduleRefresh(for: credential)
        } catch {
            state = .error(error.localizedDescription)
            cleanup()
        }
    }

    func stop() async {
        guard isActive || recognizer != nil else { return }
        state = .stopping
        try? recognizer?.stopContinuousRecognition()
        cleanup()
        state = .idle
    }

    private func configureAndStart(credential: InterpreterCredential) throws {
        sessionGeneration &+= 1
        let generation = sessionGeneration
        let config = try SPXSpeechTranslationConfiguration(authorizationToken: credential.token, region: credential.region)
        config.speechRecognitionLanguage = direction.sourceLanguage
        config.addTargetLanguage(direction.azureTargetLanguage)
        let targetLanguage = direction.azureTargetLanguage
        let audio = SPXAudioConfiguration()
        let recognizer = try SPXTranslationRecognizer(
            speechTranslationConfiguration: config,
            audioConfiguration: audio
        )
        let sink = InterpreterRecognizerCallbackSink(coordinator: self)
        callbackSink = sink
        installInterpreterRecognizerCallbacks(on: recognizer, sink: sink, generation: generation, targetLanguage: targetLanguage)
        try recognizer.startContinuousRecognition()
        self.recognizer = recognizer
    }

    fileprivate func receivePartial(_ text: String, generation: UInt64) {
        guard generation == sessionGeneration, isActive || state == .requestingCredential else { return }
        sourceText = text
        state = .partialSource(text)
    }

    fileprivate func receiveRecognized(source: String, translation: String?, generation: UInt64) {
        guard generation == sessionGeneration, isActive else { return }
        sourceText = source
        state = .finalSource(source)
        if let translation, !translation.isEmpty {
            translatedText = translation
            state = .translatedText(translation)
        }
    }

    fileprivate func receiveCanceled(generation: UInt64) {
        guard generation == sessionGeneration else { return }
        state = .error("Azure Speech session was canceled.")
        cleanup()
    }

    private func cleanup() {
        sessionGeneration &+= 1
        refreshTask?.cancel()
        refreshTask = nil
        recognizer = nil
        credential = nil
        callbackSink = nil
        isActive = false
    }

    private func scheduleRefresh(for initial: InterpreterCredential) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            let delay = max(30, initial.expiresAt.timeIntervalSinceNow - 90)
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, self.isActive else { return }
            do {
                let next = try await self.tokenClient.requestCredential(for: self.direction)
                self.credential = next
                self.recognizer?.authorizationToken = next.token
                self.scheduleRefresh(for: next)
            } catch {
                await self.stopAfterRefreshFailure()
            }
        }
    }

    private func stopAfterRefreshFailure() async {
        guard isActive else { return }
        try? recognizer?.stopContinuousRecognition()
        cleanup()
        state = .error("Не вдалося оновити захищений токен перекладу.")
    }
}
