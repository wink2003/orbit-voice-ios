#if os(iOS) && ORBIT_CALLKIT_ONLY
import SwiftUI

struct OrbitCallKitView: View {
    @ObservedObject private var callManager = OrbitNativeCallManager.shared

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                Image(systemName: stateIcon)
                    .font(.system(size: 68, weight: .medium))
                    .foregroundStyle(stateColor)
                    .symbolEffect(.pulse, isActive: callManager.state == .starting)

                Text(stateTitle)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                if case let .failed(message) = callManager.state {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                        .padding(.horizontal)
                }

                actionButton
                    .frame(maxWidth: 360)
            }
            .padding(28)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch callManager.state {
        case .idle, .failed:
            Button {
                callManager.dismissError()
                Task {
                    do {
                        try await callManager.startCall()
                    } catch {
                        // The manager publishes the complete error on this screen.
                    }
                }
            } label: {
                Label("START ORBIT", systemImage: "phone.fill")
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
            }
            .buttonStyle(.borderedProminent)

        case .starting:
            Button {} label: {
                HStack {
                    ProgressView()
                    Text("CONNECTING…")
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
            }
            .buttonStyle(.borderedProminent)
            .disabled(true)

        case .connected, .ending:
            Button(role: .destructive) {
                Task { await callManager.endCall() }
            } label: {
                Label(
                    callManager.state == .ending ? "ENDING…" : "END ORBIT",
                    systemImage: "phone.down.fill"
                )
                .frame(maxWidth: .infinity)
                .frame(height: 54)
            }
            .buttonStyle(.borderedProminent)
            .disabled(callManager.state == .ending)
        }
    }

    private var stateTitle: String {
        switch callManager.state {
        case .idle:
            "Orbit is ready"
        case .starting:
            "Connecting to Orbit"
        case .connected:
            "Orbit is listening"
        case .ending:
            "Ending the call"
        case .failed:
            "Orbit could not start"
        }
    }

    private var stateIcon: String {
        switch callManager.state {
        case .idle:
            "waveform.circle"
        case .starting:
            "phone.arrow.up.right"
        case .connected:
            "waveform.circle.fill"
        case .ending:
            "phone.down.circle"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }

    private var stateColor: Color {
        switch callManager.state {
        case .connected:
            .green
        case .failed:
            .red
        case .ending:
            .orange
        default:
            .accentColor
        }
    }
}
#endif
