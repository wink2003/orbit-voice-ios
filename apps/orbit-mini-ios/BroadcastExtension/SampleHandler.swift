import ActivityKit
import SwiftUI
import WidgetKit

@main
struct OrbitMiniWidgetBundle: WidgetBundle {
    var body: some Widget {
        OrbitMiniLiveActivity()
    }
}

struct OrbitMiniLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: OrbitMiniActivityAttributes.self) { context in
            HStack(spacing: 10) {
                Image("OrbitSphere")
                    .resizable().scaledToFill().frame(width: 38, height: 38).clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("ORBIT").font(.caption.weight(.bold))
                    Text(context.state.state.title).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Text(context.state.userName).font(.caption2).lineLimit(1)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .activityBackgroundTint(Color(red: 0.02, green: 0.07, blue: 0.17))
            .activitySystemActionForegroundColor(.cyan)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image("OrbitSphere").resizable().scaledToFit().frame(width: 32, height: 32).clipShape(Circle())
                }
                DynamicIslandExpandedRegion(.center) {
                    Text("ORBIT  ·  \(context.state.state.title)").font(.caption.weight(.semibold))
                }
            } compactLeading: {
                Image("OrbitSphere").resizable().scaledToFit().clipShape(Circle())
            } compactTrailing: {
                Image(systemName: context.state.state == .speaking ? "speaker.wave.2.fill" : "mic.fill")
            } minimal: {
                Image("OrbitSphere").resizable().scaledToFit().clipShape(Circle())
            }
        }
    }
}
