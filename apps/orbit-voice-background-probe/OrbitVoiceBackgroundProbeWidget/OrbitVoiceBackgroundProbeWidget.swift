import ActivityKit
import SwiftUI
import WidgetKit

struct OrbitVoiceBackgroundProbeLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ProbeAttributes.self) { context in
            VStack(alignment: .leading, spacing: 6) {
                Text("Orbit Voice Probe").font(.headline)
                Text(context.state.phase)
                Text("Microphone buffers: \(context.state.buffers)").font(.caption.monospaced())
            }
            .padding()
            .activityBackgroundTint(.black.opacity(0.85))
            .activitySystemActionForegroundColor(.mint)
        } dynamicIsland: { _ in
            DynamicIsland { DynamicIslandExpandedRegion(.center) { Text("Orbit Voice Probe") } } compactLeading: { Image(systemName: "mic.fill") } compactTrailing: { Text("ON") } minimal: { Image(systemName: "mic.fill") }
        }
    }
}

@main
struct OrbitVoiceBackgroundProbeWidgetBundle: WidgetBundle {
    var body: some Widget { OrbitVoiceBackgroundProbeLiveActivity() }
}
