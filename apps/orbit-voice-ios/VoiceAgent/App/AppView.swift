import LiveKit
import SwiftUI

struct AppView: View {
    @Namespace private var namespace
    @AppStorage("orbit.appearance") private var appearance = "system"
    // A fresh launch opens Voice, while normal in-app navigation retains the
    // person's selected tab. Selecting a tab does not start a Voice session.
    @State private var selectedTab = "voice"

    var body: some View {
        TabView(selection: $selectedTab) {
            OrbitChatsView()
                .tabItem { Label("Чат", systemImage: "message") }
                .tag("chat")
            MainVoiceHomeView()
                .tabItem { Label("Голос", systemImage: "waveform") }
                .tag("voice")
            OrbitCalendarView()
                .tabItem { Label("Календар", systemImage: "calendar") }
                .tag("calendar")
            OrbitSettingsView()
                .tabItem { Label("Налаштування", systemImage: "gearshape") }
                .tag("settings")
        }
        .environment(\.namespace, namespace)
        .preferredColorScheme(preferredColorScheme)
    }

    private var preferredColorScheme: ColorScheme? {
        switch appearance {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

}

private struct MainVoiceHomeView: View {
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var localMedia: LocalMedia
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isStarting = false

    private enum VoiceState: Equatable {
        case idle, connecting, listening, processing, speaking, muted, error

        var title: String {
            switch self {
            case .idle: "Готовий до розмови"
            case .connecting: "Підключаюсь…"
            case .listening: "Слухаю"
            case .processing: "Думаю…"
            case .speaking: "Orbit відповідає"
            case .muted: "Мікрофон вимкнено"
            case .error: "Потрібна увага"
            }
        }

        var detail: String {
            switch self {
            case .idle: "Натисніть, щоб почати голосову розмову"
            case .connecting: "Готую безпечне з’єднання"
            case .listening: "Говоріть природно українською"
            case .processing: "Мить — обробляю відповідь"
            case .speaking: "Скажіть «кінець», щоб завершити"
            case .muted: "Увімкніть мікрофон, коли будете готові"
            case .error: "Перевірте повідомлення про помилку нижче"
            }
        }

        var accent: Color {
            switch self {
            case .idle: .indigo
            case .connecting: .orange
            case .listening: .cyan
            case .processing: .orange
            case .speaking: .yellow
            case .muted: .gray
            case .error: .red
            }
        }
    }

    private var state: VoiceState {
        if session.error != nil || session.agent.error != nil || localMedia.error != nil { return .error }
        if isStarting { return .connecting }
        guard session.isConnected else { return .idle }
        guard localMedia.isMicrophoneEnabled else { return .muted }
        let agent = String(describing: session.agent.agentState).lowercased()
        if agent.contains("speak") { return .speaking }
        if agent.contains("think") { return .processing }
        return .listening
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.bg1, state.accent.opacity(0.13), Color.bg1],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                header
                Spacer(minLength: 12)
                voiceOrb
                status
                controls
                errors
                Spacer(minLength: 16)
                privacyNote
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: state)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("ORBIT").font(.headline.weight(.bold)).tracking(3).foregroundStyle(.tint)
                Text("Голос").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "waveform")
                .font(.title3.weight(.semibold))
                .frame(width: 42, height: 42)
                .background(.thinMaterial, in: Circle())
                .accessibilityHidden(true)
        }
    }

    private var voiceOrb: some View {
        ZStack {
            Circle().fill(state.accent.opacity(0.10)).frame(width: 280, height: 280)
            Circle().stroke(state.accent.opacity(0.25), lineWidth: 1).frame(width: 232, height: 232)
                .rotationEffect(.degrees(reduceMotion ? 0 : (state == .listening || state == .speaking ? 18 : 0)))
            Circle()
                .fill(LinearGradient(colors: [state.accent.opacity(0.96), Color.indigo.opacity(0.85), Color.bgAccent], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 176, height: 176)
                .shadow(color: state.accent.opacity(0.45), radius: state == .speaking ? 34 : 22)
                .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1))
                .scaleEffect(reduceMotion ? 1 : (state == .speaking ? 1.07 : state == .listening ? 1.03 : 1))
            Image(systemName: state == .speaking ? "speaker.wave.2.fill" : "waveform")
                .font(.system(size: 52, weight: .medium))
                .foregroundStyle(.white)
        }
        .frame(height: 286)
        .accessibilityLabel("Стан голосового Orbit: \(state.title)")
    }

    private var status: some View {
        VStack(spacing: 6) {
            Text(state.title).font(.title2.weight(.semibold))
            Text(state.detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }

    private var controls: some View {
        Group {
            if session.isConnected {
                HStack(spacing: 12) {
                    Button { Task { await localMedia.toggleMicrophone() } } label: {
                        Label(localMedia.isMicrophoneEnabled ? "Мікрофон" : "Увімкнути мікрофон", systemImage: localMedia.isMicrophoneEnabled ? "mic.fill" : "mic.slash.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Button(role: .destructive) { Task { await OrbitRuntime.shared.endVoiceSession() } } label: {
                        Label("Завершити", systemImage: "stop.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            } else {
                Button {
                    guard !isStarting else { return }
                    Task {
                        isStarting = true
                        await OrbitRuntime.shared.startVoiceSession()
                        isStarting = false
                    }
                } label: {
                    Label(isStarting ? "Підключення…" : "Почати розмову", systemImage: "waveform.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .disabled(isStarting)
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var errors: some View {
        if let error = session.error {
            ErrorView(error: error) { Task { await OrbitRuntime.shared.endVoiceSession() }; session.dismissError() }
        } else if let error = session.agent.error {
            ErrorView(error: error) { Task { await OrbitRuntime.shared.endVoiceSession() } }
        } else if let error = localMedia.error {
            ErrorView(error: error) { Task { await OrbitRuntime.shared.endVoiceSession() }; localMedia.dismissError() }
        }
    }

    private var privacyNote: some View {
        Label("Голос запускається лише після вашого натискання.", systemImage: "lock.fill")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }
}
