import Foundation

enum InterpreterTokenClientError: LocalizedError {
    case notPaired
    case rejected(Int)
    case invalidResponse
    case network

    var errorDescription: String? {
        switch self {
        case .notPaired: return "Спершу активуйте цей iPhone."
        case let .rejected(status): return "Сервер відхилив запит (\(status))."
        case .invalidResponse: return "Сервер повернув некоректні дані."
        case .network: return "Не вдалося підключитися до сервера."
        }
    }
}
struct InterpreterTokenClient {
    private let endpoint = URL(string: "https://voice.orbit.opik.net/v1/interpreter/session-token")!

    func requestCredential(for direction: InterpreterDirection) async throws -> InterpreterCredential {
        guard let deviceToken = KeychainStore.readDeviceToken(), !deviceToken.isEmpty else {
            throw InterpreterTokenClientError.notPaired
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(["provider": "azure", "direction": direction.rawValue])
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch { throw InterpreterTokenClientError.network }
        guard let http = response as? HTTPURLResponse else { throw InterpreterTokenClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw InterpreterTokenClientError.rejected(http.statusCode) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let credential = try? decoder.decode(InterpreterCredential.self, from: data),
              credential.provider == "azure",
              credential.sourceLanguage == direction.sourceLanguage,
              credential.targetLanguage == direction.targetLanguage,
              credential.region == "germanywestcentral",
              credential.authScheme == "azure-speech-bearer",
              !credential.token.isEmpty else { throw InterpreterTokenClientError.invalidResponse }
        return credential
    }
}
