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
    @State private var integrations: OrbitIntegrationStatus?
    @State private var statusUnavailable = false

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
                    whatsappStatus
                }
                Section("Контакти") {
                    NavigationLink { OrbitContactsView() } label: {
                        Label("Контакти Orbit", systemImage: "person.crop.circle.badge.plus")
                    }
                    Text("Єдина адресна книга Orbit для явних WhatsApp і Telegram-ідентичностей.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Інструменти")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .task { await loadStatus() }
        }
    }

    @ViewBuilder
    private var whatsappStatus: some View {
        if let whatsapp = integrations?.whatsapp {
            Label(whatsAppStatusLabel(whatsapp), systemImage: "message.badge")
                .foregroundStyle(whatsapp.state == "not_configured" ? .secondary : .primary)
        } else if statusUnavailable {
            Label("WhatsApp — стан недоступний", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        } else {
            Label("WhatsApp — перевірка…", systemImage: "message.badge")
                .foregroundStyle(.secondary)
        }
    }

    private func loadStatus() async {
        do {
            integrations = try await MainProductAPI.shared.integrationStatus()
            statusUnavailable = false
        } catch {
            statusUnavailable = true
        }
    }
}

struct OrbitContactsView: View {
    @State private var contacts: [OrbitContact] = []
    @State private var query = ""
    @State private var isLoading = true
    @State private var error: Error?
    @State private var editor: OrbitContact?
    @State private var showingEditor = false

    var body: some View {
        List {
            if isLoading && contacts.isEmpty {
                ProgressView("Завантажую контакти…")
            } else if contacts.isEmpty {
                ContentUnavailableView {
                    Label(query.isEmpty ? "Контактів ще немає" : "Нічого не знайдено", systemImage: "person.2")
                } description: {
                    Text(query.isEmpty ? "Додайте контакт, щоб швидко знаходити його в Orbit." : "Спробуйте інше ім’я, номер або username.")
                }
            } else {
                ForEach(contacts) { contact in
                    NavigationLink {
                        OrbitContactDetailView(contact: contact) { updated in
                            replace(updated)
                        } onArchive: {
                            contacts.removeAll { $0.id == contact.id }
                        }
                    } label: { OrbitContactRow(contact: contact) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Контакти")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Знайти контакт")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { editor = nil; showingEditor = true } label: { Image(systemName: "plus") }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .onChange(of: query) { _, _ in Task { await load() } }
        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                OrbitContactEditor(contact: editor) { saved in
                    replace(saved)
                    showingEditor = false
                }
            }
        }
        .alert("Контакти недоступні", isPresented: .constant(error != nil)) {
            Button("Гаразд") { error = nil }
        } message: { Text(error?.localizedDescription ?? "Спробуйте ще раз.") }
    }

    private func load() async {
        do { contacts = try await MainProductAPI.shared.contacts(query: query); error = nil }
        catch { self.error = error }
        isLoading = false
    }
    private func replace(_ contact: OrbitContact) {
        if let index = contacts.firstIndex(where: { $0.id == contact.id }) { contacts[index] = contact }
        else { contacts.append(contact); contacts.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending } }
    }
}

private struct OrbitContactRow: View {
    let contact: OrbitContact
    var body: some View {
        HStack(spacing: 12) {
            Text(String(contact.displayName.prefix(1)).uppercased())
                .font(.headline).foregroundStyle(.white).frame(width: 40, height: 40)
                .background(Color.indigo, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(contact.displayName).font(.headline)
                if let nickname = contact.nickname, !nickname.isEmpty { Text(nickname).font(.caption).foregroundStyle(.secondary) }
                HStack(spacing: 10) {
                    if contact.whatsappNumber != nil { Label("WhatsApp", systemImage: "message.fill") }
                    if contact.telegramPeer != nil { Label("Telegram", systemImage: "paperplane.fill") }
                }.font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 3)
    }
}

private struct OrbitContactEditor: View {
    @Environment(\.dismiss) private var dismiss
    let existing: OrbitContact?
    let onSaved: (OrbitContact) -> Void
    @State private var name: String
    @State private var nickname: String
    @State private var note: String
    @State private var whatsapp: String
    @State private var telegram: String
    @State private var visibility: String
    @State private var targetPersonId: String
    @State private var profiles: [OrbitFamilyProfile] = []
    @State private var saving = false
    @State private var error: Error?

    init(contact: OrbitContact?, onSaved: @escaping (OrbitContact) -> Void) {
        existing = contact; self.onSaved = onSaved
        _name = State(initialValue: contact?.displayName ?? "")
        _nickname = State(initialValue: contact?.nickname ?? "")
        _note = State(initialValue: contact?.note ?? "")
        _whatsapp = State(initialValue: contact?.whatsappNumber.map { "+\($0)" } ?? "")
        _telegram = State(initialValue: contact?.telegramUsername ?? contact?.telegramPeer ?? "")
        _visibility = State(initialValue: contact?.visibility ?? "private")
        _targetPersonId = State(initialValue: contact?.targetPersonId ?? "")
    }

    var body: some View {
        Form {
            Section("Контакт") {
                TextField("Ім’я", text: $name)
                TextField("Псевдонім", text: $nickname)
                TextField("Нотатка", text: $note, axis: .vertical).lineLimit(2...5)
            }
            Section("Канали") {
                TextField("WhatsApp · +380…", text: $whatsapp).keyboardType(.phonePad)
                TextField("Telegram username або відомий peer", text: $telegram).textInputAutocapitalization(.never)
                Text("Orbit надсилає лише через явно збережену ідентичність. Це не змінює телефонну книгу Telegram.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Видимість") {
                Picker("Контакт", selection: $visibility) {
                    Text("Особистий").tag("private")
                    Text("Спільний для родини").tag("family_shared")
                }
                .pickerStyle(.segmented)
            }
            Section("Явний профіль Orbit") {
                Picker("Пов’язати з профілем", selection: $targetPersonId) {
                    Text("Не пов’язувати").tag("")
                    ForEach(profiles) { profile in Text(profile.displayName).tag(profile.personId) }
                }
                Text("Це лише явна позначка профілю Orbit і не визначається за ім’ям чи номером.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(existing == nil ? "Новий контакт" : "Редагувати контакт")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Скасувати") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("Зберегти") { Task { await save() } }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving) }
        }
        .task { profiles = (try? await MainProductAPI.shared.familyProfiles()) ?? [] }
        .alert("Не вдалося зберегти", isPresented: .constant(error != nil)) { Button("Гаразд") { error = nil } } message: { Text(error?.localizedDescription ?? "Перевірте дані.") }
    }

    private func save() async {
        saving = true; defer { saving = false }
        let payload = MainProductAPI.OrbitContactPayload(displayName: name.trimmingCharacters(in: .whitespacesAndNewlines), nickname: nickname.nilIfBlank, note: note.nilIfBlank, whatsappNumber: whatsapp.nilIfBlank, telegramPeer: telegram.nilIfBlank, telegramUsername: telegram.nilIfBlank, targetPersonId: targetPersonId.nilIfBlank, visibility: visibility)
        do {
            let saved = if let existing { try await MainProductAPI.shared.updateContact(id: existing.id, payload) } else { try await MainProductAPI.shared.createContact(payload) }
            onSaved(saved); dismiss()
        } catch { error = error }
    }
}

private struct OrbitContactDetailView: View {
    let contact: OrbitContact
    let onUpdated: (OrbitContact) -> Void
    let onArchive: () -> Void
    @State private var current: OrbitContact
    @State private var showingEditor = false
    @State private var showingArchive = false
    @State private var archiveError: Error?

    init(contact: OrbitContact, onUpdated: @escaping (OrbitContact) -> Void, onArchive: @escaping () -> Void) {
        self.contact = contact; self.onUpdated = onUpdated; self.onArchive = onArchive
        _current = State(initialValue: contact)
    }

    var body: some View {
        List {
            Section {
                OrbitContactRow(contact: current)
                if let note = current.note, !note.isEmpty { Text(note).font(.subheadline).foregroundStyle(.secondary) }
            }
            Section("Написати через Orbit") {
                if current.whatsappNumber != nil {
                    NavigationLink { OrbitChatsView(contactPrompt: "Напиши \(current.displayName) у WhatsApp: ") } label: { Label("Написати в WhatsApp", systemImage: "message.fill") }
                }
                if current.telegramPeer != nil {
                    NavigationLink { OrbitChatsView(contactPrompt: "Напиши \(current.displayName) у Telegram: ") } label: { Label("Написати в Telegram", systemImage: "paperplane.fill") }
                }
            }
            Section {
                Button("Редагувати") { showingEditor = true }
                Button("Архівувати контакт", role: .destructive) { showingArchive = true }
            }
        }
        .navigationTitle(current.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingEditor) { NavigationStack { OrbitContactEditor(contact: current) { current = $0; onUpdated($0) } } }
        .confirmationDialog("Архівувати контакт?", isPresented: $showingArchive) {
            Button("Архівувати", role: .destructive) {
                Task {
                    do { try await MainProductAPI.shared.archiveContact(id: current.id); onArchive() }
                    catch { archiveError = error }
                }
            }
            Button("Скасувати", role: .cancel) {}
        } message: { Text("Історія повідомлень не видаляється. Контакт просто зникне зі списку.") }
        .alert("Не вдалося архівувати", isPresented: .constant(archiveError != nil)) {
            Button("Гаразд") { archiveError = nil }
        } message: { Text(archiveError?.localizedDescription ?? "Спробуйте ще раз.") }
    }
}

private extension String {
    var nilIfBlank: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self }
}

private func whatsAppStatusLabel(_ status: OrbitWhatsAppIntegrationStatus) -> String {
    switch status.state {
    case "provider_accepted": "WhatsApp — підключено"
    case "inbound_verified": "WhatsApp — підключено, надсилання потребує підтвердження"
    case "configured": "WhatsApp — налаштовано"
    default: "WhatsApp — потребує налаштування"
    }
}

struct MemoryCenterView: View {
    @State private var response: OrbitMemoryCenterResponse?
    @State private var query = ""
    @State private var isLoading = true
    @State private var error: Error?
    @State private var correctingAssertion: OrbitMemoryAssertion?
    @AppStorage("orbit.memory.showHistory") private var showHistory = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && response == nil {
                    ProgressView("Завантажую пам’ять…")
                } else if let error, response == nil {
                    ContentUnavailableView {
                        Label("Пам’ять недоступна", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error.localizedDescription)
                    } actions: {
                        Button("Повторити") { Task { await load() } }
                    }
                } else if isEmpty {
                    ContentUnavailableView {
                        Label(query.isEmpty ? "Пам’яті ще немає" : "Нічого не знайдено", systemImage: query.isEmpty ? "brain.head.profile" : "magnifyingglass")
                    } description: {
                        Text(query.isEmpty ? "Коли Orbit збереже важливу інформацію, вона з’явиться тут." : memorySearchEmptyDescription(showHistory: showHistory))
                    }
                } else {
                    List {
                        if let response {
                            if !response.assertions.isEmpty {
                                Section("Факти та вподобання") {
                                    ForEach(response.assertions) { assertion in
                                        NavigationLink {
                                            MemoryAssertionDetailView(assertion: assertion) { correctingAssertion = assertion }
                                        } label: {
                                            MemoryAssertionRow(assertion: assertion)
                                        }
                                    }
                                }
                            }
                            if !response.relationships.isEmpty {
                                Section("Зв’язки") {
                                    ForEach(response.relationships) { relationship in
                                        MemoryRelationshipRow(relationship: relationship)
                                    }
                                }
                            }
                            if !response.events.isEmpty {
                                Section("Події") {
                                    ForEach(response.events) { event in
                                        MemoryEventRow(event: event)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Центр пам’яті")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Знайти в пам’яті")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        MemoryImportsView()
                    } label: {
                        Image(systemName: "tray.full")
                    }
                    .accessibilityLabel("Імпорти пам’яті")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Toggle("Показувати історію", isOn: $showHistory)
                        Button { Task { await load() } } label: { Label("Оновити", systemImage: "arrow.clockwise") }
                    } label: {
                        Image(systemName: showHistory ? "clock.arrow.circlepath" : "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .environment(\.locale, Locale(identifier: "uk_UA"))
            .task { await load() }
            .refreshable { await load() }
            .onSubmit(of: .search) { Task { await load() } }
            .onChange(of: showHistory) { _, _ in Task { await load() } }
            .onChange(of: query) { _, value in
                if value.isEmpty { Task { await load() } }
            }
            .sheet(item: $correctingAssertion) { assertion in
                MemoryCorrectionSheet(assertion: assertion) {
                    try await MainProductAPI.shared.correctMemoryAssertion(id: assertion.id, correction: $0)
                    await load()
                }
            }
            .alert("Помилка пам’яті", isPresented: .constant(error != nil && response != nil)) {
                Button("Гаразд") { error = nil }
            } message: {
                Text(error?.localizedDescription ?? "Спробуйте ще раз.")
            }
        }
    }

    private var isEmpty: Bool {
        guard let response else { return true }
        return response.assertions.isEmpty && response.relationships.isEmpty && response.events.isEmpty
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            response = try await MainProductAPI.shared.memoryCenter(query: query, includeHistory: showHistory)
            error = nil
        } catch {
            self.error = error
        }
    }
}

private struct MemoryImportsView: View {
    @State private var batches: [OrbitMemoryImportBatch] = []
    @State private var isLoading = true
    @State private var error: Error?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Завантажую імпорти…")
            } else if let error {
                ContentUnavailableView {
                    Label("Імпорти тимчасово недоступні", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error.localizedDescription)
                } actions: {
                    Button("Повторити") { Task { await load() } }
                }
            } else if batches.isEmpty {
                ContentUnavailableView {
                    Label("Імпортів ще немає", systemImage: "tray")
                } description: {
                    Text("Коли експорт ChatGPT буде безпечно проаналізовано, тут з’являться його стан і підсумок. Дані не додаються до пам’яті без окремого підтвердження.")
                }
            } else {
                List(batches) { batch in
                    NavigationLink {
                        MemoryImportDetailView(batch: batch)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Label("ChatGPT", systemImage: "sparkles")
                                Spacer()
                                Text(memoryImportStatusLabel(batch))
                                    .font(.caption)
                                    .foregroundStyle(memoryImportStatusColor(batch))
                            }
                            Text(memoryDateTime(batch.startedAt))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text(memoryImportSummary(batch))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 3)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Імпорти")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            batches = try await MainProductAPI.shared.memoryImports()
            error = nil
        } catch {
            self.error = error
        }
    }
}

private struct MemoryImportDetailView: View {
    let batch: OrbitMemoryImportBatch

    var body: some View {
        List {
            Section("Джерело") {
                LabeledContent("Імпорт", value: "ChatGPT")
                LabeledContent("Стан", value: memoryImportStatusLabel(batch))
                LabeledContent("Початок", value: memoryDateTime(batch.startedAt))
                if let completedAt = batch.completedAt { LabeledContent("Завершено", value: memoryDateTime(completedAt)) }
            }
            Section("Підсумок") {
                LabeledContent("Розмов проаналізовано", value: String(batch.conversations))
                LabeledContent("Кандидатів у пам’ять", value: String(batch.candidates))
                LabeledContent("Додано або оновлено", value: String(batch.operationsCreated))
                if batch.duplicatesSkipped > 0 { LabeledContent("Дублікати пропущено", value: String(batch.duplicatesSkipped)) }
                if batch.credentialRejected > 0 { LabeledContent("Дані доступу не імпортовано", value: String(batch.credentialRejected)) }
                if batch.needsReview > 0 { LabeledContent("Потребує перевірки", value: String(batch.needsReview)) }
            }
            Section {
                Text("Orbit зберігає лише підсумок імпорту та походження пам’яті. Сирий архів не показується в застосунку.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Імпорт ChatGPT")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private func memoryImportStatusLabel(_ batch: OrbitMemoryImportBatch) -> String {
    switch batch.phase {
    case "analysis": "Аналіз"
    case "ready": "Готово до імпорту"
    case "applying": "Імпортується"
    case "completed": "Завершено"
    case "failed": "Помилка"
    default:
        switch batch.status {
        case "completed": "Завершено"
        case "failed": "Помилка"
        default: "Очікує"
        }
    }
}

private func memoryImportStatusColor(_ batch: OrbitMemoryImportBatch) -> Color {
    switch batch.phase {
    case "completed": .green
    case "failed": .red
    case "ready", "analysis", "applying": .orange
    default: .secondary
    }
}

private func memoryImportSummary(_ batch: OrbitMemoryImportBatch) -> String {
    if batch.phase == "completed" { return "\(batch.operationsCreated) змін у пам’яті · \(batch.duplicatesSkipped) дублікатів пропущено" }
    return "\(batch.conversations) розмов · \(batch.candidates) кандидатів у пам’ять"
}

private struct MemoryAssertionRow: View {
    let assertion: OrbitMemoryAssertion

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: assertion.status == "active" ? "brain.head.profile" : "clock.arrow.circlepath")
                .foregroundStyle(assertion.status == "active" ? .indigo : .secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(assertion.subjectName).font(.subheadline.weight(.semibold))
                Text(assertion.valueText).font(.body).lineLimit(2)
                HStack(spacing: 6) {
                    Text(memoryPredicateLabel(assertion.predicate))
                    Text("·")
                    Text(memoryStatusLabel(assertion.status))
                }
                .font(.caption)
                .foregroundStyle(assertion.status == "active" ? Color.secondary : Color.orange)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct MemoryAssertionDetailView: View {
    let assertion: OrbitMemoryAssertion
    let onCorrect: () -> Void

    var body: some View {
        List {
            Section {
                Text(assertion.valueText)
                    .font(.title3.weight(.medium))
                    .textSelection(.enabled)
            } header: {
                Text(memoryPredicateLabel(assertion.predicate))
            }
            Section("Стан") {
                LabeledContent("Статус", value: memoryStatusLabel(assertion.status))
                LabeledContent("Кому належить", value: assertion.subjectName)
                if let observedAt = assertion.observedAt { LabeledContent("Помічено", value: memoryDateTime(observedAt)) }
                if let validFrom = assertion.validFrom { LabeledContent("Дійсне від", value: memoryDate(validFrom)) }
                if let validTo = assertion.validTo { LabeledContent("Дійсне до", value: memoryDate(validTo)) }
            }
            if assertion.status == "superseded" {
                Section("Наступна інформація") {
                    if let successor = assertion.successor {
                        NavigationLink {
                            MemorySuccessorDetailView(successor: successor, subjectName: assertion.subjectName, predicate: assertion.predicate)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(successor.valueText).font(.body.weight(.medium))
                                Text(memoryStatusLabel(successor.status)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text("Новіше значення недоступне")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section("Походження") {
                LabeledContent("Джерело", value: memorySourceLabel(assertion.sourceType))
                if let timestamp = assertion.sourceTimestamp { LabeledContent("Дата джерела", value: memoryDateTime(timestamp)) }
                Text("Orbit зберігає історію змін, щоб старі відомості не ставали поточними непомітно.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if assertion.canCorrect {
                Section {
                    Button { onCorrect() } label: {
                        Label("Виправити цю інформацію", systemImage: "pencil")
                    }
                } footer: {
                    Text("Нова відповідь замінить цю як актуальну, а попередня залишиться в історії.")
                }
            }
        }
        .navigationTitle("Пам’ять")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MemorySuccessorDetailView: View {
    let successor: OrbitMemorySuccessor
    let subjectName: String
    let predicate: String

    var body: some View {
        List {
            Section {
                Text(successor.valueText)
                    .font(.title3.weight(.medium))
                    .textSelection(.enabled)
            } header: {
                Text(memoryPredicateLabel(predicate))
            }
            Section("Стан") {
                LabeledContent("Статус", value: memoryStatusLabel(successor.status))
                LabeledContent("Кому належить", value: subjectName)
                if let observedAt = successor.observedAt { LabeledContent("Помічено", value: memoryDateTime(observedAt)) }
                if let validFrom = successor.validFrom { LabeledContent("Дійсне від", value: memoryDate(validFrom)) }
                if let validTo = successor.validTo { LabeledContent("Дійсне до", value: memoryDate(validTo)) }
            }
        }
        .navigationTitle("Наступна інформація")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MemoryCorrectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let assertion: OrbitMemoryAssertion
    let onSave: (String) async throws -> Void
    @State private var correction = ""
    @State private var isSaving = false
    @State private var error: Error?

    var body: some View {
        NavigationStack {
            Form {
                Section("Поточна інформація") {
                    Text(assertion.valueText).foregroundStyle(.secondary)
                }
                Section("Правильна інформація") {
                    TextField("Введіть нове значення", text: $correction, axis: .vertical)
                        .lineLimit(2 ... 5)
                }
                Section {
                    Text("Orbit збереже нове значення як актуальне, а попереднє — як історію.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Виправити пам’ять")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Скасувати") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Зберегти") { Task { await save() } }
                        .disabled(correction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .alert("Не вдалося зберегти", isPresented: .constant(error != nil)) {
                Button("Гаразд") { error = nil }
            } message: { Text(error?.localizedDescription ?? "Спробуйте ще раз.") }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await onSave(correction.trimmingCharacters(in: .whitespacesAndNewlines))
            dismiss()
        } catch { self.error = error }
    }
}

private struct MemoryRelationshipRow: View {
    let relationship: OrbitMemoryRelationship
    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(relationship.subjectName) · \(relationship.relationType)").font(.subheadline.weight(.semibold))
                Text(relationship.objectName).foregroundStyle(.secondary)
            }
        } icon: { Image(systemName: "arrow.triangle.branch").foregroundStyle(.teal) }
    }
}

private struct MemoryEventRow: View {
    let event: OrbitMemoryEvent
    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(event.summary).font(.subheadline.weight(.semibold)).lineLimit(3)
                if let date = event.occurredFrom { Text(date, style: .date).font(.caption).foregroundStyle(.secondary) }
            }
        } icon: { Image(systemName: "calendar.badge.clock").foregroundStyle(.orange) }
    }
}

private func memorySearchEmptyDescription(showHistory: Bool) -> String {
    showHistory ? "Спробуйте інше слово або сховайте історичні записи." : "Спробуйте інше слово або увімкніть перегляд історії."
}

private func memoryDateTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "uk_UA")
    formatter.dateStyle = .long
    formatter.timeStyle = .short
    return formatter.string(from: date)
}

private func memoryDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "uk_UA")
    formatter.dateStyle = .long
    formatter.timeStyle = .none
    return formatter.string(from: date)
}

private func memoryPredicateLabel(_ predicate: String) -> String {
    switch predicate {
    case "preferred_drink", "preference": "Уподобання"
    case "grade", "school_class": "Освіта"
    case "job", "employer": "Робота"
    case "address", "home_address": "Дім"
    case "vehicle": "Автомобіль"
    default: predicate.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

private func memoryStatusLabel(_ status: String) -> String {
    switch status {
    case "active": "Актуальне"
    case "superseded": "Замінено новішою інформацією"
    case "retracted": "Відкликано"
    case "disputed": "Потребує уточнення"
    default: "Історичне"
    }
}

private func memorySourceLabel(_ source: String?) -> String {
    switch source {
    case "user_chat_message": "Розмова з Orbit"
    case "manual_confirmation": "Ручне уточнення"
    case "chatgpt_export": "Імпорт ChatGPT"
    case "tool/runtime_verified": "Підтверджена дія"
    default: "Orbit"
    }
}

struct OrbitSettingsView: View {
    @EnvironmentObject private var authentication: OrbitAuthentication
    @EnvironmentObject private var audioOptions: AudioOptions
    @State private var showingAudio = false
    @State private var serverOnline: Bool?
    @State private var showsChangeUserConfirmation = false
    @AppStorage("orbit.chat.showTimestamps") private var showChatTimestamps = false
    @AppStorage("orbit.chat.compact") private var compactChat = false
    @AppStorage("orbit.chat.haptics") private var chatHaptics = true
    @AppStorage("orbit.appearance") private var appearance = "system"

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
                Section("Чат") {
                    Toggle("Показувати час повідомлень", isOn: $showChatTimestamps)
                    Toggle("Компактний вигляд", isOn: $compactChat)
                    Toggle("Легкий відгук під час надсилання", isOn: $chatHaptics)
                    Text("Ці параметри діють лише на цьому iPhone.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Вигляд") {
                    Picker("Тема", selection: $appearance) {
                        Text("Системна").tag("system")
                        Text("Світла").tag("light")
                        Text("Темна").tag("dark")
                    }
                }
                Section("Пам’ять і приватність") {
                    NavigationLink { MemoryCenterView() } label: {
                        Label("Центр пам’яті", systemImage: "brain.head.profile")
                    }
                    Label("Пам’ять Orbit — активна", systemImage: "checkmark.circle")
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
