import PhotosUI
import SwiftUI
import UIKit
import Vision

private struct HomeworkOCRLine: Identifiable, Sendable {
    let id: Int
    let text: String
    let confidence: Double
    let region: HomeworkOCRRegion
}

private struct HomeworkOCRRegion: Sendable {
    let minX: Double
    let minY: Double
    let width: Double
    let height: Double
    var maxX: Double { minX + width }
    var maxY: Double { minY + height }
}

private struct HomeworkOCRMatch {
    let task: OrbitHomeworkTask
    let score: Double
    let line: HomeworkOCRLine
}

private struct HomeworkCalendarDay: Identifiable {
    let key: String
    let title: String
    var id: String { key }
}

@MainActor @Observable
private final class SchoolHomeworkStore {
    var children: [OrbitFamilyProfile] = []
    var childPersonId: String?
    var tasks: [OrbitHomeworkTask] = []
    var snapshots: [OrbitHomeworkSnapshot] = []
    var proposals: [OrbitHomeworkProposal] = []
    var loading = false
    var saving = false
    var error: String?
    var profilePersonId: String?
    var isChild: Bool
    private var loadRequest = UUID()

    init(profilePersonId: String?, isChild: Bool) { self.profilePersonId = profilePersonId; self.isChild = isChild; if isChild { childPersonId = profilePersonId } }

    func configure(profilePersonId: String?, isChild: Bool) {
        guard self.profilePersonId != profilePersonId || self.isChild != isChild else { return }
        self.profilePersonId = profilePersonId; self.isChild = isChild; childPersonId = isChild ? profilePersonId : nil
        tasks = []; snapshots = []; proposals = []; error = nil
    }

    func load() async {
        let requestID = UUID(); loadRequest = requestID
        loading = true; error = nil
        defer { if loadRequest == requestID { loading = false } }
        do {
            if isChild {
                guard let profilePersonId else { throw OrbitChatAPIError.notPaired }
                childPersonId = profilePersonId
            } else {
                children = try await MainProductAPI.shared.familyProfiles().filter(\.isMinor)
                if let current = childPersonId, children.contains(where: { $0.personId == current }) {} else { childPersonId = children.first?.personId }
            }
            guard let childPersonId else { tasks = []; snapshots = []; proposals = []; return }
            let taskResult = try await MainProductAPI.shared.schoolHomework(childPersonId: isChild ? nil : childPersonId)
            guard loadRequest == requestID else { return }
            tasks = taskResult.tasks
            if isChild { snapshots = []; proposals = [] }
            else {
                snapshots = (try? await MainProductAPI.shared.schoolHomeworkSnapshots(childPersonId: childPersonId))?.snapshots ?? []
                guard loadRequest == requestID else { return }
                proposals = (try? await MainProductAPI.shared.schoolHomeworkProposals(childPersonId: childPersonId))?.proposals ?? []
            }
        } catch {
            guard loadRequest == requestID else { return }
            self.error = "Не вдалося завантажити домашні завдання. Перевірте з’єднання й повторіть спробу."
        }
    }

    func uploadPhoto(_ data: Data, contentType: String, schoolYear: String?, calendarWeek: Int?, pageLabel: String?, clientRequestId: String) async throws -> OrbitHomeworkSnapshot {
        guard let childPersonId else { throw OrbitChatAPIError.invalidResponse }
        saving = true; defer { saving = false }
        let response = try await MainProductAPI.shared.uploadHomeworkPhoto(data, contentType: contentType, childPersonId: childPersonId, schoolYear: schoolYear, calendarWeek: calendarWeek, pageLabel: pageLabel, clientRequestId: clientRequestId)
        snapshots.removeAll { $0.id == response.snapshot.id }; snapshots.insert(response.snapshot, at: 0)
        return response.snapshot
    }

    func propose(snapshot: OrbitHomeworkSnapshot, subject: String, text: String, lessonDate: String?, dueDate: String?, changeKind: String = "new", matchedTaskId: String? = nil, expectedRevision: Int? = nil, sourceRegion: String, ocrConfidence: Double?, clientRequestId: String) async throws {
        guard let childPersonId else { throw OrbitChatAPIError.invalidResponse }
        var candidate: [String: Any] = ["subject": subject, "assignmentText": text, "sourceRegion": sourceRegion, "confidence": ["assignmentText": ocrConfidence ?? 0] as [String: Double]]
        candidate["lessonDate"] = lessonDate as Any? ?? NSNull(); candidate["dueDate"] = dueDate as Any? ?? NSNull()
        if let expectedRevision { candidate["expectedRevision"] = expectedRevision }
        try await MainProductAPI.shared.createHomeworkProposal(childPersonId: childPersonId, snapshotId: snapshot.id, changeKind: changeKind, matchedHomeworkId: matchedTaskId, candidate: candidate, clientRequestId: clientRequestId)
        await load()
    }

    func manual(subject: String, text: String, lessonDate: String?, dueDate: String?, clientRequestId: String) async throws {
        guard let childPersonId else { throw OrbitChatAPIError.invalidResponse }
        try await MainProductAPI.shared.createManualHomework(childPersonId: childPersonId, subject: subject, assignmentText: text, workKind: nil, lessonDate: lessonDate, dueDate: dueDate, clientRequestId: clientRequestId)
        await load()
    }

    func edit(_ task: OrbitHomeworkTask, subject: String, text: String, lessonDate: String?, dueDate: String?) async throws {
        guard let childPersonId else { throw OrbitChatAPIError.invalidResponse }
        try await MainProductAPI.shared.editHomework(id: task.id, childPersonId: childPersonId, subject: subject, assignmentText: text, workKind: task.workKind, lessonDate: lessonDate, dueDate: dueDate, revision: task.revision)
        await load()
    }

    func setProgress(_ task: OrbitHomeworkTask, status: String, help: Bool, note: String? = nil) async throws {
        try await MainProductAPI.shared.updateHomeworkProgress(id: task.id, status: status, helpRequested: help, note: note ?? task.progress.note, revision: task.progress.revision)
        await load()
    }

    func resolve(_ proposal: OrbitHomeworkProposal, accept: Bool) async throws {
        try await MainProductAPI.shared.resolveHomeworkProposal(id: proposal.id, decision: accept ? "accept" : "reject")
        await load()
    }
}

struct SchoolHomeworkView: View {
    let profilePersonId: String?
    let openBrain: () -> Void
    @ObservedObject private var permissionStore = OrbitPermissionStore.shared
    @State private var store: SchoolHomeworkStore
    @State private var tab = 0
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var cameraOpen = false
    @State private var photoData: Data?
    @State private var photoContentType = "image/jpeg"
    @State private var photoUploadRequestId = UUID().uuidString
    @State private var proposalRequestId = UUID().uuidString
    @State private var manualRequestId = UUID().uuidString
    @State private var photoSnapshot: OrbitHomeworkSnapshot?
    @State private var localOCR = ""
    @State private var ocrLines: [HomeworkOCRLine] = []
    @State private var selectedOCRLineIDs = Set<Int>()
    @State private var subject = ""
    @State private var assignment = ""
    @State private var lessonDate = ""
    @State private var dueDate = ""
    @State private var diarySchoolYear = ""
    @State private var diaryWeek = ""
    @State private var diaryPageLabel = ""
    @State private var changeKind = "new"
    @State private var matchedTaskId: String?
    @State private var showManual = false
    @State private var showReviewForm = false
    @State private var editingTask: OrbitHomeworkTask?
    @State private var searchText = ""
    @State private var noteDrafts: [String: String] = [:]
    @State private var selectedSnapshot: OrbitHomeworkSnapshot?
    @State private var brainSelectedTaskId: String?
    @State private var brainQuestion = ""
    @State private var brainAnswer: String?
    @State private var brainSending = false
    @State private var showBrainSendConfirmation = false
    @State private var selectedHomeworkDay: String?
    @State private var selectedHomeworkSubject: String?
    @State private var selectedProgressState: String?

    init(profilePersonId: String?, openBrain: @escaping () -> Void) {
        self.profilePersonId = profilePersonId; self.openBrain = openBrain
        _store = State(initialValue: SchoolHomeworkStore(profilePersonId: profilePersonId, isChild: false))
    }

    private var isChild: Bool { permissionStore.permissions?.isChild == true }
    private var canReview: Bool { permissionStore.allows(.homeworkReview) }
    private var canWriteProgress: Bool { permissionStore.allows(.homeworkProgress) }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Домашні завдання", selection: $tab) {
                Text("Завдання").tag(0); Text("Щоденник").tag(1); Text("School Brain").tag(2)
            }.pickerStyle(.segmented).padding(.horizontal).padding(.vertical, 10)
            Group {
                if let error = store.error {
                    ContentUnavailableView { Label("Тимчасово недоступно", systemImage: "wifi.exclamationmark") } description: { Text(error) } actions: { Button("Повторити") { Task { await store.load() } }.buttonStyle(.borderedProminent) }
                } else if store.loading && store.tasks.isEmpty {
                    ProgressView("Завантажуємо домашні завдання…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    switch tab {
                    case 0: tasksSurface
                    case 1: diarySurface
                    default: brainSurface
                    }
                }
            }
        }
        .navigationTitle("Домашні завдання")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(profilePersonId ?? "")-\(permissionStore.permissions?.actorClass ?? "unknown")") {
            store.configure(profilePersonId: profilePersonId, isChild: isChild)
            selectedHomeworkDay = nil; selectedHomeworkSubject = nil; selectedProgressState = nil
            brainSelectedTaskId = nil; brainAnswer = nil
            photoData = nil; photoSnapshot = nil; localOCR = ""; ocrLines = []; selectedOCRLineIDs = []
            await store.load()
        }
        .refreshable { await store.load() }
        .onChange(of: selectedPhoto) { _, photo in
            guard let photo else { return }
            Task { await loadPhoto(photo) }
        }
        .onChange(of: subject) { _, _ in if showReviewForm { proposalRequestId = UUID().uuidString }; if showManual && editingTask == nil { manualRequestId = UUID().uuidString } }
        .onChange(of: assignment) { _, _ in if showReviewForm { proposalRequestId = UUID().uuidString }; if showManual && editingTask == nil { manualRequestId = UUID().uuidString } }
        .onChange(of: lessonDate) { _, _ in if showReviewForm { proposalRequestId = UUID().uuidString }; if showManual && editingTask == nil { manualRequestId = UUID().uuidString } }
        .onChange(of: dueDate) { _, _ in if showReviewForm { proposalRequestId = UUID().uuidString }; if showManual && editingTask == nil { manualRequestId = UUID().uuidString } }
        .sheet(isPresented: $cameraOpen) {
            HomeworkCameraPicker { image in
                guard let image, let data = image.jpegData(compressionQuality: 0.88) else { return }
                Task { await preparePhoto(data, contentType: "image/jpeg") }
            }.ignoresSafeArea()
        }
        .sheet(isPresented: $showManual) { manualSheet }
        .sheet(isPresented: $showReviewForm) { reviewSheet }
        .sheet(item: $selectedSnapshot) { HomeworkSnapshotPreview(snapshot: $0) }
    }

    private var childPicker: some View {
        Group {
            if !isChild && store.children.count > 1 {
                Picker("Учень", selection: Binding(get: { store.childPersonId ?? "" }, set: { store.childPersonId = $0; Task { await store.load() } })) {
                    ForEach(store.children) { child in Text(child.displayName).tag(child.personId) }
                }.pickerStyle(.menu)
            } else if !isChild, let child = store.children.first { Text(child.displayName).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary) }
        }
    }

    private var tasksSurface: some View {
        List {
            Section { childPicker }
            Section("Календар") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        dayChip(title: "Усі дні", value: nil)
                        ForEach(homeworkCalendarDays) { day in dayChip(title: day.title, value: day.key) }
                        dayChip(title: "Без дати", value: "undated")
                    }.padding(.vertical, 2)
                }
                .accessibilityLabel("Вибір дня домашніх завдань")
            }
            Section("Фільтри") {
                Picker("Предмет", selection: $selectedHomeworkSubject) {
                    Text("Усі предмети").tag(String?.none)
                    ForEach(homeworkSubjects, id: \.self) { Text($0).tag(Optional($0)) }
                }
                Picker("Прогрес", selection: $selectedProgressState) {
                    Text("Будь-який").tag(String?.none)
                    Text("Не почато").tag(Optional("not_started"))
                    Text("Виконую").tag(Optional("in_progress"))
                    Text("Виконано").tag(Optional("completed"))
                    Text("Потрібна допомога").tag(Optional("needs_help"))
                }
            }
            if store.tasks.isEmpty {
                ContentUnavailableView("Завдань поки немає", systemImage: "books.vertical", description: Text("Порожній список не означає, що в щоденнику немає домашньої роботи."))
            }
            ForEach(filteredTasks) { task in
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text(task.subject).font(.headline); Spacer(); if task.reviewState == "needs_review" { Label("Уточнити", systemImage: "questionmark.circle").font(.caption).foregroundStyle(.orange) } }
                    Text(task.assignmentText).textSelection(.enabled)
                    HStack(spacing: 12) {
                        if let date = task.lessonDate { Label("Урок \(date)", systemImage: "calendar") }
                        if let date = task.dueDate { Label("Термін \(date)", systemImage: "clock") } else { Label("Термін невідомий", systemImage: "clock") }
                    }.font(.caption).foregroundStyle(.secondary)
                    if !canWriteProgress { Text(progressLabel(task.progress.status)).font(.caption.weight(.semibold)).foregroundStyle(task.progress.status == "needs_help" ? .orange : .secondary) }
                    if canWriteProgress {
                        Picker("Мій поступ", selection: Binding(get: { task.progress.status }, set: { value in Task { try? await store.setProgress(task, status: value, help: value == "needs_help") } })) {
                            Text("Не почато").tag("not_started"); Text("Виконую").tag("in_progress"); Text("Виконано").tag("completed"); Text("Потрібна допомога").tag("needs_help")
                        }.pickerStyle(.menu)
                        TextField("Моя нотатка", text: Binding(get: { noteDrafts[task.id] ?? task.progress.note }, set: { noteDrafts[task.id] = $0 }), axis: .vertical).lineLimit(1...3)
                        Button("Зберегти нотатку") { Task { do { try await store.setProgress(task, status: task.progress.status, help: task.progress.helpRequested, note: noteDrafts[task.id] ?? task.progress.note) } catch { store.error = "Не вдалося зберегти особисту нотатку." } } }.font(.caption)
                    }
                    if canReview { Button("Редагувати") { editingTask = task; subject = task.subject; assignment = task.assignmentText; lessonDate = task.lessonDate ?? ""; dueDate = task.dueDate ?? ""; showManual = true }.font(.caption) }
                }.padding(.vertical, 5)
            }
            if canReview { Section { Button { editingTask = nil; subject = ""; assignment = ""; lessonDate = ""; dueDate = ""; manualRequestId = UUID().uuidString; showManual = true } label: { Label("Додати завдання вручну", systemImage: "plus") } } }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "Предмет або завдання")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { Task { await store.load() } } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("Оновити завдання") } }
    }

    private var filteredTasks: [OrbitHomeworkTask] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.tasks.filter { task in
            let matchesQuery = query.isEmpty || task.subject.localizedCaseInsensitiveContains(query) || task.assignmentText.localizedCaseInsensitiveContains(query)
            let matchesSubject = selectedHomeworkSubject == nil || task.subject == selectedHomeworkSubject
            let matchesProgress = selectedProgressState == nil || task.progress.status == selectedProgressState
            let matchesDay: Bool
            if selectedHomeworkDay == "undated" { matchesDay = task.lessonDate == nil && task.dueDate == nil }
            else if let day = selectedHomeworkDay { matchesDay = task.lessonDate == day || task.dueDate == day }
            else { matchesDay = true }
            return matchesQuery && matchesSubject && matchesProgress && matchesDay
        }
    }

    private var homeworkSubjects: [String] { Array(Set(store.tasks.map(\.subject))).sorted() }

    private var homeworkCalendarDays: [HomeworkCalendarDay] {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: .now)
        let range = (-7...21).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
        let taskDates = store.tasks.flatMap { [$0.lessonDate, $0.dueDate] }.compactMap { $0 }.compactMap(Self.parseHomeworkDay)
        let dates = Array(Set(range + taskDates)).sorted()
        let keyFormatter = DateFormatter(); keyFormatter.calendar = calendar; keyFormatter.locale = Locale(identifier: "en_US_POSIX"); keyFormatter.dateFormat = "yyyy-MM-dd"
        let titleFormatter = DateFormatter(); titleFormatter.calendar = calendar; titleFormatter.locale = Locale(identifier: "uk_UA"); titleFormatter.dateFormat = "EE d MMM"
        return dates.map { HomeworkCalendarDay(key: keyFormatter.string(from: $0), title: titleFormatter.string(from: $0)) }
    }

    private func dayChip(title: String, value: String?) -> some View {
        let selected = selectedHomeworkDay == value
        return Button(title) { selectedHomeworkDay = value }
            .font(.caption.weight(selected ? .semibold : .regular))
            .padding(.horizontal, 11).padding(.vertical, 8)
            .background(selected ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
            .foregroundStyle(selected ? Color.white : Color.primary)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private static func parseHomeworkDay(_ value: String) -> Date? {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private func progressLabel(_ value: String) -> String {
        switch value { case "in_progress": "Учень: виконує"; case "completed": "Учень: виконано"; case "needs_help": "Учню потрібна допомога"; default: "Учень: не почато" }
    }

    private var diarySurface: some View {
        List {
            if canReview {
                Section("Додати фото щоденника") {
                    Text("Оригінал зберігається зашифрованим. OCR працює лише на цьому iPhone; перед підтвердженням перевірте текст і дати.").font(.footnote).foregroundStyle(.secondary)
                    TextField("Навчальний рік · напр. 2026/2027", text: $diarySchoolYear).textInputAutocapitalization(.never)
                    TextField("Тиждень щоденника · 1–53", text: $diaryWeek).keyboardType(.numberPad)
                    TextField("Позначка сторінки · необов’язково", text: $diaryPageLabel)
                    PhotosPicker(selection: $selectedPhoto, matching: .images) { Label("Вибрати з фототеки", systemImage: "photo") }
                    Button { cameraOpen = true } label: { Label("Зробити фото", systemImage: "camera") }
                    if let photoData {
                        HStack { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green); Text("Фото підготовлено · \(ByteCountFormatter.string(fromByteCount: Int64(photoData.count), countStyle: .file))"); Spacer(); Button("Очистити") { self.photoData = nil; photoSnapshot = nil; localOCR = ""; ocrLines = []; selectedOCRLineIDs = [] } }.font(.caption)
                        Button { Task { await uploadAndReview() } } label: { if store.saving { ProgressView() } else { Label("Зберегти фото й перевірити запис", systemImage: "lock.shield") } }.disabled(store.saving)
                    }
                    if !localOCR.isEmpty { Text("Розпізнано на пристрої; перевірте вручну").font(.caption.weight(.semibold)); Text(localOCR).font(.caption).textSelection(.enabled).lineLimit(8) }
                    if let match = bestOCRMatch {
                        Label("Можливо, це \(match.task.subject) · схожість \(Int(match.score * 100))%", systemImage: "arrow.triangle.2.circlepath").font(.caption).foregroundStyle(.secondary)
                        Text("Це лише підказка за текстом. Перевірте сторінку та виберіть нове, змінене, повторне або неоднозначне вручну.").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Section("Потребують перевірки") {
                    if store.proposals.isEmpty { Text("Немає записів для перевірки.").foregroundStyle(.secondary) }
                    ForEach(store.proposals) { proposal in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(proposal.candidate.subject).font(.headline)
                            if proposal.changeKind == "update", let previous = proposal.currentAssignmentText {
                                LabeledContent("Було", value: previous)
                                LabeledContent("Нова пропозиція", value: proposal.candidate.assignmentText)
                            } else {
                                Text(proposal.candidate.assignmentText).textSelection(.enabled)
                            }
                            Text(proposal.changeKind == "uncertain" ? "Неоднозначно — звірте з фото" : proposal.changeKind == "update" ? "Можлива зміна завдання" : proposal.changeKind == "same" ? "Можливий повтор" : "Нове завдання").font(.caption).foregroundStyle(.secondary)
                            if let confidence = proposal.candidate.confidence?["assignmentText"] { Text("Впевненість OCR: \(Int(confidence * 100))%").font(.caption2).foregroundStyle(.secondary) }
                            if let region = proposal.candidate.sourceRegion { Text("Фрагмент джерела: \(region)").font(.caption2).foregroundStyle(.secondary).textSelection(.enabled) }
                            if let source = store.snapshots.first(where: { $0.id == proposal.snapshotId }) { Button("Переглянути фото джерела") { selectedSnapshot = source }.font(.caption) }
                            HStack { Button("Відхилити") { Task { try? await store.resolve(proposal, accept: false) } }.buttonStyle(.bordered); Button("Підтвердити") { Task { try? await store.resolve(proposal, accept: true) } }.buttonStyle(.borderedProminent).disabled(proposal.changeKind == "uncertain") }
                        }.padding(.vertical, 5)
                    }
                }
                Section("Збережені сторінки") {
                    if store.snapshots.isEmpty { Text("Фото ще не додавали.").foregroundStyle(.secondary) }
                    ForEach(store.snapshots) { item in Button { selectedSnapshot = item } label: { Label("\(item.pageLabel ?? "Сторінка") · \(item.capturedAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "doc.text.image") } }
                }
            } else {
                ContentUnavailableView("Джерела щоденника доступні батькам", systemImage: "lock", description: Text("Тут відображаються підтверджені домашні завдання."))
            }
        }.listStyle(.insetGrouped)
    }

    private var brainSurface: some View {
        List {
            Section {
                Label("Навчальна допомога працює через School Brain Orbit", systemImage: "brain.head.profile").font(.headline)
                Text("Надсилайте до наявного School Brain лише вибране підтверджене завдання. Фото й нерозглянутий OCR не передаються. Запит обробляється налаштованим AI-провайдером Orbit; відповідь є підказкою, а не шкільним фактом.").font(.footnote).foregroundStyle(.secondary)
                Picker("Підтверджене завдання", selection: $brainSelectedTaskId) {
                    Text("Без завдання").tag(String?.none)
                    ForEach(store.tasks.filter { $0.reviewState == "confirmed" }) { task in
                        Text("\(task.subject): \(task.assignmentText.prefix(48))").tag(Optional(task.id))
                    }
                }
                TextField("Про що запитати?", text: $brainQuestion, axis: .vertical).lineLimit(2...5)
                Button { showBrainSendConfirmation = true } label: {
                    if brainSending { ProgressView("Надсилаємо запит…") }
                    else { Label("Запитати School Brain", systemImage: "paperplane") }
                }.buttonStyle(.borderedProminent).disabled(brainSending || brainQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .confirmationDialog("Надіслати до School Brain?", isPresented: $showBrainSendConfirmation, titleVisibility: .visible) {
                        Button("Надіслати підтверджений текст") { Task { await askBrain() } }
                        Button("Скасувати", role: .cancel) {}
                    } message: {
                        Text(brainConfirmationText)
                    }
                if let brainAnswer { Text(brainAnswer).textSelection(.enabled).padding(.top, 4) }
                Button { openBrain() } label: { Label("Відкрити розмову School Brain", systemImage: "arrow.up.right") }.buttonStyle(.bordered)
            }
            Section("Підтверджені записи") {
                if store.tasks.isEmpty { Text("Підтверджених завдань поки немає.").foregroundStyle(.secondary) }
                ForEach(store.tasks) { task in Text("\(task.subject): \(task.assignmentText)").textSelection(.enabled) }
            }
            Section { Text("Фото та нерозглянуті пропозиції залишаються в цьому розділі й не передаються до Brain автоматично.").font(.caption).foregroundStyle(.secondary) }
        }.listStyle(.insetGrouped)
    }

    private var selectedBrainTask: OrbitHomeworkTask? {
        brainSelectedTaskId.flatMap { id in store.tasks.first { $0.id == id && $0.reviewState == "confirmed" } }
    }

    private var brainConfirmationText: String {
        let taskText = selectedBrainTask.map { " Додасться завдання «\($0.subject): \($0.assignmentText)»." } ?? ""
        return "До наявного Orbit School Brain буде надіслано ваше запитання.\(taskText) Фото та OCR не надсилатимуться."
    }

    private func askBrain() async {
        let question = brainQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        let selected = selectedBrainTask
        let credentialLike = #"(?i)(password|passwort|kennwort|парол\w*|\bpin\b|access\s*code|zugangscode)"#
        let content: String
        if let selected {
            guard "\(selected.subject) \(selected.assignmentText) \(question)".range(of: credentialLike, options: .regularExpression) == nil else {
                brainAnswer = "Запит не надіслано: схоже, він містить пароль або код доступу. Видаліть його й спробуйте знову."
                return
            }
            content = "Підтверджене домашнє завдання: \(selected.subject) — \(selected.assignmentText)\n\nЗапит учня/батьків: \(question)\n\nВикористовуй це лише як контекст для навчальної підказки. Не змінюй завдання, не вигадуй дедлайн і познач невизначеність."
        } else {
            guard question.range(of: credentialLike, options: .regularExpression) == nil else {
                brainAnswer = "Запит не надіслано: схоже, він містить пароль або код доступу. Видаліть його й спробуйте знову."
                return
            }
            content = question
        }
        brainSending = true; defer { brainSending = false }
        do {
            let message = try await MainProductAPI.shared.askSchool(content)
            brainAnswer = message.content
        } catch {
            brainAnswer = "School Brain тимчасово недоступний. Перевірте з’єднання й повторіть спробу."
        }
    }

    private var manualSheet: some View {
        HomeworkEntryForm(title: editingTask == nil ? "Нове завдання" : "Редагувати завдання", subject: $subject, assignment: $assignment, lessonDate: $lessonDate, dueDate: $dueDate, saving: store.saving) {
            Task { do {
                if let editingTask { try await store.edit(editingTask, subject: subject, text: assignment, lessonDate: lessonDate.nilIfEmpty, dueDate: dueDate.nilIfEmpty) }
                else { try await store.manual(subject: subject, text: assignment, lessonDate: lessonDate.nilIfEmpty, dueDate: dueDate.nilIfEmpty, clientRequestId: manualRequestId) }
                showManual = false; self.editingTask = nil; subject = ""; assignment = ""; lessonDate = ""; dueDate = ""; manualRequestId = UUID().uuidString
            } catch { store.error = "Не вдалося зберегти завдання." } }
        }.presentationDetents([.medium, .large])
    }

    private var reviewSheet: some View {
        NavigationStack {
            Form {
                if !ocrLines.isEmpty {
                    Section("Виберіть рядки з потрібним завданням") {
                        ForEach(ocrLines) { line in
                            Button { toggleOCRLine(line) } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: selectedOCRLineIDs.contains(line.id) ? "checkmark.circle.fill" : "circle")
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(line.text).textSelection(.enabled).foregroundStyle(.primary)
                                        Text("OCR · \(Int(line.confidence * 100))% · фрагмент \(Int(line.region.minX * 100))%, \(Int(line.region.minY * 100))%").font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                }
                Picker("Порівняння", selection: $changeKind) { Text("Нове завдання").tag("new"); Text("Зміна наявного").tag("update"); Text("Той самий запис").tag("same"); Text("Не впевнений").tag("uncertain") }
                if changeKind != "new" {
                    Picker("Існуюче завдання", selection: $matchedTaskId) {
                        Text("Виберіть завдання").tag(String?.none)
                        ForEach(store.tasks) { task in Text("\(task.subject): \(task.assignmentText.prefix(50))").tag(Optional(task.id)) }
                    }
                }
                if let matchedTask = matchedTaskId.flatMap({ id in store.tasks.first { $0.id == id } }) {
                    Section("Порівняння з підтвердженим записом") {
                        LabeledContent("Було", value: matchedTask.assignmentText)
                        LabeledContent("Зараз розпізнано", value: assignment)
                        Text("Перевірте обидва тексти за фото. Зміна буде лише пропозицією до підтвердження.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                TextField("Предмет", text: $subject)
                TextField("Завдання з фото", text: $assignment, axis: .vertical).lineLimit(3...8).textSelection(.enabled)
                TextField("Дата уроку · РРРР-ММ-ДД", text: $lessonDate).textInputAutocapitalization(.never)
                TextField("Підтверджений термін · РРРР-ММ-ДД", text: $dueDate).textInputAutocapitalization(.never)
                Text("OCR — лише підказка. Перевірте оригінал і не вводьте паролі або коди доступу.").font(.footnote).foregroundStyle(.secondary)
            }.navigationTitle("Перевірити запис").navigationBarTitleDisplayMode(.inline).toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Скасувати") { showReviewForm = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("На перевірку") { submitPhotoProposal() }.disabled(store.saving || subject.isEmpty || assignment.isEmpty || (changeKind != "new" && matchedTaskId == nil))
                }
            }
        }.presentationDetents([.medium, .large])
    }

    private func submitPhotoProposal() {
        guard let photoSnapshot else { return }
        let matched = matchedTaskId.flatMap { id in store.tasks.first { $0.id == id } }
        Task { do {
            let selectedLines = ocrLines.filter { selectedOCRLineIDs.contains($0.id) }
            let region: String
            if let first = selectedLines.first {
                let minX = selectedLines.map { $0.region.minX }.min() ?? first.region.minX
                let minY = selectedLines.map { $0.region.minY }.min() ?? first.region.minY
                let maxX = selectedLines.map { $0.region.maxX }.max() ?? first.region.maxX
                let maxY = selectedLines.map { $0.region.maxY }.max() ?? first.region.maxY
                region = String(format: "vision-unit-rect:%.4f,%.4f,%.4f,%.4f", minX, minY, maxX - minX, maxY - minY)
            } else { region = "parent-entered; source=full-page" }
            let confidence = selectedLines.isEmpty ? nil : selectedLines.map(\.confidence).reduce(0, +) / Double(selectedLines.count)
            try await store.propose(snapshot: photoSnapshot, subject: subject, text: assignment, lessonDate: lessonDate.nilIfEmpty, dueDate: dueDate.nilIfEmpty, changeKind: changeKind, matchedTaskId: matched?.id, expectedRevision: matched?.revision, sourceRegion: region, ocrConfidence: confidence, clientRequestId: proposalRequestId)
            showReviewForm = false; photoData = nil; self.photoSnapshot = nil; selectedOCRLineIDs = []; changeKind = "new"; matchedTaskId = nil; photoUploadRequestId = UUID().uuidString; proposalRequestId = UUID().uuidString
        } catch { store.error = "Не вдалося надіслати запис на батьківське підтвердження." } }
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self), UIImage(data: data) != nil, let type = Self.photoType(data) else { return }
        await preparePhoto(data, contentType: type)
    }

    private func preparePhoto(_ data: Data, contentType: String) async {
        photoData = data; photoContentType = contentType; photoSnapshot = nil; photoUploadRequestId = UUID().uuidString; proposalRequestId = UUID().uuidString; ocrLines = []; selectedOCRLineIDs = []
        guard let image = UIImage(data: data), let cgImage = image.cgImage else { localOCR = "Не вдалося прочитати фото. Запис можна додати вручну."; return }
        let recognized = await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate; request.usesLanguageCorrection = false
            request.recognitionLanguages = ["de-DE", "uk-UA"]
            do {
                try VNImageRequestHandler(cgImage: cgImage).perform([request])
                return (request.results ?? []).enumerated().compactMap { index, observation -> HomeworkOCRLine? in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    let box = observation.boundingBox
                    return HomeworkOCRLine(id: index, text: candidate.string, confidence: Double(candidate.confidence), region: HomeworkOCRRegion(minX: Double(box.minX), minY: Double(box.minY), width: Double(box.width), height: Double(box.height)))
                }
            } catch { return [HomeworkOCRLine]() }
        }.value
        ocrLines = recognized
        localOCR = recognized.map(\.text).joined(separator: "\n")
        if recognized.isEmpty { localOCR = "Не вдалося розпізнати текст. Запис можна додати вручну." }
        let matches = rankedOCRMatches
        if let match = matches.first, match.score >= 0.35 {
            let ambiguous = matches.dropFirst().first.map { match.score - $0.score < 0.12 && $0.score >= 0.4 } ?? false
            if ambiguous {
                matchedTaskId = nil; changeKind = "uncertain"
            } else if match.score >= 0.9 {
                matchedTaskId = match.task.id; changeKind = "same"
            } else if match.score >= 0.55 {
                matchedTaskId = match.task.id; changeKind = "uncertain"
            } else {
                matchedTaskId = nil; changeKind = "new"
            }
        } else {
            matchedTaskId = nil; changeKind = "new"
        }
    }

    private var rankedOCRMatches: [HomeworkOCRMatch] {
        let candidates = ocrLines.flatMap { line in
            store.tasks.filter { $0.reviewState == "confirmed" }.map { task -> HomeworkOCRMatch in
                HomeworkOCRMatch(task: task, score: SchoolHomeworkTextMatcher.similarity(line.text, task.assignmentText), line: line)
            }
        }
        return candidates.sorted { $0.score > $1.score }
    }

    private var bestOCRMatch: HomeworkOCRMatch? {
        rankedOCRMatches.first.flatMap { $0.score >= 0.35 ? $0 : nil }
    }

    private func toggleOCRLine(_ line: HomeworkOCRLine) {
        if selectedOCRLineIDs.contains(line.id) { selectedOCRLineIDs.remove(line.id) }
        else { selectedOCRLineIDs.insert(line.id) }
        assignment = ocrLines.filter { selectedOCRLineIDs.contains($0.id) }.map(\.text).joined(separator: "\n")
    }

    private static func photoType(_ data: Data) -> String? {
        let bytes = [UInt8](data.prefix(12))
        if bytes.count >= 3 && bytes[0] == 0xff && bytes[1] == 0xd8 && bytes[2] == 0xff { return "image/jpeg" }
        if bytes.count >= 8 && Array(bytes.prefix(8)) == [0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a] { return "image/png" }
        if bytes.count >= 12 && String(bytes: bytes[4..<8], encoding: .ascii) == "ftyp", let brand = String(bytes: bytes[8..<12], encoding: .ascii), ["heic","heix","mif1","heif"].contains(brand) { return "image/heic" }
        return nil
    }

    private func uploadAndReview() async {
        guard let photoData else { return }
        do {
            photoSnapshot = try await store.uploadPhoto(photoData, contentType: photoContentType, schoolYear: diarySchoolYear.nilIfEmpty, calendarWeek: Int(diaryWeek), pageLabel: diaryPageLabel.nilIfEmpty, clientRequestId: photoUploadRequestId)
            if let match = bestOCRMatch, changeKind != "uncertain" {
                assignment = match.line.text
                selectedOCRLineIDs = [match.line.id]
            } else {
                assignment = ""
                selectedOCRLineIDs = []
            }
            subject = ""
            showReviewForm = true
        } catch { store.error = "Фото не збережено. Перевірте з’єднання та спробуйте ще раз." }
    }
}

private struct HomeworkSnapshotPreview: View {
    let snapshot: OrbitHomeworkSnapshot
    @State private var image: UIImage?
    @State private var failed = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Group {
                if let image { Image(uiImage: image).resizable().scaledToFit().padding() }
                else if failed { ContentUnavailableView("Фото тимчасово недоступне", systemImage: "photo.badge.exclamationmark") }
                else { ProgressView("Завантажуємо захищене фото…") }
            }.navigationTitle(snapshot.pageLabel ?? "Щоденник").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }.task {
            do { image = UIImage(data: try await MainProductAPI.shared.downloadHomeworkPhoto(id: snapshot.id, childPersonId: snapshot.childPersonId)); failed = image == nil }
            catch { failed = true }
        }
    }
}

private struct HomeworkEntryForm: View {
    let title: String
    @Binding var subject: String
    @Binding var assignment: String
    @Binding var lessonDate: String
    @Binding var dueDate: String
    let saving: Bool
    let save: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("Предмет", text: $subject)
                TextField("Завдання", text: $assignment, axis: .vertical).lineLimit(3...8).textSelection(.enabled)
                TextField("Дата уроку · РРРР-ММ-ДД (необов’язково)", text: $lessonDate).textInputAutocapitalization(.never)
                TextField("Підтверджений термін · РРРР-ММ-ДД", text: $dueDate).textInputAutocapitalization(.never)
                Text("Не вказуйте термін, якщо його немає в джерелі. Паролі та коди доступу сюди не вводьте.").font(.footnote).foregroundStyle(.secondary)
            }.navigationTitle(title).navigationBarTitleDisplayMode(.inline).toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Скасувати") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Зберегти") { save() }.disabled(saving || subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || assignment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
        }
    }
}

private struct HomeworkCameraPicker: UIViewControllerRepresentable {
    let completion: (UIImage?) -> Void
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController(); picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary; picker.delegate = context.coordinator; return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let completion: (UIImage?) -> Void
        init(completion: @escaping (UIImage?) -> Void) { self.completion = completion }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) { completion(info[.originalImage] as? UIImage); picker.dismiss(animated: true) }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { completion(nil); picker.dismiss(animated: true) }
    }
}

private extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }
