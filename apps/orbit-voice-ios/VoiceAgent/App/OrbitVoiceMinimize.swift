import LiveKit
import SwiftUI

/// Presentation state of the voice conversation window (issue #374). The call itself lives in `OrbitRuntime`/`Session`; this only says whether the
/// full window is shown. Collapsing the window never ends the call: the mini bar keeps mic / expand / end within reach while the user uses Main Orbit.
@MainActor
final class OrbitVoicePresence: ObservableObject {
    static let shared = OrbitVoicePresence()
    @Published var isExpanded = false
}

/// Compact call bar shown above the dock while a call is connected and the full window is collapsed.
struct OrbitVoiceMiniBar: View {
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var localMedia: LocalMedia
    @ObservedObject private var presence = OrbitVoicePresence.shared

    var body: some View {
        if session.isConnected && !presence.isExpanded {
            HStack(spacing: 12) {
                Image(systemName: localMedia.isMicrophoneEnabled ? "waveform" : "mic.slash.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.indigo))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Розмова з Orbit").font(.subheadline.weight(.semibold))
                    Text(localMedia.isMicrophoneEnabled ? "Триває · можна користуватись застосунком" : "Мікрофон вимкнено").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Button { Task { await localMedia.toggleMicrophone() } } label: {
                    Image(systemName: localMedia.isMicrophoneEnabled ? "mic.fill" : "mic.slash.fill").frame(minWidth: 36, minHeight: 36)
                }
                .accessibilityLabel(localMedia.isMicrophoneEnabled ? "Вимкнути мікрофон" : "Увімкнути мікрофон")
                Button { presence.isExpanded = true } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").frame(minWidth: 36, minHeight: 36)
                }
                .accessibilityLabel("Розгорнути розмову")
                Button(role: .destructive) { Task { await OrbitRuntime.shared.endVoiceSession() } } label: {
                    Image(systemName: "phone.down.fill").frame(minWidth: 36, minHeight: 36)
                }
                .accessibilityLabel("Завершити розмову")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.indigo.opacity(0.35), lineWidth: 1))
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
