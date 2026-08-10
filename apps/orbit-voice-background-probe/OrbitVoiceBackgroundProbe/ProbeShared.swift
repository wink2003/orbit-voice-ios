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

    static func write(phase: String, buffers: Int, detail: String) {
        UserDefaults.standard.set([
            "phase": phase,
            "buffers": buffers,
            "detail": detail,
            "updatedAt": ISO8601DateFormatter().string(from: Date()),
        ], forKey: key)
    }

    static func read() -> (phase: String, buffers: Int, detail: String, updatedAt: String) {
        let value = UserDefaults.standard.dictionary(forKey: key) ?? [:]
        return (
            value["phase"] as? String ?? "Never run",
            value["buffers"] as? Int ?? 0,
            value["detail"] as? String ?? "Open the app once, grant microphone access, then run the Shortcut from another app.",
            value["updatedAt"] as? String ?? "—"
        )
    }
}
