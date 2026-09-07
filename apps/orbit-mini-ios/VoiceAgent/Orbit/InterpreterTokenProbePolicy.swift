#if DEBUG

import Foundation

enum InterpreterTokenProbePolicy {
    static let endpoint = URL(string: "https://voice.orbit.opik.net/v1/interpreter/session-token")!
    static let provider = "azure"
    static let direction = "uk-UA-to-de-DE"

    private struct RequestBody: Encodable {
        let provider: String
        let direction: String
    }

    static func makeRequest(deviceToken: String) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(RequestBody(provider: provider, direction: direction))
        return request
    }

    static func sanitizedFailureCode(statusCode: Int) -> String {
        switch statusCode {
        case 401: return "http_401"
        case 429: return "http_429"
        case 500 ..< 600: return "http_5xx"
        default: return "http_\(statusCode)"
        }
    }
}

#endif
