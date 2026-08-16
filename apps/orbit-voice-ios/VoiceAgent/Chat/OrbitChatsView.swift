import SwiftUI
import UIKit

struct OrbitChatsView: View {
    @EnvironmentObject private var authentication: OrbitAuthentication
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
                } else {
                    List(chats) { chat in
                        Button { selectedChat = chat } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Image(systemName: chat.kind == "family" ? "person.3.fill" : "sparkles")
                                        .foregroundStyle(chat.kind == "family" ? .teal : .indigo)
                                    Text(chat.title).font(.headline)
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                                }
                                Text(chat.lastMessage ?? chat.subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .padding(.vertical, 5)
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
                OrbitConversationView(conversation: chat)
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
            familyProfiles = (try? await MainProductAPI.shared.familyProfiles()) ?? []
        } catch {
            self.error = error
        }
    }
}

private struct OrbitConversationView: View {
    let conversation: OrbitConversation
    @State private var messages: [OrbitChatMessage] = []
    @State private var draft = ""
    @State private var isSending = false
    @State private var error: Error?

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(messages) { message in
                            MessageBubble(message: message)
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
                    }
                    .padding(.vertical)
                }
                .onChange(of: messages.count) { _, _ in
                    guard let last = messages.last else { return }
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            Divider()
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Написати Orbit…", text: $draft, axis: .vertical)
                    .lineLimit(1 ... 5)
                    .textFieldStyle(.roundedBorder)
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 30))
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            }
            .padding()
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

    private func loadMessages() async {
        do { messages = try await OrbitChatAPI.shared.messages(in: conversation) }
        catch { self.error = error }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        draft = ""
        isSending = true
        Task {
            defer { isSending = false }
            do {
                let response = try await OrbitChatAPI.shared.send(text, to: conversation)
                messages.append(response.userMessage)
                messages.append(response.assistantMessage)
            } catch {
                draft = text
                self.error = error
            }
        }
    }
}

private struct MessageBubble: View {
    let message: OrbitChatMessage

    var body: some View {
        HStack {
            if message.senderKind == "person" { Spacer(minLength: 52) }
            SelectableMarkdownText(
                content: message.content,
                foregroundColor: message.senderKind == "person" ? .white : .label
            )
                .contextMenu {
                    #if os(iOS)
                    Button { UIPasteboard.general.string = message.content } label: { Label("Копіювати", systemImage: "doc.on.doc") }
                    #endif
                    ShareLink(item: message.content) { Label("Поділитися", systemImage: "square.and.arrow.up") }
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 10)
                .background(message.senderKind == "person" ? Color.indigo : Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18))
            if message.senderKind == "orbit" { Spacer(minLength: 52) }
        }
        .padding(.horizontal)
    }

}

private struct SelectableMarkdownText: UIViewRepresentable {
    let content: String
    let foregroundColor: UIColor

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
        view.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 300
        return uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    }
}
