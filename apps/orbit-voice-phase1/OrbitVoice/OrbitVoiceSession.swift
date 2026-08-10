import AVFoundation
import Foundation
import Speech
import UIKit

@MainActor
final class OrbitVoiceSession: NSObject, ObservableObject {
    enum State: Equatable { case idle, listening, thinking, speaking, error(String) }

    @Published private(set) var state: State = .idle
    @Published private(set) var isPaired = Phase1Keychain.readToken() != nil
    @Published private(set) var displayName = UserDefaults.standard.string(forKey: "orbit.phase1.displayName")

    let endpoint = URL(string: "https://voice.orbit.opik.net/api/voice")!
    private var sessionID: String?
    private let speech = SpeechInput()
    private var player: AVAudioPlayer?
    private var audioDelegate: AudioDelegate?

    private struct PairingResponse: Decodable { let deviceToken: String; let profile: Profile }
    private struct Profile: Decodable { let displayName: String }

    override init() {
        super.init()
        speech.onState = { [weak self] listening in
            Task { @MainActor in
                if listening { self?.state = .listening }
            }
        }
    }

    func pair(code: String) async throws {
        let normalized = code.filter(\.isNumber)
        guard normalized.count == 6 else { throw VoiceError.message("Введіть шестизначний код.") }
        var request = URLRequest(url: URL(string: "https://voice.orbit.opik.net/api/devices/pair")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "pairingCode": normalized,
            "deviceName": UIDevice.current.name,
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw VoiceError.message(message ?? "Не вдалося активувати Orbit Voice.")
        }
        let result = try JSONDecoder().decode(PairingResponse.self, from: data)
        try Phase1Keychain.saveToken(result.deviceToken)
        UserDefaults.standard.set(result.profile.displayName, forKey: "orbit.phase1.displayName")
        displayName = result.profile.displayName
        isPaired = true
    }

    func start() async {
        guard isPaired, state == .idle else { return }
        do {
            try await requestPermissions()
            try configureAudio()
            let id = UUID().uuidString.lowercased()
            sessionID = id
            _ = try await request(action: "start", sessionID: id, text: nil)
            try await listenForTurn()
        } catch { fail(error) }
    }

    func end() async {
        let id = sessionID
        sessionID = nil
        speech.stop()
        player?.stop()
        player = nil
        if let id, let token = Phase1Keychain.readToken() {
            _ = try? await request(action: "end", sessionID: id, text: "кінець", token: token)
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        state = .idle
    }

    private func listenForTurn() async throws {
        guard sessionID != nil else { return }
        state = .listening
        let text = try await speech.listen()
        let normalized = Self.normalize(text)
        if Self.endPhrases.contains(normalized) {
            await end()
            return
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            try await listenForTurn()
            return
        }
        state = .thinking
        do {
            let data = try await request(action: "turn", sessionID: sessionID!, text: text)
            try await play(data)
            try await listenForTurn()
        } catch { throw error }
    }

    private func request(action: String, sessionID: String, text: String?, token: String? = nil) async throws -> Data {
        guard let auth = token ?? Phase1Keychain.readToken() else { throw VoiceError.message("Orbit Voice не активований.") }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(auth)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: String] = [
            "action": action, "session_id": sessionID,
            "channel": "ios_shortcut", "response_mode": "voice", "language": "auto",
        ]
        if let text { body["text"] = text }
        let (data, response) = try await URLSession.shared.upload(for: request, from: JSONEncoder().encode(body))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
            throw VoiceError.message(message ?? "Orbit не відповів.")
        }
        return data
    }

    private func play(_ data: Data) async throws {
        guard !data.isEmpty else { throw VoiceError.message("Orbit повернув порожню відповідь.") }
        state = .speaking
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            do {
                let p = try AVAudioPlayer(data: data)
                player = p
                let delegate = AudioDelegate { [weak self] in
                    self?.player = nil
                    self?.audioDelegate = nil
                    continuation.resume()
                }
                audioDelegate = delegate
                p.delegate = delegate
                if !p.play() { throw VoiceError.message("Не вдалося відтворити відповідь.") }
            } catch { continuation.resume(throwing: error) }
        }
    }

    private func requestPermissions() async throws {
        let mic = await AVAudioApplication.requestRecordPermission()
        guard mic else { throw VoiceError.message("Потрібен доступ до мікрофона.") }
        let speechAuth = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speechAuth == .authorized else { throw VoiceError.message("Потрібен доступ до розпізнавання мовлення.") }
    }

    private func configureAudio() throws {
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP])
        try audio.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func fail(_ error: Error) {
        speech.stop(); player?.stop(); player = nil
        state = .error(error.localizedDescription)
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased().folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: "[^\\p{L}\\p{N}]+", with: " ", options: .regularExpression)
            .split(whereSeparator: { $0 == " " }).joined(separator: " ")
    }

    private static let endPhrases: Set<String> = [
        "кінець", "все", "досить", "закінчити", "закінчити розмову", "дякую все", "дякую", "поки",
        "всё", "хватит", "закончить", "закончить разговор", "спасибо всё",
        "fertig", "das wars", "beenden", "danke das wars", "done", "thats all", "finish",
    ]
}

private final class AudioDelegate: NSObject, AVAudioPlayerDelegate {
    let finished: () -> Void
    init(finished: @escaping () -> Void) { self.finished = finished }
    func audioPlayerDidFinishPlaying(_: AVAudioPlayer, successfully _: Bool) { finished() }
}

enum VoiceError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(value) = self { return value }; return nil }
}
