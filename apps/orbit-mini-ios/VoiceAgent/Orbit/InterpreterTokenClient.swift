import Foundation

enum InterpreterTokenClientError: LocalizedError {
    case notPaired
    case rejected(Int)
    case invalidResponse(InterpreterTokenDiagnostic)
    case network

    var errorDescription: String? {
        switch self {
        case .notPaired: return "Спершу активуйте цей iPhone."
        case let .rejected(status): return "Сервер відхилив запит (\(status))."
        case let .invalidResponse(diagnostic): return "Сервер повернув некоректні дані. [\(diagnostic.rawValue)]"
        case .network: return "Не вдалося підключитися до сервера."
        }
    }
}

/// Stable, privacy-safe categories for diagnosing the broker contract. These
/// values intentionally contain no received data or provider response text.
enum InterpreterTokenDiagnostic: Equatable, Sendable {
    case transportNonHTTP, decodeJSON
    case decodeMissingField(String), decodeNullField(String), decodeTypeMismatch(String)
    case decodeExpiresAt, decodeEndpoint, decodeUnknown
    case metadataProvider, metadataSourceLanguage, metadataTargetLanguage, metadataRegion, metadataAuthScheme
    case tokenEmpty

    var rawValue: String {
        switch self {
        case .transportNonHTTP: return "transport_non_http"
        case .decodeJSON: return "decode_json"
        case let .decodeMissingField(field): return "decode_missing_\(Self.safeField(field))"
        case let .decodeNullField(field): return "decode_null_\(Self.safeField(field))"
        case let .decodeTypeMismatch(field): return "decode_type_\(Self.safeField(field))"
        case .decodeExpiresAt: return "decode_expiresAt"
        case .decodeEndpoint: return "decode_endpoint"
        case .decodeUnknown: return "decode_unknown"
        case .metadataProvider: return "metadata_provider"
        case .metadataSourceLanguage: return "metadata_sourceLanguage"
        case .metadataTargetLanguage: return "metadata_targetLanguage"
        case .metadataRegion: return "metadata_region"
        case .metadataAuthScheme: return "metadata_authScheme"
        case .tokenEmpty: return "token_empty"
        }
    }

    private static func safeField(_ field: String) -> String {
        ["provider", "token", "expiresAt", "sourceLanguage", "targetLanguage", "region", "endpoint", "authScheme"].contains(field) ? field : "unknown_field"
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
        guard let http = response as? HTTPURLResponse else {
            throw InterpreterTokenClientError.invalidResponse(.transportNonHTTP)
        }
        guard (200..<300).contains(http.statusCode) else { throw InterpreterTokenClientError.rejected(http.statusCode) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let credential: InterpreterCredential
        do {
            credential = try decoder.decode(InterpreterCredential.self, from: data)
        } catch let error as DecodingError {
            throw InterpreterTokenClientError.invalidResponse(Self.diagnostic(for: error))
        } catch {
            throw InterpreterTokenClientError.invalidResponse(.decodeUnknown)
        }
        guard credential.provider == "azure" else {
            throw InterpreterTokenClientError.invalidResponse(.metadataProvider)
        }
        guard credential.sourceLanguage == direction.sourceLanguage else {
            throw InterpreterTokenClientError.invalidResponse(.metadataSourceLanguage)
        }
        guard credential.targetLanguage == direction.targetLanguage else {
            throw InterpreterTokenClientError.invalidResponse(.metadataTargetLanguage)
        }
        guard credential.region == "germanywestcentral" else {
            throw InterpreterTokenClientError.invalidResponse(.metadataRegion)
        }
        guard credential.authScheme == "azure-speech-bearer" else {
            throw InterpreterTokenClientError.invalidResponse(.metadataAuthScheme)
        }
        guard !credential.token.isEmpty else {
            throw InterpreterTokenClientError.invalidResponse(.tokenEmpty)
        }
        return credential
    }

    static func diagnostic(for error: DecodingError) -> InterpreterTokenDiagnostic {
        let field: String?
        let path: [CodingKey]
        switch error {
        case let .keyNotFound(key, context): field = key.stringValue; path = context.codingPath
        case let .valueNotFound(_, context): field = context.codingPath.last?.stringValue; path = context.codingPath
        case let .typeMismatch(_, context): field = context.codingPath.last?.stringValue; path = context.codingPath
        case let .dataCorrupted(context): field = context.codingPath.last?.stringValue; path = context.codingPath
        @unknown default: return .decodeUnknown
        }
        guard let field else { return path.isEmpty ? .decodeJSON : .decodeUnknown }
        switch field {
        case "expiresAt":
            switch error {
            case .keyNotFound: return .decodeMissingField(field)
            case .valueNotFound: return .decodeNullField(field)
            case .typeMismatch: return .decodeTypeMismatch(field)
            case .dataCorrupted: return .decodeExpiresAt
            @unknown default: return .decodeUnknown
            }
        case "endpoint":
            switch error {
            case .keyNotFound: return .decodeMissingField(field)
            case .valueNotFound: return .decodeNullField(field)
            default: return .decodeEndpoint
            }
        case "provider", "token", "sourceLanguage", "targetLanguage", "region", "authScheme":
            switch error {
            case .keyNotFound: return .decodeMissingField(field)
            case .valueNotFound: return .decodeNullField(field)
            case .typeMismatch: return .decodeTypeMismatch(field)
            case .dataCorrupted: return field == "expiresAt" ? .decodeExpiresAt : .decodeJSON
            @unknown default: return .decodeUnknown
            }
        default: return .decodeUnknown
        }
    }
}
