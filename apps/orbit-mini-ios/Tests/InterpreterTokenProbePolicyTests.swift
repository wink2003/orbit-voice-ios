#if DEBUG

import Foundation

@main
struct InterpreterTokenProbePolicyTests {
    static func main() throws {
        let request = try InterpreterTokenProbePolicy.makeRequest(deviceToken: "mock-device-token")
        expect(request.url?.absoluteString == "https://voice.orbit.opik.net/v1/interpreter/session-token")
        expect(request.httpMethod == "POST")
        expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer mock-device-token")
        let body = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: String]
        expect(body?["provider"] == "azure")
        expect(body?["direction"] == "uk-UA-to-de-DE")
        expect(body?["family_id"] == nil && body?["person_id"] == nil)
        expect(InterpreterTokenProbePolicy.sanitizedFailureCode(statusCode: 401) == "http_401")
        expect(InterpreterTokenProbePolicy.sanitizedFailureCode(statusCode: 429) == "http_429")
        expect(InterpreterTokenProbePolicy.sanitizedFailureCode(statusCode: 503) == "http_5xx")
        expect(InterpreterTokenProbePolicy.sanitizedFailureCode(statusCode: 418) == "http_418")
        print("InterpreterTokenProbePolicyTests: PASS")
    }

    private static func expect(_ condition: @autoclosure () -> Bool) {
        precondition(condition(), "Interpreter token probe policy assertion failed")
    }
}

#endif
