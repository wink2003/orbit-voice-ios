import LiveKit
import SwiftUI
import UIKit

struct OrbitChatsView: View {
    var contactPrompt: String? = nil
    #if DEBUG
    var fixture: Routes05ChatFixture? = nil
    #endif
    @State private var profile: OrbitProfile?
    @State private var chats: [OrbitConversation] = []
    @State private var selectedChat: OrbitConversation?
    @State private var showingSchoolBrain = false
    @State private var isLoading = true
    @State private var error: Error?
    @State private var familyProfiles: [OrbitFamilyProfile] = []
    @State private var showingVoice = false
    @State private var isCreatingConversation = false
    @State private var selectedFilter = "Всі"
    #if DEBUG
    private let debugConversation: Bool
    #endif

    #if DEBUG
    init(contactPrompt: String? = nil, fixture: Routes05ChatFixture? = nil, debugConversation: Bool = false) {
        self.contactPrompt = contactPrompt
        self.fixture = fixture
        self.debugConversation = debugConversation
        _profile = State(initialValue: fixture?.profile)
        _chats = State(initialValue: fixture?.chats ?? [])
        _selectedChat = State(initialValue: debugConversation ? fixture?.chats.first : nil)
        _isLoading = State(initialValue: fixture == nil)
    }
    #endif

    private var visibleChats: [OrbitConversation] {
        #if DEBUG
        fixture?.chats ?? chats
        #else
        chats
        #endif
    }

    private var filteredChats: [OrbitConversation] {
        switch selectedFilter {
        case "Особисті": return visibleChats.filter { $0.kind == "personal" }
        case "Сімейні": return visibleChats.filter { $0.kind == "family" }
        default: return visibleChats
        }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                    Routes05Mast(section: "core") { showingVoice = true }
                    Routes05Chapter("ORBIT / 02", title: "Orbit / розмови", detail: "Ваші розмови, збережені в Orbit.", accent: Routes05Tokens.yellow)
                    coreAgentHero
                    Routes05SectionHeader("Розмови", action: "Створити") { createConversation() }
                        .padding(.horizontal, 16)
                    filterChips
                    if isLoading { ProgressView("Завантажую чати…").frame(maxWidth: .infinity, minHeight: 80) }
                    else if filteredChats.isEmpty { Routes05StateRow(text: "Для цього фільтра розмов немає.", tint: Routes05Tokens.blue) }
                    else {
                        ForEach(Array(filteredChats.enumerated()), id: \.element.id) { index, chat in
                            Button { selectedChat = chat } label: { chatRow(chat, index: index + 1) }
                                .buttonStyle(.plain)
                        }
                    }
                    Button { showingVoice = true } label: {
                        HStack {
                            Text("◉ ГОЛОС").font(.caption.weight(.black))
                            Text("Говорити з Orbit").font(.caption)
                            Spacer()
                            Image(systemName: "arrow.right").font(.caption.weight(.black))
                        }
                        .foregroundStyle(Routes05Tokens.darkSurfaceInk)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 44)
                        .background(Routes05Tokens.darkSurface)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("routes05-orbit-voice")
                        .padding(.top, 2)
                    Color.clear.frame(height: 1).id("routes05-bottom")
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .safeAreaPadding(.bottom, 96)
                .onAppear {
                    guard Routes05DebugCapture.scrollToBottom else { return }
                    DispatchQueue.main.async { proxy.scrollTo("routes05-bottom", anchor: .bottom) }
                }
            }
            .background(Routes05Tokens.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingVoice) { OrbitVoiceSheet() }
            .navigationDestination(item: $selectedChat) { chat in
                #if DEBUG
                OrbitConversationView(conversation: chat, initialDraft: contactPrompt, debugMessages: debugConversation ? Routes05DebugFixtures.conversationMessages : nil)
                #else
                OrbitConversationView(conversation: chat, initialDraft: contactPrompt)
                #endif
            }
            .navigationDestination(isPresented: $showingSchoolBrain) {
                SchoolBrainView()
            }
            .task {
                #if DEBUG
                if fixture == nil { await load() }
                #else
                await load()
                #endif
            }
            .refreshable {
                #if DEBUG
                if fixture == nil { await load() }
                #else
                await load()
                #endif
            }
            .alert("Не вдалося відкрити чати", isPresented: .constant(error != nil)) {
                Button("Гаразд") { error = nil }
            } message: {
                Text(error?.localizedDescription ?? "Спробуй ще раз.")
            }
        }
    }

    private var coreAgentHero: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("CORE AGENT / READY").font(.system(size: 10, weight: .black, design: .monospaced)).tracking(1.2)
                    Spacer(minLength: 4)
                    if let profile {
                        Menu {
                            Button { createConversation() } label: { Label("Нова розмова", systemImage: "plus.bubble") }
                            Label("Активний профіль", systemImage: "checkmark.circle")
                            if !familyProfiles.isEmpty {
                                Section("Профілі родини") {
                                    ForEach(familyProfiles) { familyProfile in
                                        Label(familyProfile.displayName + (familyProfile.personId == profile.personId ? " · активний" : ""), systemImage: familyProfile.personId == profile.personId ? "checkmark" : "person")
                                    }
                                }
                            }
                        } label: {
                            Image(systemName: "person.crop.circle")
                                .font(.headline)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Профіль \(profile.displayName)")
                    }
                }
                Text("Запитайте\nщо завгодно.").font(.system(.title, design: .rounded).weight(.black)).tracking(-1)
                Button("НОВА РОЗМОВА ↗") { createConversation() }
                    .font(.caption.weight(.black)).foregroundStyle(Routes05Tokens.ink)
                    .padding(.horizontal, 8).frame(minHeight: 34).background(Routes05Tokens.mint)
            }
            .foregroundStyle(Routes05Tokens.darkSurfaceInk)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            ZStack {
                Circle().stroke(Routes05Tokens.ink, lineWidth: 7).frame(width: 66, height: 66)
                Circle().fill(Routes05Tokens.yellow).frame(width: 40, height: 40)
            }
            .frame(width: 126).frame(maxHeight: .infinity)
            .background(Routes05Tokens.mint)
        }
        .frame(minHeight: 162)
        .background(Routes05Tokens.darkSurface)
        .overlay(Rectangle().stroke(Routes05Tokens.ink, lineWidth: 1))
        .padding(.horizontal, 16)
    }

    private var filterChips: some View {
        HStack(spacing: 8) {
            ForEach(["Всі", "Особисті", "Сімейні"], id: \.self) { value in
                Button(value) { selectedFilter = value }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(selectedFilter == value ? Routes05Tokens.darkSurfaceInk : Routes05Tokens.ink)
                    .padding(.horizontal, 13).frame(minHeight: 36)
                    .background(selectedFilter == value ? Routes05Tokens.darkSurface : Routes05Tokens.surface, in: Capsule())
                    .overlay(Capsule().stroke(Routes05Tokens.rule, lineWidth: 1))
            }
        }
        .padding(.horizontal, 16)
    }

    private func chatRow(_ chat: OrbitConversation, index: Int) -> some View {
        Routes05IndexedRow(index: String(format: "%02d", index), tint: chat.kind == "family" ? Routes05Tokens.mint : Routes05Tokens.blue) {
            VStack(alignment: .leading, spacing: 3) {
                Text(OrbitChatPresentation.displayTitle(kind: chat.kind, title: chat.title)).font(.subheadline.weight(.bold)).lineLimit(1)
                Text(chat.lastMessage ?? chat.subtitle).font(.caption).foregroundStyle(Routes05Tokens.secondary).lineLimit(2)
            }
        }
        .padding(.horizontal, 16)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await OrbitChatAPI.shared.chats()
            profile = response.profile
            chats = response.chats
            if OrbitChatNavigationPolicy.opensExplicitConversation(contactPrompt: contactPrompt), selectedChat == nil {
                selectedChat = response.chats.first(where: { $0.kind == "personal" })
            }
            isLoading = false
            Task { await loadFamilyProfiles() }
        } catch {
            self.error = error
        }
    }

    private func createConversation() {
        guard !isCreatingConversation else { return }
        isCreatingConversation = true
        Task { @MainActor in
            defer { isCreatingConversation = false }
            if let conversation = try? await OrbitChatAPI.shared.createConversation() {
                chats.insert(conversation, at: 0)
                selectedChat = conversation
            }
        }
    }

    private func loadFamilyProfiles() async {
        familyProfiles = (try? await MainProductAPI.shared.familyProfiles()) ?? []
    }
}

private struct OrbitConversationView: View {
    let conversation: OrbitConversation
    let initialDraft: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.novaDockVisible) private var novaDockVisible
    @State private var messages: [OrbitChatMessage] = []
    @State private var draft = ""
    @State private var isSending = false
    @State private var error: Error?
    @State private var isAtLatest = true
    @State private var showLatestButton = false
    @State private var jumpToLatestRequest = 0
    @State private var didInitialLoad = false
    @State private var failedMessageID: String?
    @State private var agentPollTasks: [String: Task<Void, Never>] = [:]
    @State private var isStopping = false
    @State private var showingVoice = false
    @State private var searchText = ""
    @AppStorage("orbit.chat.haptics") private var hapticsEnabled = true
    private let debugMessages: [OrbitChatMessage]?

    init(conversation: OrbitConversation, initialDraft: String? = nil, debugMessages: [OrbitChatMessage]? = nil) {
        self.conversation = conversation
        self.initialDraft = initialDraft
        self.debugMessages = debugMessages
        _draft = State(initialValue: initialDraft ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        Routes05ContextHeader(
                            section: "core",
                            eyebrow: "CORE AGENT / CONVERSATION",
                            title: OrbitChatPresentation.displayTitle(kind: conversation.kind, title: conversation.title),
                            detail: "Контекст, джерела й підтвердження — в одному маршруті.",
                            accent: Routes05Tokens.blue
                        )
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
                            .background(Routes05Tokens.surface)
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Routes05Tokens.ink, lineWidth: 1))
                            .padding(.horizontal)
                            .padding(.top, 24)
                        }
                        if !searchText.isEmpty {
                            Text(visibleMessages.isEmpty ? "Нічого не знайдено серед завантажених повідомлень" : "Пошук лише серед завантажених повідомлень")
                                .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                        }
                        ForEach(visibleMessages) { item in
                            if let separator = item.layout.dateSeparator {
                                Text(separator)
                                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                    .padding(.horizontal, 12).padding(.vertical, 4)
                                    .background(OrbitColors.bubbleOther, in: Capsule())
                                    .padding(.top, 8)
                                    .accessibilityAddTraits(.isHeader)
                            }
                            MessageBubble(
                                message: item.message,
                                deliveryFailed: failedMessageID == item.message.id,
                                isActionInFlight: isSending,
                                startsGroup: item.layout.startsGroup,
                                endsGroup: item.layout.endsGroup,
                                retryAction: failedMessageID == item.message.id ? { retryFailed() } : nil,
                                confirmAction: canConfirm(item.message) ? { submitConfirmation("Підтверджую") } : nil,
                                cancelAction: canConfirm(item.message) ? { submitConfirmation("Скасувати") } : nil
                            )
                                .id(item.message.id)
                        }
                        if isAgentWorking {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text(isStopping ? "Зупиняю…" : "Orbit працює над відповіддю — це може тривати довше")
                                    .font(.footnote).foregroundStyle(.secondary)
                                Spacer()
                                Button("Зупинити") { stopAgent() }
                                    .buttonStyle(.bordered)
                                    .disabled(isStopping)
                                    .frame(minHeight: OrbitSpacing.minTarget)
                            }
                            .padding(.horizontal)
                            .accessibilityElement(children: .contain)
                        } else if isSending {
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
            // Reserve the inline native navigation-bar footprint on the
            // viewport, rather than in transcript content. This keeps
            // scroll-to-latest from cancelling the masthead clearance.
            .padding(.top, 96)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
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
                        .frame(width: OrbitSpacing.minTarget, height: OrbitSpacing.minTarget)
                        .background(canSend ? Color.accentColor : Color.secondary, in: Circle())
                }
                .disabled(!canSend)
                .accessibilityLabel("Надіслати")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Routes05Tokens.canvas)
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
                .frame(minHeight: OrbitSpacing.minTarget)
                .padding(.trailing, 18)
                .padding(.bottom, 68)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .background(Routes05Tokens.canvas.ignoresSafeArea())
        .navigationTitle(OrbitChatPresentation.displayTitle(kind: conversation.kind, title: conversation.title))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(Routes05Tokens.canvas, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Пошук у завантажених")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Розмови") { dismiss() }
                    .frame(minHeight: OrbitSpacing.minTarget)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingVoice = true } label: { Image(systemName: "waveform") }
                    .frame(minWidth: OrbitSpacing.minTarget, minHeight: OrbitSpacing.minTarget)
                    .accessibilityLabel("Голосова розмова")
            }
        }
        .sheet(isPresented: $showingVoice) { OrbitVoiceSheet() }
        .toolbar(.hidden, for: .tabBar)
        .task { await loadMessages() }
        .onAppear { novaDockVisible.wrappedValue = false }
        .onDisappear {
            novaDockVisible.wrappedValue = true
            cancelLocalAgentPolling()
        }
        .alert("Orbit тимчасово недоступний", isPresented: .constant(error != nil)) {
            Button("Гаразд") { error = nil }
        } message: {
            Text(error?.localizedDescription ?? "Спробуй ще раз.")
        }
    }

    private struct DisplayedMessage: Identifiable {
        let message: OrbitChatMessage
        let layout: OrbitChatRowLayout
        var id: String { message.id }
    }

    private var visibleMessages: [DisplayedMessage] {
        let filtered = messages.filter { OrbitChatPresentation.matches($0.content, query: searchText) }
        let rows = filtered.map { OrbitChatRowInput(id: $0.id, senderKey: $0.senderKind == "person" ? "person:\($0.senderPersonId ?? "me")" : $0.senderKind, date: $0.createdAt) }
        let layouts = OrbitChatPresentation.layout(rows)
        return zip(filtered, layouts).map { DisplayedMessage(message: $0, layout: $1) }
    }

    private var isAgentWorking: Bool { !agentPollTasks.isEmpty }

    private func stopAgent() {
        guard !isStopping else { return }
        let runIDs = Array(agentPollTasks.keys)
        isStopping = true
        Task { @MainActor in
            defer { isStopping = false }
            for runID in runIDs { _ = try? await OrbitChatAPI.shared.cancelAgentRun(in: conversation, runId: runID) }
        }
    }

    private func retryFailed() {
        guard let failedID = failedMessageID, let failed = messages.first(where: { $0.id == failedID }), !isSending else { return }
        messages.removeAll { $0.id == failedID }
        failedMessageID = nil
        draft = failed.content
        send()
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
        #if DEBUG
        if let debugMessages {
            messages = debugMessages
            return
        }
        #endif
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
                if let run = response.agentRun {
                    startAgentPolling(runId: run.id, placeholderID: response.assistantMessage.id)
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

    // Polling is local only: cancelling it never cancels the server-side run.
    private func cancelLocalAgentPolling() {
        agentPollTasks.values.forEach { $0.cancel() }
        agentPollTasks.removeAll()
    }

    private func startAgentPolling(runId: String, placeholderID: String) {
        guard agentPollTasks[runId] == nil else { return }
        agentPollTasks[runId] = Task { @MainActor in
            defer { agentPollTasks[runId] = nil }
            let delays: [UInt64] = [1_500_000_000] + Array(repeating: 2_500_000_000, count: 70)
            for delay in delays {
                try? await Task.sleep(nanoseconds: delay)
                if Task.isCancelled { return }
                guard let status = try? await OrbitChatAPI.shared.agentRunStatus(in: conversation, runId: runId) else { continue }
                if Task.isCancelled { return }
                guard status.isDone else { continue }
                let outcome = OrbitAgentRunMerge.applyTerminal(&messages, placeholderID: placeholderID, durable: status.assistantMessage)
                if outcome == .needsRefresh { await quietRefresh() }
                return
            }
            if Task.isCancelled { return }
            OrbitAgentRunMerge.removePlaceholder(&messages, placeholderID: placeholderID)
            await quietRefresh()
        }
    }

    private func quietRefresh() async {
        if let remote = try? await OrbitChatAPI.shared.messages(in: conversation) { messages = remote }
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
    var startsGroup = true
    var endsGroup = true
    var retryAction: (() -> Void)? = nil
    let confirmAction: (() -> Void)?
    let cancelAction: (() -> Void)?
    @AppStorage("orbit.chat.showTimestamps") private var showTimestamp = false
    @AppStorage("orbit.chat.compact") private var compactMessages = false

    var body: some View {
        HStack {
            if message.senderKind == "person" { Spacer(minLength: 52) }
            VStack(alignment: message.senderKind == "person" ? .trailing : .leading, spacing: 4) {
                Text(message.senderKind == "person" ? "ВИ" : "ORBIT / ВІДПОВІДЬ")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(message.senderKind == "person" ? Routes05Tokens.accentInk : Routes05Tokens.darkSurfaceInk)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(message.senderKind == "person" ? Routes05Tokens.mint : Routes05Tokens.darkSurface)
                SelectableMarkdownText(
                    content: message.content,
                    foregroundColor: message.senderKind == "person" ? .black : .label
                )
                    .equatable()
                    .contextMenu {
                        #if os(iOS)
                        Button { UIPasteboard.general.string = message.content } label: { Label("Копіювати", systemImage: "doc.on.doc") }
                        #endif
                        ShareLink(item: message.content) { Label("Поділитися", systemImage: "square.and.arrow.up") }
                    }
                if showTimestamp || endsGroup {
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
                .background(message.senderKind == "person" ? Routes05Tokens.lilac : Routes05Tokens.surface)
                .overlay(alignment: .leading) {
                    if message.senderKind == "orbit" {
                        Rectangle().fill(Routes05Tokens.blue).frame(width: 4)
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Routes05Tokens.ink, lineWidth: 1))
            if message.senderKind == "orbit" { Spacer(minLength: 52) }
        }
        .padding(.horizontal)
        .padding(.top, startsGroup ? 8 : 0)
        .accessibilityElement(children: .contain)
        .overlay(alignment: .bottomTrailing) {
            if deliveryFailed {
                HStack(spacing: 8) {
                    Label("Не надіслано", systemImage: "exclamationmark.circle")
                        .font(.caption2)
                        .foregroundStyle(OrbitColors.danger)
                    if let retryAction {
                        Button("Повторити", action: retryAction)
                            .font(.caption.weight(.semibold))
                            .frame(minHeight: OrbitSpacing.minTarget)
                    }
                }
                .padding(.trailing, 20)
                .offset(y: 30)
            }
        }
        .padding(.bottom, deliveryFailed ? 30 : 0)
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
        .background(Routes05Tokens.surface)
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Routes05Tokens.ink, lineWidth: 1))
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
        let displaySource = OrbitChatMarkdownFormatting.preservingWhitespaceSource(content)
        let cleanSource = OrbitChatMarkdownFormatting.strippingLiteralHeadingMarkers(displaySource)
        let headingTitles = OrbitChatMarkdownFormatting.literalHeadingTitles(displaySource)
        if let markdown = try? AttributedString(markdown: cleanSource, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            attributed = NSAttributedString(markdown)
        } else {
            attributed = NSAttributedString(string: content)
        }
        let mutable = NSMutableAttributedString(attributedString: attributed)
        mutable.addAttribute(.foregroundColor, value: foregroundColor, range: NSRange(location: 0, length: mutable.length))
        let baseFont = UIFont.preferredFont(forTextStyle: .body)
        mutable.enumerateAttribute(.font, in: NSRange(location: 0, length: mutable.length)) { value, range, _ in
            let traits = (value as? UIFont)?.fontDescriptor.symbolicTraits ?? []
            let descriptor = baseFont.fontDescriptor.withSymbolicTraits(traits) ?? baseFont.fontDescriptor
            mutable.addAttribute(.font, value: UIFont(descriptor: descriptor, size: 0), range: range)
        }
        var searchLocation = 0
        for title in headingTitles where !title.isEmpty {
            let searchRange = NSRange(location: searchLocation, length: max(0, mutable.length - searchLocation))
            let titleRange = (mutable.string as NSString).range(of: title, options: [], range: searchRange)
            if titleRange.location != NSNotFound {
                mutable.addAttribute(.font, value: UIFont.preferredFont(forTextStyle: .headline), range: titleRange)
                searchLocation = NSMaxRange(titleRange)
            }
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        paragraph.paragraphSpacing = 7
        mutable.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: mutable.length))
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

// Voice stays an explicit action: the session is only started by a button inside MainVoiceHomeView.
struct OrbitVoiceSheet: View {
    @EnvironmentObject private var session: Session
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            MainVoiceHomeView()
                .navigationTitle("Голос")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Закрити") { dismiss() }
                            .disabled(session.isConnected)
                            .frame(minHeight: OrbitSpacing.minTarget)
                    }
                }
        }
        .interactiveDismissDisabled(session.isConnected)
    }
}
