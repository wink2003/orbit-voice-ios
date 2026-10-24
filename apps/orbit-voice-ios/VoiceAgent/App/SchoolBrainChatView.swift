import SwiftUI
import UIKit

struct SchoolBrainView: View {
    @State private var model = SchoolBrainChatModel(service: SchoolBrainLiveService())
    @Environment(\.novaDockTopY) private var dockTopY
    @State private var contentMaxY: CGFloat = 0
    @FocusState private var composerFocused: Bool
#if DEBUG
    private let debugFixture: Routes05SchoolFixture?
#endif

    init() {
#if DEBUG
        self.debugFixture = nil
#endif
    }

#if DEBUG
    init(fixture: Routes05SchoolFixture) {
        self.debugFixture = fixture
        _model = State(initialValue: SchoolBrainChatModel(service: SchoolBrainLiveService(), debugMessages: Routes05DebugFixtures.schoolBrainMessages))
    }
#endif

    var body: some View {
        @Bindable var model = model
        ZStack {
            VStack(spacing: 0) {
                transcript
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    if let failure = model.sendFailure {
                        SchoolBrainErrorBanner(failure: failure, canRetry: failure.isRetryable && model.failedQuestion != nil && !model.isSending, retry: { Task { await model.retry() } }, dismiss: { model.dismissError() })
                    }
                    SchoolBrainStarterRow { model.applyStarter($0); composerFocused = true }
                    SchoolBrainComposer(text: $model.draft, isSending: model.isSending, canSend: model.canSend, focused: $composerFocused) { Task { await model.send() } }
                }
                .background(Routes05Tokens.canvas)
            }
            .padding(.bottom, SchoolBrainLayout.dockOverlap(contentMaxY: contentMaxY, dockTopY: dockTopY))
        }
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { contentMaxY = $0 }
        .background(Routes05Tokens.canvas.ignoresSafeArea())
        .navigationTitle("Запитати про школу")
        .navigationBarTitleDisplayMode(.inline)
        .task {
#if DEBUG
            if debugFixture == nil { await model.load() }
#else
            await model.load()
#endif
        }
    }

    @ViewBuilder private var transcript: some View {
        ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        Routes05ContextHeader(
                            section: "school",
                            eyebrow: "SCHOOL / ASK ORBIT",
                            title: "Поясню.\nЗнайду.",
                            detail: "Відповіді з посиланнями на авторизовані повідомлення й події.",
                            accent: Routes05Tokens.mint
                        )
                        switch model.loadState {
                    case .loading where model.messages.isEmpty:
                        ProgressView("Завантаження розмови…").frame(maxWidth: .infinity).padding(.top, 40)
                    case let .failed(failure) where model.messages.isEmpty:
                        SchoolBrainLoadFailure(failure: failure) { Task { await model.load() } }
                    default:
                        if model.isEmptyConversation { SchoolBrainEmptyState() }
                    }
                    ForEach(model.messages) { message in
                        SchoolBrainBubble(message: message, sources: model.sourceRows(for: message))
                    }
                    if let pending = model.pendingQuestion {
                        SchoolBrainBubble(message: OrbitSchoolBrainMessage(id: "pending", role: "user", content: pending, sourceRefs: [], createdAt: Date()), sources: [])
                        SchoolBrainWaitingBubble()
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await model.load() }
            .defaultScrollAnchor(.bottom)
            .onChange(of: model.messages.count) { _, _ in scrollToBottom(proxy) }
            .onChange(of: model.pendingQuestion) { _, _ in scrollToBottom(proxy) }
            .onChange(of: composerFocused) { _, focused in if focused { scrollToBottom(proxy) } }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
    }
}

private struct SchoolBrainBubble: View {
    let message: OrbitSchoolBrainMessage
    let sources: [SchoolBrainSourceRow]
    private var isUser: Bool { message.role == "user" }

    var body: some View {
        let blocks: [SchoolBrainMarkdown.Block] = isUser ? [] : SchoolBrainMarkdown.blocks(from: message.content)
        HStack(alignment: .top, spacing: 0) {
            if isUser { Spacer(minLength: 44) }
            VStack(alignment: .leading, spacing: 10) {
                if isUser {
                    Text(message.content)
                        .font(.body)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(Color.white)
                        .accessibilityLabel("Ви: \(message.content)")
                } else {
                    SchoolBrainMarkdownView(blocks: blocks, spokenText: SchoolBrainMarkdown.plainText(blocks))
                }
                if !sources.isEmpty { SchoolBrainSourcesSection(sources: sources) }
            }
            .frame(maxWidth: 560, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(isUser ? Routes05Tokens.lilac : Routes05Tokens.surface)
            .overlay(alignment: .leading) {
                if !isUser { Rectangle().fill(Routes05Tokens.blue).frame(width: 4) }
            }
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Routes05Tokens.ink, lineWidth: 1))
            .contextMenu { Button("Копіювати", systemImage: "doc.on.doc") { UIPasteboard.general.string = message.content } }
            if !isUser { Spacer(minLength: 44) }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }
}

private struct SchoolBrainMarkdownView: View {
    let blocks: [SchoolBrainMarkdown.Block]
    let spokenText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                row(for: block)
            }
        }
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Orbit: \(spokenText)")
    }

    @ViewBuilder private func row(for block: SchoolBrainMarkdown.Block) -> some View {
        switch block {
        case let .paragraph(text):
            Text(text).lineSpacing(3)
        case let .heading(text):
            Text(text).font(.headline).lineSpacing(2).padding(.top, 2)
        case let .bullet(level, text):
            listItem(marker: "•", level: level, text: text)
        case let .numbered(level, marker, text):
            listItem(marker: marker, level: level, text: text)
        case let .code(code):
            Text(code)
                .font(.system(.callout, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func listItem(marker: String, level: Int, text: AttributedString) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(marker).foregroundStyle(.secondary).fixedSize()
            Text(text).lineSpacing(3)
        }
        .padding(.leading, CGFloat(level) * 16)
    }
}

private struct SchoolBrainSourcesSection: View {
    let sources: [SchoolBrainSourceRow]
    @State private var expanded = false
    @State private var showAll = false
    private let collapsedLimit = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() } } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).rotationEffect(.degrees(expanded ? 90 : 0))
                    Text("Джерела · \(sources.count)").font(.footnote.weight(.semibold))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
                .frame(minHeight: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? "розгорнуто" : "згорнуто")
            if expanded {
                ForEach(showAll ? sources : Array(sources.prefix(collapsedLimit))) { source in
                    NavigationLink { SchoolDetailLoaderView(itemID: source.itemID) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: source.type == "letter" ? "envelope" : "message").frame(width: 20).foregroundStyle(NovaTodayTokens.indigo)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.displayTitle).font(.footnote).foregroundStyle(.primary).lineLimit(2).multilineTextAlignment(.leading)
                                Text([source.typeLabel, source.date.map(SchoolBrainSources.dateText)].compactMap { $0 }.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if !showAll && sources.count > collapsedLimit {
                    Button("Показати всі (\(sources.count))") { showAll = true }.font(.footnote).frame(minHeight: 32)
                }
            }
        }
    }
}

private struct SchoolBrainWaitingBubble: View {
    var body: some View {
        HStack {
            HStack(spacing: 8) { ProgressView(); Text("Orbit готує відповідь…").font(.subheadline).foregroundStyle(.secondary) }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Routes05Tokens.surface)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Routes05Tokens.rule, lineWidth: 1))
            Spacer(minLength: 44)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Orbit готує відповідь")
    }
}

private struct SchoolBrainEmptyState: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(NovaTodayTokens.indigo)
            Text("Запитайте про школу").font(.headline)
            Text("Orbit відповість на основі шкільних листів, повідомлень і календаря. Оберіть підказку нижче або напишіть своє запитання.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .accessibilityElement(children: .combine)
    }
}

private struct SchoolBrainLoadFailure: View {
    let failure: SchoolBrainFailure
    let retry: () -> Void
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle").font(.title2).foregroundStyle(.orange)
            Text(failure.loadMessage).font(.subheadline).multilineTextAlignment(.center)
            if failure.isRetryable { Button("Повторити", action: retry).buttonStyle(.bordered) }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 32)
    }
}

private struct SchoolBrainErrorBanner: View {
    let failure: SchoolBrainFailure
    let canRetry: Bool
    let retry: () -> Void
    let dismiss: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
            Text(failure.message).font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
            if canRetry { Button("Повторити", action: retry).font(.footnote.weight(.semibold)).frame(minHeight: 44) }
            Button { dismiss() } label: { Image(systemName: "xmark").font(.footnote) }.frame(minWidth: 44, minHeight: 44).accessibilityLabel("Закрити")
        }
        .padding(.horizontal, 14)
        .background(Color.orange.opacity(0.12))
        .accessibilityElement(children: .contain)
    }
}

private struct SchoolBrainStarterRow: View {
    let choose: (String) -> Void
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SchoolBrainStarters.all, id: \.self) { value in
                    Button { choose(value) } label: {
                        Text(value).font(.subheadline.weight(.medium)).lineLimit(1)
                            .padding(.horizontal, 14).frame(minHeight: 44)
                            .background(Routes05Tokens.surface)
                            .overlay(Capsule().strokeBorder(Routes05Tokens.rule, lineWidth: 1))
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Додає питання в поле вводу")
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
        }
    }
}

private struct SchoolBrainComposer: View {
    @Binding var text: String
    let isSending: Bool
    let canSend: Bool
    var focused: FocusState<Bool>.Binding
    let send: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Запитайте про школу…", text: $text, axis: .vertical)
                .lineLimit(1...5)
                .focused(focused)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Routes05Tokens.surface)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Routes05Tokens.ink, lineWidth: 1))
                .accessibilityLabel("Запитання про школу")
            Button(action: send) {
                Group {
                    if isSending { ProgressView() } else { Image(systemName: "arrow.up.circle.fill").font(.title) }
                }
                .frame(width: 44, height: 44)
            }
            .disabled(!canSend)
            .tint(Routes05Tokens.yellow)
            .accessibilityLabel(isSending ? "Надсилання" : "Надіслати")
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }
}
