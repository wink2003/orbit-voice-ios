import LiveKit
import SwiftUI
import UIKit

struct AppView: View {
    @EnvironmentObject private var authentication: OrbitAuthentication
    @ObservedObject private var coordinator = OrbitMiniVoiceCoordinator.shared
    @ObservedObject private var session = OrbitMiniVoiceCoordinator.shared.session
    @Environment(\.scenePhase) private var scenePhase
    @State private var settingsShown = false

    var body: some View {
        ZStack {
            Color(red: 0.012, green: 0.03, blue: 0.09).ignoresSafeArea()
            VStack(spacing: 24) {
                header
                Spacer(minLength: 12)
                sphere
                stateLabel
                startStopButton
                if let error = coordinator.lastError {
                    Text(error)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.red.opacity(0.9))
                        .padding(.horizontal, 28)
                }
                Spacer(minLength: 16)
                activeUser
            }
            .padding(24)
        }
        .task {
            await authentication.loadFamilyProfiles()
            await coordinator.cleanOrphansAtLaunch()
        }
        .onChange(of: session.isConnected) { _, connected in
            if !connected { Task { await coordinator.cleanOrphansAtLaunch() } }
        }
        .onChange(of: String(describing: session.agent.agentState)) { _, value in
            Task { await coordinator.updateAgentState(value) }
        }
        .onChange(of: session.messages.count) { _, _ in
            Task { await coordinator.handleLatestUserMessage() }
        }
        .sheet(isPresented: $settingsShown) { OrbitMiniSettingsView() }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("ORBIT")
                    .font(.headline.weight(.bold))
                    .tracking(4)
                    .foregroundStyle(.cyan)
                Text("mini")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            Button { settingsShown = true } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .frame(width: 42, height: 42)
                    .background(.white.opacity(0.1), in: Circle())
            }
            .accessibilityLabel("Налаштування Orbit Mini")
        }
        .foregroundStyle(.white)
    }

    private var voiceState: OrbitMiniVoiceState? {
        guard coordinator.isVoiceActive else { return nil }
        let value = String(describing: session.agent.agentState).lowercased()
        if value.contains("speak") { return .speaking }
        if value.contains("think") { return .thinking }
        return .listening
    }

    private var sphere: some View {
        orbitSphereImage
            .resizable()
            .scaledToFit()
            .frame(maxWidth: 310)
            .clipShape(RoundedRectangle(cornerRadius: 58, style: .continuous))
            .shadow(color: glowColor.opacity(0.5), radius: 30)
            .scaleEffect(voiceState == .speaking ? 1.04 : 1)
            .animation(.easeInOut(duration: 0.35), value: voiceState)
            .accessibilityHidden(true)
    }

    private var orbitSphereImage: Image {
        if let url = Bundle.main.url(forResource: "OrbitSphere", withExtension: "jpg"),
           let image = UIImage(contentsOfFile: url.path) {
            return Image(uiImage: image)
        }
        return Image("OrbitSphere")
    }

    private var glowColor: Color {
        switch voiceState {
        case .listening: .cyan
        case .thinking: .orange
        case .speaking: .yellow
        case nil, .ended: .clear
        }
    }

    private var stateLabel: some View {
        VStack(spacing: 6) {
            Text(voiceState?.title ?? (coordinator.isStarting ? "Підключаюсь…" : "Готовий"))
                .font(.title2.weight(.semibold))
            Text(voiceState == nil ? "Натисніть, щоб почати розмову" : "Скажіть «кінець», щоб завершити")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.68))
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(.white)
    }

    private var startStopButton: some View {
        Button {
            Task {
                if coordinator.isVoiceActive { await coordinator.stop(reason: "button") }
                else { await coordinator.start() }
            }
        } label: {
            Label(
                coordinator.isVoiceActive ? "Завершити" : "Почати розмову",
                systemImage: coordinator.isVoiceActive ? "stop.fill" : "waveform.circle.fill"
            )
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(coordinator.isVoiceActive ? Color.red.opacity(0.84) : Color.cyan.opacity(0.82), in: Capsule())
        }
        .disabled(coordinator.isStarting)
        .foregroundStyle(.black)
        .accessibilityHint(coordinator.isVoiceActive ? "Зупиняє голосову сесію" : "Запускає голосову сесію")
    }

    private var activeUser: some View {
        Menu {
            ForEach(authentication.familyProfiles) { profile in
                Button(profile.displayName) {
                    Task { try? await authentication.selectProfile(profile) }
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.fill")
                VStack(alignment: .leading, spacing: 1) {
                    Text("Говорить")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                    Text(authentication.displayName ?? "Orbit")
                        .font(.subheadline.weight(.semibold))
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
            }
            .padding(13)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        }
        .foregroundStyle(.white)
        .disabled(coordinator.session.isConnected)
    }
}
