import SwiftUI

@main
struct OrbitVoiceBackgroundProbeApp: App {
    var body: some Scene {
        WindowGroup { ProbeView() }
    }
}

struct ProbeView: View {
    @StateObject private var recorder = BackgroundProbeRecorder.shared

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: recorder.buffers > 0 ? "mic.fill" : "mic.slash")
                .font(.system(size: 56))
                .foregroundStyle(recorder.buffers > 0 ? .green : .orange)
            Text("Orbit Voice Probe").font(.title.bold())
            Text(recorder.phase).font(.headline)
            Text("Buffers: \(recorder.buffers)").font(.system(.title2, design: .monospaced))
            Text(recorder.detail).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Text("Updated: \(recorder.updatedAt)").font(.caption).foregroundStyle(.secondary)
            Button("Grant microphone permission") { Task { await recorder.requestMicrophonePermission() } }
                .buttonStyle(.borderedProminent)
            Button("Refresh status") { recorder.refresh() }.buttonStyle(.bordered)
            Text("Grant microphone permission here once. Then leave this app, open Maps or Safari, and run the Start Background Microphone Test action through Shortcuts/Siri.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.top, 10)
        }
        .padding(28)
    }
}
