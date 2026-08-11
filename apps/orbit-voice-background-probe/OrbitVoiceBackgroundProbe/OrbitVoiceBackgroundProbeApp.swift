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
    @State private var installedExtensionAudit = InstalledExtensionAudit.capture()

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: recorder.buffers > 0 ? "mic.fill" : "mic.slash")
                .font(.system(size: 56))
                .frame(maxWidth: .infinity)
                .foregroundStyle(recorder.buffers > 0 ? .green : .orange)
            Text("Orbit Voice Probe").font(.title.bold()).frame(maxWidth: .infinity, alignment: .center)
            Text(recorder.phase).font(.headline).frame(maxWidth: .infinity, alignment: .center)
            Text("Buffers: \(recorder.buffers)").font(.system(.title2, design: .monospaced)).frame(maxWidth: .infinity, alignment: .center)
            Text("Foreground: \(recorder.foregroundBuffers)   Background: \(recorder.backgroundBuffers)")
                .font(.system(.body, design: .monospaced))
            Text("Audio session: \(recorder.audioSessionActive ? "active" : "inactive")")
                .foregroundStyle(recorder.audioSessionActive ? .green : .secondary)
            Text(recorder.detail).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Text("Updated: \(recorder.updatedAt)").font(.caption).foregroundStyle(.secondary)
            GroupBox("LIVE ACTIVITY STATUS") {
                VStack(alignment: .leading, spacing: 7) {
                    statusRow("Authorized", recorder.liveActivitiesEnabled ? "enabled" : "disabled")
                    statusRow("Activities", "\(recorder.liveActivityCount)")
                    statusRow("Current ID", recorder.currentActivityID ?? "none")
                    statusRow("State", recorder.currentActivityState)
                    statusRow("Request", recorder.lastActivityRequestResult)
                    statusRow("Listening update", recorder.lastListeningUpdateResult)
                    statusRow("Alert update", recorder.lastAlertUpdateResult)
                    statusRow("ActivityKit error", recorder.lastActivityKitError ?? "none")
                }
            }
            GroupBox("INSTALLED EXTENSIONS") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Runtime package audit").font(.caption.bold())
                        Spacer()
                        Button("Refresh", systemImage: "arrow.clockwise") {
                            installedExtensionAudit = InstalledExtensionAudit.capture()
                        }
                    }
                    Button("Copy Installed Extension Diagnostics", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = installedExtensionAudit.report
                    }
                    .buttonStyle(.bordered)
                    Text(installedExtensionAudit.report)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            if recorder.destructionErrorDetails != nil {
                Text("Historical scene test: UISceneErrorDomain code 0 — multiple scenes are unsupported on this device.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Diagnostics").font(.headline)
                    Spacer()
                    Button("Copy Diagnostics", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = recorder.diagnosticsText
                    }
                    Button("Clear Diagnostics", systemImage: "trash") { recorder.clearDiagnostics() }
                }
                if recorder.diagnosticsText.isEmpty {
                    Text("No stored diagnostic messages.").foregroundStyle(.secondary)
                } else {
                    Text(recorder.diagnosticsText)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
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
        .padding(20)
        }
        .background(ProbeWindowCapture { window in
            recorder.captureVisibleProbeWindow(window)
        })
        .onAppear {
            installedExtensionAudit = InstalledExtensionAudit.capture()
        }
    }

    private func statusRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label).font(.caption.bold())
            Spacer(minLength: 8)
            Text(value).font(.system(.caption, design: .monospaced))
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
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
