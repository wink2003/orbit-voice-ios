import ActivityKit
import SwiftUI
import WidgetKit

struct OrbitVoiceBackgroundProbeLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ProbeAttributes.self) { context in
            OrbitListeningActivityView(state: context.state)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 0.01, green: 0.025, blue: 0.08))
                .activityBackgroundTint(Color(red: 0.01, green: 0.025, blue: 0.08))
                .activitySystemActionForegroundColor(.cyan)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    OrbitListeningActivityView(state: context.state)
                }
            } compactLeading: {
                Image(systemName: "circle.inset.filled")
                    .foregroundStyle(.cyan)
                    .symbolEffect(.pulse, options: .nonRepeating, value: context.state.phase)
            } compactTrailing: {
                Text(context.state.phase == "listening" ? "ON" : "END")
                    .font(.caption2.bold())
                    .foregroundStyle(.cyan)
            } minimal: {
                Image(systemName: "circle.inset.filled")
                    .foregroundStyle(.cyan)
            }
        }
    }
}

private struct OrbitListeningActivityView: View {
    let state: ProbeAttributes.ContentState

    private var listening: Bool { state.phase == "listening" }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(.cyan)
                    .overlay(Circle().stroke(.white.opacity(0.92), lineWidth: 2))
                    .shadow(color: .cyan.opacity(listening ? 0.95 : 0.35), radius: listening ? 12 : 4)
                    .frame(width: 34, height: 34)
                Circle()
                    .stroke(.cyan.opacity(0.9), lineWidth: 1.4)
                    .frame(width: 48, height: 27)
                    .rotationEffect(.degrees(-24))
                Circle()
                    .stroke(.white.opacity(0.75), lineWidth: 1.2)
                    .frame(width: 48, height: 27)
                    .rotationEffect(.degrees(34))
            }
            .frame(width: 52, height: 44)
            .scaleEffect(listening ? 1.04 : 0.92)
            .animation(.easeInOut(duration: 0.45), value: state.phase)

            VStack(alignment: .leading, spacing: 3) {
                Text("ORBIT")
                    .font(.caption.bold())
                    .tracking(2.5)
                    .foregroundStyle(.cyan)
                Text(listening ? "Слухаю…" : "Завершено")
                    .font(.title3.bold())
                    .contentTransition(.opacity)
                Text(listening ? "Голосовий режим активний" : "Голосовий режим зупинено")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(listening ? "Orbit. Слухаю." : "Orbit. Завершено.")
    }
}

@main
struct OrbitVoiceBackgroundProbeWidgetBundle: WidgetBundle {
    var body: some Widget {
        OrbitVoiceBackgroundProbeLiveActivity()
    }
}
