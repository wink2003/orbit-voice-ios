import SwiftUI
import UIKit

@main
struct OrbitVoiceBackgroundProbeApp: App {
    @UIApplicationDelegateAdaptor(ProbeApplicationDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup { ProbeView() }
    }
}

final class ProbeApplicationDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        Task { @MainActor in
            BackgroundProbeRecorder.shared.discardedSceneSessions(sceneSessions)
        }
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
            if let error = recorder.destructionErrorDetails {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Full scene-destruction error").font(.headline).foregroundStyle(.red)
                    Text(error).font(.caption.monospaced()).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
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
        .background(ProbeWindowCapture { window in
            recorder.captureVisibleProbeWindow(window)
        })
    }
}

private struct ProbeWindowCapture: UIViewControllerRepresentable {
    let capture: (UIWindow?) -> Void

    func makeUIViewController(context: Context) -> ProbeWindowCaptureController {
        ProbeWindowCaptureController(capture: capture)
    }

    func updateUIViewController(_ controller: ProbeWindowCaptureController, context: Context) {
        controller.capture = capture
        controller.reportWindow()
    }
}

private final class ProbeWindowCaptureController: UIViewController {
    var capture: (UIWindow?) -> Void

    init(capture: @escaping (UIWindow?) -> Void) {
        self.capture = capture
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        reportWindow()
    }

    func reportWindow() {
        DispatchQueue.main.async { [weak self] in
            self?.capture(self?.view.window)
        }
    }
}
