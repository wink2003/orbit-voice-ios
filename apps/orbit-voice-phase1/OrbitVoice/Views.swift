import SwiftUI

struct PairingView: View {
    @ObservedObject var session: OrbitVoiceSession
    @State private var code = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "waveform.circle.fill").font(.system(size: 70)).foregroundStyle(.mint)
            Text("Orbit Voice").font(.largeTitle.bold())
            Text("Введіть одноразовий код активації з Orbit.").multilineTextAlignment(.center).foregroundStyle(.secondary)
            TextField("000000", text: $code).keyboardType(.numberPad).textContentType(.oneTimeCode)
                .font(.system(size: 30, design: .monospaced)).multilineTextAlignment(.center).padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            if let error { Text(error).foregroundStyle(.red).multilineTextAlignment(.center) }
            Button { Task { await pair() } } label: { if busy { ProgressView() } else { Text("Активувати") } }
                .buttonStyle(.borderedProminent).tint(.mint).disabled(code.filter(\.isNumber).count != 6 || busy)
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func pair() async {
        busy = true; error = nil; defer { busy = false }
        do { try await session.pair(code: code) } catch let caught { error = caught.localizedDescription }
    }
}

struct VoiceView: View {
    @ObservedObject var session: OrbitVoiceSession
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            Image(systemName: icon).font(.system(size: 90)).foregroundStyle(.mint)
            Text(title).font(.title2.weight(.semibold))
            if case let .error(message) = session.state { Text(message).foregroundStyle(.red).multilineTextAlignment(.center) }
            Button { Task { await session.end() } } label: { Label("Завершити", systemImage: "xmark.circle.fill") }
                .buttonStyle(.bordered)
            Spacer()
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
            .task { if session.state == .idle { await session.start() } }
    }
    private var title: String {
        switch session.state { case .idle: "Готово"; case .listening: "Слухаю"; case .thinking: "Думаю"; case .speaking: "Відповідаю"; case .error: "Помилка" }
    }
    private var icon: String {
        switch session.state { case .listening: "mic.fill"; case .thinking: "ellipsis.circle.fill"; case .speaking: "speaker.wave.2.fill"; default: "waveform.circle.fill" }
    }
}
