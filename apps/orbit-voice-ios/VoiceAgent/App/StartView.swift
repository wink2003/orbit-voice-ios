import LiveKitComponents
import SwiftUI

/// The initial view that is shown when the app is not connected to the server.
struct StartView: View {
    @EnvironmentObject private var session: Session

    let isConnectingAutomatically: Bool

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Namespace private var button

    @State private var audioOptionsPresented = false

    var body: some View {
        VStack(spacing: 8 * .grid) {
            bars()
            connectButton()
            audioOptionsButton()
        }
        .padding(.horizontal, horizontalSizeClass == .regular ? 32 * .grid : 16 * .grid)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(visionOS)
            .glassBackgroundEffect()
            .frame(maxWidth: 175 * .grid)
        #endif
    }

    private func bars() -> some View {
        HStack(spacing: .grid) {
            let bars = [2, 8, 12, 8, 2].map { $0 * .grid }
            ForEach(0 ..< 5, id: \.self) { index in
                Rectangle()
                    .fill(.fg0)
                    .frame(width: 2 * .grid, height: bars[index])
            }
        }
    }

    @ViewBuilder
    private func connectButton() -> some View {
        if isConnectingAutomatically {
            HStack(spacing: 4 * .grid) {
                Spinner()
                Text("Підключення до Orbit…")
            }
            .frame(width: 58 * .grid, height: 11 * .grid)
            .foregroundStyle(.fgModerate)
        } else {
        AsyncButton {
            await OrbitRuntime.shared.startVoiceSession()
        } label: {
            HStack {
                Spacer()
                Text("Почати розмову")
                    .matchedGeometryEffect(id: "connect", in: button)
                Spacer()
            }
            .frame(width: 58 * .grid, height: 11 * .grid)
        } busyLabel: {
            HStack(spacing: 4 * .grid) {
                Spacer()
                Spinner()
                    .transition(.scale.combined(with: .opacity))
                Text("Підключення…")
                    .matchedGeometryEffect(id: "connect", in: button)
                Spacer()
            }
            .frame(width: 58 * .grid, height: 11 * .grid)
        }
        #if os(visionOS)
        .buttonStyle(.borderedProminent)
        .controlSize(.extraLarge)
        #else
        .buttonStyle(ProminentButtonStyle())
        #endif
        }
    }

    private func audioOptionsButton() -> some View {
        Button {
            audioOptionsPresented = true
        } label: {
            HStack(spacing: .grid) {
                Image(systemName: "slider.horizontal.3")
                Text("Налаштування голосу")
            }
            .font(.system(size: 13))
            .foregroundStyle(.fg3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $audioOptionsPresented) {
            AudioOptionsSheet()
        }
    }
}

#Preview {
    StartView(isConnectingAutomatically: false)
}
