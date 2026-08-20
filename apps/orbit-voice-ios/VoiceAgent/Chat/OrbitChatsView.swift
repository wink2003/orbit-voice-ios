import SwiftUI
import UIKit

struct OrbitChatsView: View {
    var contactPrompt: String? = nil
    @State private var profile: OrbitProfile?
    @State private var chats: [OrbitConversation] = []
    @State private var selectedChat: OrbitConversation?
    @State private var isLoading = true
    @State private var error: Error?
    @State private var familyProfiles: [OrbitFamilyProfile] = []

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Завантажую чати…")
                } else if chats.isEmpty {
                    ContentUnavailableView {
                        Label("Чатів ще немає", systemImage: "bubble.left.and.bubble.right")
                    } description: {
                        Text("Ваші особисті та родинні розмови з Orbit з’являться тут.")
                    } actions: {
                        Button("Оновити") { Task { await load() } }
                    }
                } else {
                    List(chats) { chat in
                        Button { selectedChat = chat } label: {
                            HStack(spacing: 12) {
                                Image(systemName: chat.kind == "family" ? "person.3.fill" : "sparkles")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .frame(width: 38, height: 38)
                                    .background(chat.kind == "family" ? Color.teal : Color.indigo, in: Circle())
                                VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(chat.title).font(.headline)
                                    Spacer()
                                    if let updatedAt = chat.updatedAt {
                                        Text(updatedAt, style: .relative)
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                    Text(chat.lastMessage ?? chat.subtitle)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 3)
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Чати")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let profile {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Label("Активний профіль", systemImage: "checkmark.circle")
                            if !familyProfiles.isEmpty {
                                Section("Профілі родини") {
                                    ForEach(familyProfiles) { familyProfile in
                                        Label(
                                            familyProfile.displayName + (familyProfile.personId == profile.personId ? " · активний" : ""),
                                            systemImage: familyProfile.personId == profile.personId ? "checkmark" : "person"
                                        )
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(profile.displayName).font(.footnote)
                                Image(systemName: "chevron.down").font(.caption2)
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationDestination(item: $selectedChat) { chat in
                OrbitConversationView(conversation: chat, initialDraft: contactPrompt)
            }
            .task { await load() }
            .refreshable { await load() }
            .alert("Не вдалося відкрити чати", isPresented: .constant(error != nil)) {
                Button("Гаразд") { error = nil }
            } message: {
                Text(error?.localizedDescription ?? "Спробуй ще раз.")
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await OrbitChatAPI.shared.chats()
            profile = response.profile
            chats = response.chats
            isLoading = false
            Task { await loadFamilyProfiles() }
        } catch {
            self.error = error
        }
    }

    private func loadFamilyProfiles() async {
        familyProfiles = (try? await MainProductAPI.shared.familyProfiles()) ?? []
    }
}

private struct OrbitConversationView: View {
    let conversation: OrbitConversation
    let initialDraft: String?
    @State private var messages: [OrbitChatMessage] = []
    @State private var draft = ""
    @State private var isSending = false
    @State private var error: Error?
    @State private var isAtLatest = true
    @State private var showLatestButton = false
    @State private var jumpToLatestRequest = 0
    @State private var didInitialLoad = false
    @State private var failedMessageID: String?
    @AppStorage("orbit.chat.haptics") private var hapticsEnabled = true

    init(conversation: OrbitConversation, initialDraft: String? = nil) {
        self.conversation = conversation
        self.initialDraft = initialDraft
        _draft = State(initialValue: initialDraft ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if messages.isEmpty && !isSending {
                            VStack(alignment: .leading, spacing: 14) {
                                Label("Чим допомогти?", systemImage: "sparkles")
                                    .font(.title3.weight(.semibold))
                                Text("Поставте запитання або оберіть швидкий початок.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 8) {
                                    quickPrompt("Спланувати мій день")
                                    quickPrompt("Що ти пам’ятаєш?")
                                }
                                quickPrompt("Написати родині", fullWidth: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(20)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .padding(.horizontal)
                            .padding(.top, 24)
                        }
                        ForEach(messages) { message in
                            MessageBubble(
                                message: message,
                                deliveryFailed: failedMessageID == message.id,
                                isActionInFlight: isSending,
                                confirmAction: canConfirm(message) ? { submitConfirmation("Підтверджую") } : nil,
                                cancelAction: canConfirm(message) ? { submitConfirmation("Скасувати") } : nil
                            )
                                .id(message.id)
                        }
                        if isSending {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text("Orbit думає…").font(.footnote).foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal)
                        }
                        Color.clear
                            .frame(height: 1)
                            .id("chat-latest")
                    }
                    .padding(.vertical)
                }
                .scrollDismissesKeyboard(.interactively)
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    max(0, geometry.contentSize.height - geometry.contentOffset.y - geometry.containerSize.height)
                } action: { _, distanceFromLatest in
                    let atLatest = distanceFromLatest < 40
                    isAtLatest = atLatest
                    showLatestButton = !atLatest && !messages.isEmpty
                }
                .onChange(of: messages.count) { _, _ in
                    let firstLoad = !didInitialLoad
                    didInitialLoad = true
                    scrollToLatest(using: proxy, animated: !firstLoad && isAtLatest)
                }
                .onChange(of: isSending) { _, sending in
                    if sending && isAtLatest {
                        scrollToLatest(using: proxy, animated: false)
                    }
                }
                .onChange(of: jumpToLatestRequest) { _, _ in
                    scrollToLatest(using: proxy, animated: true)
                }
                .onAppear {
                    scrollToLatest(using: proxy, animated: false)
                }
            }
            Divider()
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Написати Orbit…", text: $draft, axis: .vertical)
                    .lineLimit(1 ... 5)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                Button(action: send) {
                    Image(systemName: isSending ? "ellipsis" : "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(canSend ? Color.indigo : Color.secondary, in: Circle())
                }
                .disabled(!canSend)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .overlay(alignment: .bottomTrailing) {
            if showLatestButton {
                Button {
                    showLatestButton = false
                    isAtLatest = true
                    jumpToLatestRequest += 1
                } label: {
                    Label("До останнього", systemImage: "arrow.down")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                }
                .padding(.trailing, 18)
                .padding(.bottom, 68)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .navigationTitle(conversation.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task { await loadMessages() }
        .alert("Orbit тимчасово недоступний", isPresented: .constant(error != nil)) {
            Button("Гаразд") { error = nil }
        } message: {
            Text(error?.localizedDescription ?? "Спробуй ще раз.")
        }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    @ViewBuilder
    private func quickPrompt(_ title: String, fullWidth: Bool = false) -> some View {
        Button {
            draft = title
        } label: {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .frame(maxWidth: fullWidth ? .infinity : nil, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func scrollToLatest(using proxy: ScrollViewProxy, animated: Bool) {
        guard !messages.isEmpty || isSending else { return }
        Task { @MainActor in
            await Task.yield()
            if animated {
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("chat-latest", anchor: .bottom) }
            } else {
                proxy.scrollTo("chat-latest", anchor: .bottom)
            }
        }
    }

    private func loadMessages() async {
        do { messages = try await OrbitChatAPI.shared.messages(in: conversation) }
        catch { self.error = error }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        let clientMessageID = UUID().uuidString.lowercased()
        let localMessageID = "local-\(clientMessageID)"
        let localMessage = OrbitChatMessage(
            id: localMessageID,
            conversationId: conversation.id,
            senderKind: "person",
            senderPersonId: nil,
            content: text,
            createdAt: .now,
            clientMessageId: clientMessageID,
            actionConfirmation: nil
        )
        draft = ""
        failedMessageID = nil
        messages.append(localMessage)
        if hapticsEnabled {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        isSending = true
        Task { @MainActor in
            defer { isSending = false }
            do {
                let response = try await OrbitChatAPI.shared.send(text, to: conversation, clientMessageId: clientMessageID)
                if let index = messages.firstIndex(where: { $0.id == localMessageID }) {
                    messages[index] = response.userMessage
                }
                if !messages.contains(where: { $0.id == response.assistantMessage.id }) {
                    messages.append(response.assistantMessage)
                }
            } catch {
                if !(await reconcile(clientMessageID: clientMessageID)) {
                    failedMessageID = localMessageID
                    draft = text
                    self.error = error
                }
            }
        }
    }

    private func reconcile(clientMessageID: String) async -> Bool {
        guard let remoteMessages = try? await OrbitChatAPI.shared.messages(in: conversation),
              remoteMessages.contains(where: { $0.clientMessageId == clientMessageID }) else { return false }
        messages = remoteMessages
        failedMessageID = nil
        return true
    }

    private func canConfirm(_ message: OrbitChatMessage) -> Bool {
        guard message.senderKind == "orbit", let confirmation = message.actionConfirmation else { return false }
        return confirmation.status == "proposed" && confirmation.needsConfirmation
    }

    private func submitConfirmation(_ text: String) {
        guard !isSending else { return }
        draft = text
        send()
    }
}

private struct MessageBubble: View {
    let message: OrbitChatMessage
    let deliveryFailed: Bool
    let isActionInFlight: Bool
    let confirmAction: (() -> Void)?
    let cancelAction: (() -> Void)?
    @AppStorage("orbit.chat.showTimestamps") private var showTimestamp = false
    @AppStorage("orbit.chat.compact") private var compactMessages = false

    var body: some View {
        HStack {
            if message.senderKind == "person" { Spacer(minLength: 52) }
            VStack(alignment: message.senderKind == "person" ? .trailing : .leading, spacing: 4) {
                SelectableMarkdownText(
                    content: message.content,
                    foregroundColor: message.senderKind == "person" ? .white : .label
                )
                    .equatable()
                    .contextMenu {
                        #if os(iOS)
                        Button { UIPasteboard.general.string = message.content } label: { Label("Копіювати", systemImage: "doc.on.doc") }
                        #endif
                        ShareLink(item: message.content) { Label("Поділитися", systemImage: "square.and.arrow.up") }
                    }
                if showTimestamp {
                    Text(message.createdAt, style: .time)
                        .font(.caption2)
                        .foregroundStyle(message.senderKind == "person" ? .white.opacity(0.75) : .secondary)
                }
                if let confirmation = message.actionConfirmation,
                   confirmation.status == "proposed",
                   confirmation.needsConfirmation {
                    ActionConfirmationCard(
                        confirmation: confirmation,
                        isActionInFlight: isActionInFlight,
                        confirmAction: confirmAction,
                        cancelAction: cancelAction
                    )
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, compactMessages ? 7 : 10)
                .background(message.senderKind == "person" ? Color.indigo : Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18))
            if message.senderKind == "orbit" { Spacer(minLength: 52) }
        }
        .padding(.horizontal)
        .overlay(alignment: .bottomTrailing) {
            if deliveryFailed {
                Label("Не підтверджено", systemImage: "exclamationmark.circle")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .padding(.trailing, 20)
                    .offset(y: 18)
            }
        }
    }

}

private struct ActionConfirmationCard: View {
    let confirmation: OrbitActionConfirmation
    let isActionInFlight: Bool
    let confirmAction: (() -> Void)?
    let cancelAction: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(confirmation.channel == "telegram" ? "Telegram" : confirmation.channel == "whatsapp" ? "WhatsApp" : "Повідомлення", systemImage: confirmation.channel == "telegram" ? "paperplane.fill" : "message.fill")
                .font(.subheadline.weight(.semibold))
            Text("Отримувач: \(confirmation.recipient)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("Текст повідомлення: \(confirmation.message)")
                .font(.footnote)
                .lineLimit(4)
            HStack(spacing: 10) {
                Button("Скасувати", action: { cancelAction?() })
                    .buttonStyle(.bordered)
                Button("Підтвердити", action: { confirmAction?() })
                    .buttonStyle(.borderedProminent)
            }
            .disabled(isActionInFlight || confirmAction == nil || cancelAction == nil)
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Підтвердження надсилання повідомлення для \(confirmation.recipient)")
    }
}

private struct SelectableMarkdownText: UIViewRepresentable, Equatable {
    let content: String
    let foregroundColor: UIColor

    static func == (lhs: SelectableMarkdownText, rhs: SelectableMarkdownText) -> Bool {
        lhs.content == rhs.content && lhs.foregroundColor == rhs.foregroundColor
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.dataDetectorTypes = [.link]
        view.adjustsFontForContentSizeCategory = true
        view.font = UIFont.preferredFont(forTextStyle: .body)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        guard context.coordinator.content != content || context.coordinator.foregroundColor != foregroundColor else { return }
        let attributed: NSAttributedString
        if let markdown = try? AttributedString(markdown: content, options: .init(interpretedSyntax: .full)) {
            attributed = NSAttributedString(markdown)
        } else {
            attributed = NSAttributedString(string: content)
        }
        let mutable = NSMutableAttributedString(attributedString: attributed)
        mutable.addAttribute(.foregroundColor, value: foregroundColor, range: NSRange(location: 0, length: mutable.length))
        mutable.addAttribute(.font, value: UIFont.preferredFont(forTextStyle: .body), range: NSRange(location: 0, length: mutable.length))
        view.attributedText = mutable
        context.coordinator.content = content
        context.coordinator.foregroundColor = foregroundColor
        view.invalidateIntrinsicContentSize()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var content = ""
        var foregroundColor: UIColor = .clear
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 300
        return uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }
}
