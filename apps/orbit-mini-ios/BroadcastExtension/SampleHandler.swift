import ActivityKit
import SwiftUI
import UIKit
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
                OrbitMiniSphere(state: context.state.state, transitionID: context.state.transitionID, size: 40)
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
                    OrbitMiniSphere(state: context.state.state, transitionID: context.state.transitionID, size: 32)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text("ORBIT  ·  \(context.state.state.title)").font(.caption.weight(.semibold))
                }
            } compactLeading: {
                OrbitMiniSphere(state: context.state.state, transitionID: context.state.transitionID, size: 22)
            } compactTrailing: {
                Image(systemName: context.state.state == .speaking ? "speaker.wave.2.fill" : "mic.fill")
            } minimal: {
                OrbitMiniSphere(state: context.state.state, transitionID: context.state.transitionID, size: 18)
            }
        }
    }
}

private struct OrbitMiniSphere: View {
    let state: OrbitMiniVoiceState
    let transitionID: Int
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        image
            .renderingMode(.original)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().stroke(accent.opacity(0.82), lineWidth: state == .thinking ? 1 : 1.5))
            .shadow(color: accent.opacity(state == .thinking ? 0.22 : 0.68), radius: state == .thinking ? 2 : 7)
            .scaleEffect(reduceMotion ? 1 : scale)
            // WidgetKit receives a new ContentState for each real state
            // transition. The transition identifier prevents it treating the
            // new snapshot as structurally identical to the previous one.
            .id("\(state.rawValue)-\(transitionID)")
            .transition(.opacity.combined(with: .scale))
            .contentTransition(.interpolate)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.42), value: transitionID)
    }

    private var image: Image {
        if let url = Bundle.main.url(forResource: "OrbitSphere", withExtension: "jpg"),
           let data = try? Data(contentsOf: url),
           let uiImage = UIImage(data: data) {
            // This is deliberately a decoded UIImage from the WidgetKit
            // extension bundle, not an asset-catalog lookup from the host.
            return Image(uiImage: uiImage)
        }
        // A deliberately obvious fallback: a missing widget resource must not
        // masquerade as Orbit's supplied sphere during physical testing.
        return Image(systemName: "exclamationmark.triangle.fill")
    }

    private var accent: Color {
        switch state {
        case .listening: .cyan
        case .thinking: .orange
        case .speaking: .yellow
        case .ended: .gray
        }
    }

    private var scale: CGFloat {
        switch state {
        case .listening: 1.04
        case .speaking: 1.08
        case .thinking, .ended: 1
        }
    }
}
