import ActivityKit
import Foundation

struct ProbeAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var phase: String
        var buffers: Int
        var detail: String
    }

    var startedAt: Date
}

enum ProbeStatusStore {
    private static let key = "orbit.voice.backgroundProbe.status"

    static func write(phase: String, buffers: Int, detail: String, foregroundBuffers: Int = 0, backgroundBuffers: Int = 0, diagnostics: [String] = []) {
        UserDefaults.standard.set([
            "phase": phase,
            "buffers": buffers,
            "foregroundBuffers": foregroundBuffers,
            "backgroundBuffers": backgroundBuffers,
            "detail": detail,
            "diagnostics": diagnostics,
            "updatedAt": ISO8601DateFormatter().string(from: Date()),
        ], forKey: key)
    }

    static func read() -> (phase: String, buffers: Int, foregroundBuffers: Int, backgroundBuffers: Int, detail: String, diagnostics: [String], updatedAt: String) {
        let value = UserDefaults.standard.dictionary(forKey: key) ?? [:]
        return (
            value["phase"] as? String ?? "Never run",
            value["buffers"] as? Int ?? 0,
            value["foregroundBuffers"] as? Int ?? 0,
            value["backgroundBuffers"] as? Int ?? 0,
            value["detail"] as? String ?? "Open the app once, grant microphone access, then run the Shortcut from another app.",
            value["diagnostics"] as? [String] ?? [],
            value["updatedAt"] as? String ?? "—"
        )
    }
}
