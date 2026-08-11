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
                OrbitMiniSphere(state: context.state.state, size: 40)
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
                    OrbitMiniSphere(state: context.state.state, size: 32)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text("ORBIT  ·  \(context.state.state.title)").font(.caption.weight(.semibold))
                }
            } compactLeading: {
                OrbitMiniSphere(state: context.state.state, size: 22)
            } compactTrailing: {
                Image(systemName: context.state.state == .speaking ? "speaker.wave.2.fill" : "mic.fill")
            } minimal: {
                OrbitMiniSphere(state: context.state.state, size: 18)
            }
        }
    }
}

private struct OrbitMiniSphere: View {
    let state: OrbitMiniVoiceState
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        image
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().stroke(accent.opacity(0.82), lineWidth: state == .thinking ? 1 : 1.5))
            .shadow(color: accent.opacity(state == .thinking ? 0.22 : 0.68), radius: state == .thinking ? 2 : 7)
            .scaleEffect(reduceMotion ? 1 : scale)
            .id(state.rawValue)
            .transition(.opacity.combined(with: .scale))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.32), value: state)
    }

    private var image: Image {
        if let url = Bundle.main.url(forResource: "OrbitSphere", withExtension: "jpg"),
           let uiImage = UIImage(contentsOfFile: url.path) {
            return Image(uiImage: uiImage)
        }
        return Image("OrbitSphere")
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
