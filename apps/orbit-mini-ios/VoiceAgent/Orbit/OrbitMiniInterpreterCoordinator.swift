import AVFoundation
import Combine
import Foundation
import MicrosoftCognitiveServicesSpeech

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
        let config = try SPXSpeechTranslationConfiguration(authorizationToken: credential.token, region: credential.region)
        config.speechRecognitionLanguage = direction.sourceLanguage
        config.addTargetLanguage(direction.targetLanguage)
        let audio = SPXAudioConfiguration()
        let recognizer = try SPXTranslationRecognizer(
            speechTranslationConfiguration: config,
            audioConfiguration: audio
        )
        recognizer.addRecognizingEventHandler { [weak self] (_: SPXTranslationRecognizer, event: SPXTranslationRecognitionEventArgs) in
            Task { @MainActor in
                self?.sourceText = event.result.text
                self?.state = .partialSource(event.result.text)
            }
        }
        recognizer.addRecognizedEventHandler { [weak self] (_: SPXTranslationRecognizer, event: SPXTranslationRecognitionEventArgs) in
            Task { @MainActor in
                let result = event.result
                self?.sourceText = result.text
                self?.state = .finalSource(result.text)
                if let translation = result.translations[self?.direction.targetLanguage ?? ""] as? String {
                    self?.translatedText = translation
                    self?.state = .translatedText(translation)
                }
            }
        }
        recognizer.addCanceledEventHandler { [weak self] (_: SPXTranslationRecognizer, _: SPXTranslationRecognitionCanceledEventArgs) in
            Task { @MainActor in
                self?.state = .error("Azure Speech session was canceled.")
                self?.cleanup()
            }
        }
        recognizer.startContinuousRecognition()
        self.recognizer = recognizer
    }

    private func cleanup() {
        refreshTask?.cancel()
        refreshTask = nil
        recognizer = nil
        credential = nil
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
