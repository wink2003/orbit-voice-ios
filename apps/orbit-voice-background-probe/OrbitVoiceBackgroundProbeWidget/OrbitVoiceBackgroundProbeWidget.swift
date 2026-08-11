import ActivityKit
import SwiftUI
import WidgetKit

struct OrbitVoiceBackgroundProbeLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ProbeAttributes.self) { context in
            OrbitListeningActivityView(state: context.state)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .activityBackgroundTint(Color(red: 0.015, green: 0.035, blue: 0.10))
                .activitySystemActionForegroundColor(.mint)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    OrbitListeningActivityView(state: context.state)
                }
            } compactLeading: {
                Image(systemName: "circle.inset.filled")
                    .foregroundStyle(.mint)
                    .symbolEffect(.pulse, options: .nonRepeating, value: context.state.phase)
            } compactTrailing: {
                Text(context.state.phase == "listening" ? "ON" : "END")
                    .font(.caption2.bold())
                    .foregroundStyle(.mint)
            } minimal: {
                Image(systemName: "circle.inset.filled")
                    .foregroundStyle(.mint)
            }
        }
    }
}

private struct OrbitListeningActivityView: View {
    let state: ProbeAttributes.ContentState

    private var listening: Bool { state.phase == "listening" }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.white.opacity(0.96), .mint.opacity(0.9), .cyan.opacity(0.3)],
                            center: .center,
                            startRadius: 1,
                            endRadius: 20
                        )
                    )
                    .shadow(color: .mint.opacity(listening ? 0.85 : 0.3), radius: listening ? 10 : 4)
                    .frame(width: 30, height: 30)
                Circle()
                    .stroke(.mint.opacity(0.75), lineWidth: 1)
                    .frame(width: 42, height: 24)
                    .rotationEffect(.degrees(-24))
                Circle()
                    .stroke(.cyan.opacity(0.6), lineWidth: 1)
                    .frame(width: 42, height: 24)
                    .rotationEffect(.degrees(34))
            }
            .frame(width: 46, height: 40)
            .scaleEffect(listening ? 1.04 : 0.92)
            .animation(.easeInOut(duration: 0.45), value: state.phase)

            VStack(alignment: .leading, spacing: 2) {
                Text("ORBIT")
                    .font(.caption.bold())
                    .tracking(2)
                    .foregroundStyle(.mint)
                Text(listening ? "Слухаю…" : "Завершено")
                    .font(.headline)
                    .contentTransition(.opacity)
                Text(listening ? "Голосовий режим активний" : "Голосовий режим зупинено")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.66))
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
    }
}

@main
struct OrbitVoiceBackgroundProbeWidgetBundle: WidgetBundle {
    var body: some Widget { OrbitVoiceBackgroundProbeLiveActivity() }
}
