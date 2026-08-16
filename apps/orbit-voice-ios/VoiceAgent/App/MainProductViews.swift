import SwiftUI

struct FamilyHubView: View {
    @State private var profiles: [OrbitFamilyProfile] = []
    @State private var messages: [OrbitFamilyMessage] = []
    @State private var isLoading = true
    @State private var error: Error?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let error {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Не вдалося завантажити сімейні дані", systemImage: "exclamationmark.triangle")
                            Text(error.localizedDescription).font(.footnote).foregroundStyle(.secondary)
                            Button("Повторити") { Task { await load() } }
                        }
                    } else if profiles.isEmpty && !isLoading {
                        ContentUnavailableView("Профілів ще немає", systemImage: "person.3", description: Text("Коли профілі будуть доступні, вони з’являться тут."))
                    } else {
                        ForEach(profiles) { profile in
                            HStack(spacing: 12) {
                                Text(initials(profile.displayName))
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                    .frame(width: 40, height: 40)
                                    .background(profile.isMinor ? Color.teal : Color.indigo, in: Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.displayName).font(.headline)
                                    Text(profile.isMinor ? "Дитина" : "Член родини")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }

                Section("Останнє в родині") {
                    if messages.isEmpty && !isLoading {
                        Text("Спільних повідомлень ще немає.").foregroundStyle(.secondary)
                    } else {
                        ForEach(messages.suffix(3)) { message in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(message.senderDisplayName).font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text(message.createdAt, style: .relative).font(.caption).foregroundStyle(.secondary)
                                }
                                Text(message.content).lineLimit(2)
                            }
                        }
                    }
                }

                Section {
                    NavigationLink { FamilyMessengerView() } label: {
                        Label("Відкрити родинний чат", systemImage: "bubble.left.and.bubble.right")
                    }
                }

                Section {
                    Label("Приватна інформація доступна лише відповідно до налаштувань доступу.", systemImage: "lock.fill")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Сім’я")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await load() }
            .task { await load() }
            .overlay { if isLoading { ProgressView() } }
        }
    }

    private func load() async {
        isLoading = true; defer { isLoading = false }
        do {
            async let loadedProfiles = MainProductAPI.shared.familyProfiles()
            async let loadedMessages = MainProductAPI.shared.familyMessages(limit: 20)
            profiles = try await loadedProfiles
            messages = try await loadedMessages
        } catch let caught { error = caught }
    }

    private func initials(_ name: String) -> String {
        let parts = name.split(separator: " ")
        return String(parts.prefix(2).compactMap { $0.first }).uppercased()
    }
}

struct FamilyMessengerView: View {
    @State private var messages: [OrbitFamilyMessage] = []
    @State private var draft = ""
    @State private var isSending = false
    @State private var error: Error?

    var body: some View {
        VStack(spacing: 0) {
            if messages.isEmpty {
                ContentUnavailableView("Родинний чат", systemImage: "bubble.left.and.bubble.right", description: Text("Напишіть коротке повідомлення для сім’ї."))
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(messages) { message in
                                familyMessage(message)
                                    .id(message.id)
                            }
                        }
                        .padding()
                        .onChange(of: messages.count) { _, _ in
                            if let id = messages.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
                        }
                    }
                }
            }
            Divider()
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Повідомлення сім’ї…", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1 ... 4)
                Button { send() } label: { Image(systemName: "arrow.up.circle.fill").font(.system(size: 30)) }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            }
            .padding()
        }
        .navigationTitle("Родинний чат")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task { await load() }
        .refreshable { await load() }
        .alert("Родинний чат недоступний", isPresented: .constant(error != nil)) {
            Button("Гаразд") { error = nil }
        } message: { Text(error?.localizedDescription ?? "Спробуйте ще раз.") }
    }

    private func familyMessage(_ message: OrbitFamilyMessage) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(message.senderDisplayName).font(.caption.weight(.semibold))
                Text(message.createdAt, style: .time).font(.caption2).foregroundStyle(.secondary)
            }
            Text(message.content)
                .textSelection(.enabled)
                #if os(iOS)
                .contextMenu { Button { UIPasteboard.general.string = message.content } label: { Label("Копіювати", systemImage: "doc.on.doc") } }
                #endif
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func load() async {
        do { messages = try await MainProductAPI.shared.familyMessages() } catch { self.error = error }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        draft = ""; isSending = true
        Task {
            defer { isSending = false }
            do { messages.append(try await MainProductAPI.shared.sendFamilyMessage(text)) }
            catch let caught { draft = text; error = caught }
        }
    }
}

struct OrbitCalendarView: View {
    @State private var events: [OrbitCalendarEvent] = []
    @State private var showingEditor = false
    @State private var editingEvent: OrbitCalendarEvent?
    @State private var deleteCandidate: OrbitCalendarEvent?
    @State private var error: Error?

    var body: some View {
        NavigationStack {
            List {
                if events.isEmpty {
                    ContentUnavailableView("Календар порожній", systemImage: "calendar", description: Text("Додайте першу сімейну подію."))
                } else {
                    ForEach(events) { event in calendarRow(event) }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Календар")
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.locale, Locale(identifier: "uk_UA"))
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { editingEvent = nil; showingEditor = true } label: { Image(systemName: "plus") } } }
            .task { await load() }
            .refreshable { await load() }
            .sheet(isPresented: $showingEditor) {
                CalendarEventEditor(event: editingEvent) { event in
                    await save(event)
                }
            }
            .onChange(of: showingEditor) { _, isPresented in
                if !isPresented { Task { await load() } }
            }
            .confirmationDialog("Видалити подію?", isPresented: Binding(
                get: { deleteCandidate != nil },
                set: { if !$0 { deleteCandidate = nil } }
            )) {
                Button("Видалити", role: .destructive) {
                    if let event = deleteCandidate { Task { await delete(event) } }
                    deleteCandidate = nil
                }
                Button("Скасувати", role: .cancel) {}
            } message: { Text("Подію буде приховано з родинного календаря.") }
            .alert("Помилка календаря", isPresented: .constant(error != nil)) {
                Button("Гаразд") { error = nil }
            } message: { Text(error?.localizedDescription ?? "Спробуйте ще раз.") }
        }
    }

    private func load() async { do { events = try await MainProductAPI.shared.calendarEvents() } catch let caught { error = caught } }

    private func calendarRow(_ event: OrbitCalendarEvent) -> some View {
        Button { editingEvent = event; showingEditor = true } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(event.title).font(.headline).foregroundStyle(.primary)
                    Spacer()
                    Text(event.startsAt, style: .date).font(.caption).foregroundStyle(.secondary)
                }
                Text(event.startsAt, style: .time).font(.subheadline).foregroundStyle(.secondary)
                if !event.notes.isEmpty {
                    Text(event.notes).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                }
                Label(event.sourceType == "external" ? "Зовнішній календар" : "Сімейний Orbit", systemImage: "calendar.badge.checkmark")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { deleteCandidate = event } label: {
                Label("Видалити", systemImage: "trash")
            }
        }
    }

    private func save(_ event: OrbitCalendarEvent?) async {
        do {
            if let event { let updated = try await MainProductAPI.shared.updateCalendarEvent(event); replace(updated) }
        } catch let caught { error = caught }
        if event == nil { await load() }
    }
    private func delete(_ event: OrbitCalendarEvent) async {
        do { try await MainProductAPI.shared.deleteCalendarEvent(event); events.removeAll { $0.id == event.id } }
        catch let caught { error = caught }
    }
    private func replace(_ event: OrbitCalendarEvent) { if let index = events.firstIndex(where: { $0.id == event.id }) { events[index] = event } else { events.append(event) } }
}

private struct CalendarEventEditor: View {
    @Environment(\.dismiss) private var dismiss
    let existing: OrbitCalendarEvent?
    let onSave: (OrbitCalendarEvent?) async -> Void
    @State private var title = ""
    @State private var notes = ""
    @State private var startsAt = Date().addingTimeInterval(3600)
    @State private var endsAt = Date().addingTimeInterval(7200)
    @State private var allDay = false
    @State private var saving = false

    init(event: OrbitCalendarEvent?, onSave: @escaping (OrbitCalendarEvent?) async -> Void) { existing = event; self.onSave = onSave }
    var body: some View {
        NavigationStack {
            Form {
                Section("Подія") {
                    TextField("Назва", text: $title)
                    TextField("Нотатки", text: $notes, axis: .vertical)
                    Toggle("Весь день", isOn: $allDay)
                }
                Section("Час") {
                    DatePicker("Початок", selection: $startsAt)
                    DatePicker("Кінець", selection: $endsAt, in: startsAt...)
                }
            }
            .navigationTitle(existing == nil ? "Нова подія" : "Редагувати")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Скасувати") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Зберегти") { Task { await save() } }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving) }
            }
            .onAppear { if let existing { title = existing.title; notes = existing.notes; startsAt = existing.startsAt; endsAt = existing.endsAt; allDay = existing.allDay } }
        }
    }
    private func save() async {
        saving = true; defer { saving = false }
        if let existing { await onSave(OrbitCalendarEvent(id: existing.id, familyId: existing.familyId, ownerPersonId: existing.ownerPersonId, title: title, notes: notes, startsAt: startsAt, endsAt: endsAt, allDay: allDay, sourceType: existing.sourceType, sourceIdentifier: existing.sourceIdentifier, createdAt: existing.createdAt, updatedAt: existing.updatedAt)) }
        else {
            do { _ = try await MainProductAPI.shared.createCalendarEvent(title: title, notes: notes, startsAt: startsAt, endsAt: endsAt, allDay: allDay) }
            catch { return }
        }
        dismiss()
    }
}

struct OrbitToolsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Дії") {
                    NavigationLink { OrbitChatsView() } label: { Label("Виконати дію через Orbit", systemImage: "paperplane") }
                    Text("Orbit підготує дію в чаті та попросить підтвердження, якщо воно потрібне.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Інтеграції") {
                    Label("Пам’ять Orbit — активна", systemImage: "brain.head.profile")
                    Label("Telegram — керується Orbit", systemImage: "paperplane")
                    Label("WhatsApp — не підключено", systemImage: "message.badge")
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Інструменти")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
        }
    }
}

struct OrbitSettingsView: View {
    @EnvironmentObject private var authentication: OrbitAuthentication
    @EnvironmentObject private var audioOptions: AudioOptions
    @State private var showingAudio = false
    @State private var serverOnline: Bool?
    @State private var showsChangeUserConfirmation = false

    var body: some View {
        NavigationStack {
            List {
                Section("Профіль") {
                    Label(authentication.displayName ?? "Активний профіль", systemImage: "person.crop.circle")
                    Button("Змінити профіль на цьому iPhone", role: .destructive) { showsChangeUserConfirmation = true }
                }
                Section("Голос") {
                    Button { showingAudio = true } label: { LabeledContent("Обробка мікрофона", value: audioOptions.voiceProcessingModeLabel) }
                    LabeledContent("Стан голосу", value: "Готовий до запуску")
                }
                Section("Пам’ять і приватність") {
                    Label("Memory V2 увімкнено", systemImage: "brain.head.profile")
                    Text("Orbit використовує релевантну пам’ять за правилами доступу. Медичні, фінансові та юридичні дані не стають спільними автоматично.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Стан") {
                    LabeledContent("Сервер", value: serverOnline == true ? "Доступний" : serverOnline == false ? "Недоступний" : "Перевірка…")
                    LabeledContent("Telegram", value: "Керується сервером")
                    LabeledContent("Версія / збірка", value: "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"))")
                }
                Section("Інструменти та інтеграції") {
                    NavigationLink { OrbitToolsView() } label: { Label("Інструменти", systemImage: "wrench.and.screwdriver") }
                }
                Section("Про Orbit") { Text("Main Orbit — сімейний AI-помічник. Orbit Mini залишається окремим клієнтом для голосу без рук.").font(.footnote).foregroundStyle(.secondary) }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Налаштування")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingAudio) { AudioOptionsSheet() }
            .task { await checkServer() }
            .confirmationDialog("Змінити профіль на цьому iPhone?", isPresented: $showsChangeUserConfirmation) {
                Button("Змінити профіль", role: .destructive) { authentication.forgetDevice() }
                Button("Скасувати", role: .cancel) {}
            } message: {
                Text("Поточний профіль буде від’єднано. Для повторної активації знадобиться новий одноразовий код.")
            }
        }
    }
    private func checkServer() async {
        guard let url = URL(string: "https://voice.orbit.opik.net/healthz") else { return }
        do { let (_, response) = try await URLSession.shared.data(from: url); serverOnline = (response as? HTTPURLResponse)?.statusCode == 200 }
        catch { serverOnline = false }
    }
}

private extension AudioOptions {
    var voiceProcessingModeLabel: String {
        switch voiceProcessingMode { case .automatic: "Автоматично"; case .platform: "Система"; case .software: "Програмно" }
    }
}
