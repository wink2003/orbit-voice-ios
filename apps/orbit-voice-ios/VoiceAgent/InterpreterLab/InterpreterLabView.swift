#if DEBUG
@preconcurrency import AVFoundation
import SwiftUI

@MainActor
final class InterpreterLabStore: ObservableObject {
    @Published var provider: InterpreterProviderKind = .azure
    @Published var direction: InterpreterDirection = .ukrainianToGerman
    @Published var mode: InterpreterMode = .live
    @Published private(set) var state: InterpreterState = .idle
    @Published private(set) var sourceTranscript = ""
    @Published private(set) var translatedText = ""
    @Published private(set) var diagnostics: [String] = []
    @Published private(set) var metrics = InterpreterLatencyMetrics()
    @Published private(set) var error: String?
    @Published private(set) var isRecordingFixture = false
    @Published private(set) var lastFixture: InterpreterRecordedFixture?
    private let auth: any InterpreterAuthProviding = MockInterpreterAuthProvider()
    private var activeProvider: (any InterpreterProvider)?
    private var eventTask: Task<Void, Never>?
    private var capturedMilliseconds: Double = 0
    private var fixturePCM = Data()

    func start() {
        guard state == .idle || state == .failed else { return }
        state = .preparing; error = nil; sourceTranscript = ""; translatedText = ""; metrics = InterpreterLatencyMetrics(); capturedMilliseconds = 0
        let selectedProvider = MockInterpreterProvider(kind: provider)
        activeProvider = selectedProvider
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            for await event in await selectedProvider.events() { await self?.receive(event) }
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                let authorization = try await auth.authorization(for: provider, direction: direction)
                try await selectedProvider.prepare(authorization: authorization)
                try await selectedProvider.start(direction: direction)
            } catch { await receive(.error(error.localizedDescription)) }
        }
    }

    func accept(frame: InterpreterPCMFrame) {
        if isRecordingFixture { fixturePCM.append(frame.data); capturedMilliseconds += frame.durationMilliseconds; return }
        metrics.firstInputPCM = metrics.firstInputPCM ?? frame.capturedAtNanoseconds
        capturedMilliseconds += frame.durationMilliseconds
        let activeProvider = activeProvider
        Task { try? await activeProvider?.accept(audio: frame) }
    }

    func stop() {
        guard let activeProvider else { return }
        state = .stopping
        Task { await activeProvider.stopInput(); await activeProvider.endSession() }
    }

    func reset() { stop(); eventTask?.cancel(); eventTask = nil; activeProvider = nil; state = .idle; sourceTranscript = ""; translatedText = ""; diagnostics = []; metrics = InterpreterLatencyMetrics(); error = nil; capturedMilliseconds = 0 }

    func beginFixtureRecording() { guard state == .idle else { return }; fixturePCM = Data(); capturedMilliseconds = 0; isRecordingFixture = true; state = .listening }
    func finishFixtureRecording() {
        guard isRecordingFixture else { return }; isRecordingFixture = false
        do { lastFixture = try InterpreterFixtureStore.save(fixturePCM, format: .canonical); state = .idle }
        catch { error = error.localizedDescription; state = .failed }
        fixturePCM = Data()
    }
    func replayLastFixture() {
        guard let fixture = lastFixture else { error = "Record a local fixture first."; state = .failed; return }
        Task { [weak self] in
            guard let self else { return }
            do {
                let data = try InterpreterFixtureStore.load(fixture)
                start()
                try await Task.sleep(for: .milliseconds(50))
                let bytesPerChunk = InterpreterAudioFormat.canonical.sampleRate * 2 / 10
                for offset in stride(from: 0, to: data.count, by: bytesPerChunk) {
                    let end = min(offset + bytesPerChunk, data.count)
                    accept(frame: InterpreterPCMFrame(data: data.subdata(in: offset..<end), format: .canonical, capturedAtNanoseconds: DispatchTime.now().uptimeNanoseconds))
                }
                stop()
            } catch { error = error.localizedDescription; state = .failed }
        }
    }

    func currentRecord(fixtureID: String? = nil) -> InterpreterBenchmarkRecord {
        InterpreterBenchmarkRecord(provider: provider, direction: direction, mode: mode, fixtureID: fixtureID, sessionID: UUID(), audioFormat: .canonical, inputAudioDurationMilliseconds: capturedMilliseconds, sourceTranscript: sourceTranscript, translatedText: translatedText, errors: error.map { [$0] } ?? [], reconnectCount: 0, interruptions: diagnostics.filter { $0.hasPrefix("interruption:") }, receivedAudioDurationMilliseconds: 0, providerUsageInputAudioSeconds: nil, providerUsageOutputAudioSeconds: nil, estimatedCostUSD: nil, latency: metrics)
    }

    private func receive(_ event: InterpreterEvent) {
        metrics.record(event)
        switch event {
        case .state(let value): state = value
        case .sourceTranscript(let text, _, _): sourceTranscript = text
        case .translatedText(let text, _, _): translatedText = text
        case .interruption(let value): diagnostics.append("interruption: \(value)")
        case .routeChanged(let value): diagnostics.append("route: \(value)")
        case .error(let value): error = value; state = .failed
        case .usage: break
        case .translatedAudio: break
        }
    }
}

@MainActor
final class InterpreterAudioCapture: NSObject, ObservableObject {
    @Published private(set) var isCapturing = false
    @Published private(set) var routeDescription = ""
    @Published private(set) var lastError: String?
    var onFrame: ((InterpreterPCMFrame) -> Void)?
    private let engine = AVAudioEngine()
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true)!
    private var converter: AVAudioConverter?

    func start() throws {
        guard !isCapturing else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)
        let input = engine.inputNode
        let sourceFormat = input.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else { throw CaptureError.unsupportedFormat }
        self.converter = converter
        routeDescription = session.currentRoute.outputs.map { $0.portName }.joined(separator: ", ")
        input.installTap(onBus: 0, bufferSize: 1_600, format: sourceFormat) { [weak self] buffer, _ in
            Task { @MainActor in self?.convertAndEmit(buffer) }
        }
        engine.prepare(); try engine.start(); isCapturing = true
    }

    func stop() {
        guard isCapturing else { return }
        engine.inputNode.removeTap(onBus: 0); engine.stop(); converter = nil; isCapturing = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func convertAndEmit(_ input: AVAudioPCMBuffer) {
        guard let converter, let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: 1_600) else { return }
        var supplied = false
        var conversionError: NSError?
        converter.convert(to: output, error: &conversionError) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true; status.pointee = .haveData; return input
        }
        guard conversionError == nil, output.frameLength > 0, let samples = output.int16ChannelData else { return }
        let data = Data(bytes: samples[0], count: Int(output.frameLength) * MemoryLayout<Int16>.size)
        let frame = InterpreterPCMFrame(data: data, format: .canonical, capturedAtNanoseconds: DispatchTime.now().uptimeNanoseconds)
        onFrame?(frame)
    }
    enum CaptureError: Error { case unsupportedFormat }
}

struct InterpreterLabView: View {
    @StateObject private var store = InterpreterLabStore()
    @StateObject private var capture = InterpreterAudioCapture()
    @State private var showDiagnostics = false
    var body: some View {
        NavigationStack {
            ScrollView { VStack(alignment: .leading, spacing: 18) {
                Text("ORBIT LIVE INTERPRETER").font(.caption.weight(.bold)).tracking(1.4).foregroundStyle(.tint)
                Text("Українська ↔ Deutsch").font(.largeTitle.weight(.bold)).accessibilityAddTraits(.isHeader)
                Text("DEBUG A/B laboratory · mock providers only · no conversation is sent until Phase 2 approval.").font(.subheadline).foregroundStyle(.secondary)
                picker("Provider", selection: $store.provider, values: InterpreterProviderKind.allCases) { $0.title }
                picker("Direction", selection: $store.direction, values: InterpreterDirection.allCases) { $0.title }
                picker("Mode", selection: $store.mode, values: InterpreterMode.allCases) { $0.title }
                stateCard
                transcriptCard("Input transcript", text: store.sourceTranscript, empty: "Waiting for source transcript")
                transcriptCard("Translation", text: store.translatedText, empty: "Waiting for translated text")
                metricsCard
                controls
                Button("Diagnostics") { showDiagnostics = true }.frame(maxWidth: .infinity).buttonStyle(.bordered)
                Text("Live mode is ephemeral: raw PCM is forwarded only to the selected provider during an explicit run and is never saved. Fixture recording/replay is credential-gated for Phase 2.").font(.footnote).foregroundStyle(.secondary)
            }.padding(20) }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Interpreter Lab").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showDiagnostics) { diagnostics }
        }
    }
    private func picker<T: CaseIterable & Identifiable & Hashable, Content: View>(_ title: String, selection: Binding<T>, values: T.AllCases, @ViewBuilder label: @escaping (T) -> Content) -> some View where T.AllCases: RandomAccessCollection {
        VStack(alignment: .leading, spacing: 7) { Text(title).font(.headline); Picker(title, selection: selection) { ForEach(Array(values), id: \.self) { value in label(value).tag(value) } }.pickerStyle(.segmented).accessibilityLabel(title) }
    }
    private var stateCard: some View { VStack(alignment: .leading, spacing: 6) { Label(store.state.title, systemImage: store.state == .failed ? "exclamationmark.triangle.fill" : "waveform.circle.fill").font(.title3.weight(.semibold)).foregroundStyle(store.state == .failed ? .red : .indigo); if let error = store.error { Text(error).font(.subheadline).foregroundStyle(.red) }; Text("Mic: \(capture.isCapturing ? "active" : "inactive") · Output route: \(capture.routeDescription.isEmpty ? "not active" : capture.routeDescription)").font(.footnote).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding().background(.background, in: RoundedRectangle(cornerRadius: 16)) }
    private func transcriptCard(_ title: String, text: String, empty: String) -> some View { VStack(alignment: .leading, spacing: 8) { Text(title).font(.headline); Text(text.isEmpty ? empty : text).textSelection(.enabled).foregroundStyle(text.isEmpty ? .secondary : .primary).frame(maxWidth: .infinity, minHeight: 46, alignment: .topLeading) }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.background, in: RoundedRectangle(cornerRadius: 16)) }
    private var metricsCard: some View { VStack(alignment: .leading, spacing: 8) { Text("Latency (monotonic)").font(.headline); metric("First transcript", store.metrics.milliseconds(from: store.metrics.firstInputPCM, to: store.metrics.firstSourceTranscript)); metric("Translation text", store.metrics.milliseconds(from: store.metrics.firstInputPCM, to: store.metrics.firstTranslatedText)); metric("Network first audio", store.metrics.milliseconds(from: store.metrics.firstInputPCM, to: store.metrics.firstTranslatedAudio)); metric("Audible first audio", store.metrics.milliseconds(from: store.metrics.firstInputPCM, to: store.metrics.firstAudioPlayed)); metric("Playback complete", store.metrics.milliseconds(from: store.metrics.firstInputPCM, to: store.metrics.playbackFinished)) }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.background, in: RoundedRectangle(cornerRadius: 16)) }
    private func metric(_ title: String, _ value: Double?) -> some View { LabeledContent(title, value: value.map { String(format: "%.0f ms", $0) } ?? "—").font(.subheadline.monospacedDigit()) }
    private var diagnostics: some View { NavigationStack { List { Section("Capture") { LabeledContent("Canonical PCM", value: "16 kHz · mono · 16-bit · 100 ms") ; LabeledContent("Mic", value: capture.isCapturing ? "active" : "inactive") } ; Section("Events") { if store.diagnostics.isEmpty { Text("No interruption, route change, cancellation, or restart events.").foregroundStyle(.secondary) } else { ForEach(store.diagnostics, id: \.self) { Text($0) } } } ; Section("Privacy") { Text("No credentials, request headers, raw PCM, Orbit Memory, chats, contacts, calendar, or messages are included in export.") } }.navigationTitle("Diagnostics").toolbar { Button("Done") { showDiagnostics = false } } } }
    @ViewBuilder private var controls: some View {
        if store.mode == .live {
            HStack(spacing: 12) { Button(store.state == .idle || store.state == .failed ? "Start" : "Stop") { toggle() }.buttonStyle(.borderedProminent).tint(store.state == .idle || store.state == .failed ? .indigo : .red).frame(maxWidth: .infinity).controlSize(.large); Button("Reset") { capture.stop(); store.reset() }.buttonStyle(.bordered).controlSize(.large) }
        } else {
            VStack(spacing: 10) {
                Button(store.isRecordingFixture ? "Stop & Save Fixture" : "Record Fixture") { if store.isRecordingFixture { capture.stop(); store.finishFixtureRecording() } else { store.beginFixtureRecording(); do { try capture.start(); capture.onFrame = store.accept(frame:) } catch { store.reset() } } }.buttonStyle(.borderedProminent).tint(store.isRecordingFixture ? .red : .indigo).frame(maxWidth: .infinity).controlSize(.large)
                Button("Replay Last Fixture") { store.replayLastFixture() }.buttonStyle(.bordered).frame(maxWidth: .infinity).disabled(store.lastFixture == nil)
                if let fixture = store.lastFixture { Text("Local fixture: \(fixture.byteCount / 32) ms · never uploaded except during an explicit future provider run.").font(.footnote).foregroundStyle(.secondary) }
            }
        }
    }
    private func toggle() { if store.state == .idle || store.state == .failed { store.start(); do { try capture.start(); capture.onFrame = store.accept(frame:) } catch { store.reset() } } else { capture.stop(); store.stop() } }
}
#endif
