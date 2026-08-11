import ActivityKit
import Foundation

// This exact file belongs to both the Orbit Mini app target and its WidgetKit
// extension target. Keeping one source definition prevents an accidental drift
// between Activity.request and ActivityConfiguration.
enum OrbitMiniVoiceState: String, Codable, Hashable {
    case listening, thinking, speaking, ended

    var title: String {
        switch self {
        case .listening: "Слухаю…"
        case .thinking: "Думаю…"
        case .speaking: "Відповідаю…"
        case .ended: "Розмову завершено"
        }
    }
}

struct OrbitMiniActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var state: OrbitMiniVoiceState
        var userName: String
        /// Changes only for a real voice-state transition, giving WidgetKit a
        /// distinct identity for its short, update-driven transition.
        var transitionID: Int
    }

    var startedAt: Date
}
