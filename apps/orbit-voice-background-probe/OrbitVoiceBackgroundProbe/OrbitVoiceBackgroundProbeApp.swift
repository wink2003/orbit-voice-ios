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
            Text("Foreground: \(recorder.foregroundBuffers)   Background: \(recorder.backgroundBuffers)")
                .font(.system(.body, design: .monospaced))
            Text("Audio session: \(recorder.audioSessionActive ? "active" : "inactive")")
                .foregroundStyle(recorder.audioSessionActive ? .green : .secondary)
            Text(recorder.detail).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Text("Updated: \(recorder.updatedAt)").font(.caption).foregroundStyle(.secondary)
            if !recorder.diagnostics.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Diagnostics").font(.headline)
                    ForEach(recorder.diagnostics.suffix(6), id: \.self) { entry in
                        Text(entry).font(.caption2.monospaced()).textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button("Grant microphone permission") { Task { await recorder.requestMicrophonePermission() } }
                .buttonStyle(.borderedProminent)
            Button("Start Foreground → Background Test") {
                Task {
                    do { try await recorder.startForegroundBackgroundTest() }
                    catch { recorder.showError(error.localizedDescription) }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(recorder.audioSessionActive)
            Button("Stop Recording") { Task { await recorder.stop(reason: "Stopped from foreground UI") } }
                .buttonStyle(.bordered)
            Button("Refresh status") { recorder.refresh() }.buttonStyle(.bordered)
            Text("Start while this screen is visible, then manually open Safari or Maps. Return here and compare the foreground/background counters.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.top, 10)
        }
        .padding(28)
    }
}
