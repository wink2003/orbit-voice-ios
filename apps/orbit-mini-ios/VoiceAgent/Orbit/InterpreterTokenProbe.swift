#if DEBUG

import Combine
import Foundation

/// A deliberately narrow DEBUG-only probe for the already-deployed Azure token
/// broker. It does not start audio, LiveKit, or any Interpreter session.
@MainActor
final class InterpreterTokenProbe: ObservableObject {
    struct Success: Equatable {
        let provider: String
        let direction: String
        let region: String
        let endpoint: String
        let expiresAt: String
        let tokenPresent: Bool
    }

    enum Outcome: Equatable {
        case idle
        case running
        case success(Success)
        case failure(code: String)
    }

    @Published private(set) var outcome: Outcome = .idle

    private struct ResponseBody: Decodable {
        let provider: String
        let token: String
        let expiresAt: String
        let sourceLanguage: String
        let targetLanguage: String
        let region: String
        let endpoint: String
        let authScheme: String
    }

    func run() async {
        guard outcome != .running else { return }
        guard let deviceToken = KeychainStore.readDeviceToken(), !deviceToken.isEmpty else {
            outcome = .failure(code: "not_paired")
            return
        }

        outcome = .running
        do {
            let request = try InterpreterTokenProbePolicy.makeRequest(deviceToken: deviceToken)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                outcome = .failure(code: "no_http_response")
                return
            }
            guard (200 ..< 300).contains(http.statusCode) else {
                outcome = .failure(code: InterpreterTokenProbePolicy.sanitizedFailureCode(statusCode: http.statusCode))
                return
            }

            // Keep the short-lived token only in this local decoded value. It is
            // never interpolated, displayed, persisted, copied, or exported.
            let result = try JSONDecoder().decode(ResponseBody.self, from: data)
            guard !result.token.isEmpty, !result.expiresAt.isEmpty else {
                outcome = .failure(code: "invalid_response")
                return
            }
            guard result.provider == InterpreterTokenProbePolicy.provider,
                  result.sourceLanguage == "uk-UA",
                  result.targetLanguage == "de-DE",
                  result.region == "germanywestcentral",
                  result.authScheme == "azure-speech-bearer"
            else {
                outcome = .failure(code: "unexpected_metadata")
                return
            }

            outcome = .success(Success(
                provider: result.provider,
                direction: InterpreterTokenProbePolicy.direction,
                region: result.region,
                endpoint: result.endpoint,
                expiresAt: result.expiresAt,
                tokenPresent: true
            ))
        } catch is EncodingError {
            outcome = .failure(code: "invalid_response")
        } catch {
            // Do not expose transport/provider response bodies in the UI.
            outcome = .failure(code: "network_error")
        }
    }

}

#endif
