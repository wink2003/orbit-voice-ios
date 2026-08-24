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
        ZStack {
            Circle().fill(miniAccent.opacity(0.10)).frame(width: 278, height: 278)
            Circle().stroke(miniAccent.opacity(0.26), lineWidth: 1).frame(width: 232, height: 232)
                .rotationEffect(.degrees(voiceState == .listening || voiceState == .speaking ? 16 : 0))
            Circle()
                .trim(from: 0.12, to: voiceState == .speaking ? 0.88 : 0.68)
                .stroke(Color.mint.opacity(0.32), lineWidth: 7)
                .frame(width: 202, height: 202)
                .rotationEffect(.degrees(-90))
            Circle()
                .fill(LinearGradient(colors: [Color.teal, Color.cyan.opacity(0.85), Color.indigo.opacity(0.88)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 164, height: 164)
                .shadow(color: miniAccent.opacity(0.52), radius: 30)
                .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1))
                .scaleEffect(voiceState == .speaking ? 1.07 : voiceState == .listening ? 1.03 : 1)
            Image(systemName: voiceState == .speaking ? "speaker.wave.2.fill" : "waveform")
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(.white)
        }
            .frame(height: 286)
            .animation(.easeInOut(duration: 0.35), value: voiceState)
            .accessibilityHidden(true)
    }

    // Mini deliberately uses its existing deep-navy / teal companion palette;
    // Main retains the indigo Orbit palette. The icons remain untouched.
    private var miniAccent: Color {
        switch voiceState {
        case .listening: .teal
        case .thinking: .mint
        case .speaking: .cyan
        case nil, .ended: .teal
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
            switch authentication.familyProfilesLoadState {
            case .loaded:
                ForEach(authentication.familyProfiles) { profile in
                    Button(profile.displayName) {
                        Task { try? await authentication.selectProfile(profile) }
                    }
                }
            case .loading, .idle:
                Text("Завантаження профілів…")
            case .empty:
                Text("Сімейні профілі відсутні")
            case .unavailable:
                Button("Спробувати ще раз") {
                    Task { await authentication.loadFamilyProfiles() }
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.fill")
                VStack(alignment: .leading, spacing: 1) {
                    Text("Говорить")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                    Text(profileLabel)
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
        .disabled(coordinator.session.isConnected || authentication.familyProfilesLoadState == .loading)
    }

    private var profileLabel: String {
        if let profile = authentication.selectedFamilyProfile {
            return profile.displayName
        }
        switch authentication.familyProfilesLoadState {
        case .idle, .loading:
            return "Завантаження профілю…"
        case .empty:
            return "Профілі відсутні"
        case .unavailable:
            return "Профіль недоступний"
        case .loaded:
            return "Виберіть профіль"
        }
    }
}
