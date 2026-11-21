import PhotosUI
import SwiftUI
import UIKit
import Vision

private typealias HomeworkOCRLine = SchoolHomeworkOCRLine
private typealias HomeworkOCRRegion = SchoolHomeworkOCRRegion

private struct HomeworkReviewCandidate: Identifiable, Equatable {
    let id: Int
    var subject: String
    var assignmentText: String
    var lessonDate: String?
    var dueDate: String?
    var sourceLineIDs: [Int]
    var sourceRegion: HomeworkOCRRegion
    var confidence: [String: Double]
    var needsReview: Bool
    var reviewReason: String?
    var changeKind: String
    var matchedTaskId: String?
    var matchScore: Double
    var pendingDuplicate: Bool
    var selected: Bool
    var clientRequestId: String
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

    func propose(snapshot: OrbitHomeworkSnapshot, subject: String, text: String, lessonDate: String?, dueDate: String?, changeKind: String = "new", matchedTaskId: String? = nil, expectedRevision: Int? = nil, sourceRegion: String, confidence: [String: Double], clientRequestId: String) async throws {
        guard let childPersonId else { throw OrbitChatAPIError.invalidResponse }
        var candidate: [String: Any] = ["subject": subject, "assignmentText": text, "sourceRegion": sourceRegion, "confidence": confidence]
        candidate["lessonDate"] = lessonDate as Any? ?? NSNull(); candidate["dueDate"] = dueDate as Any? ?? NSNull()
        if let expectedRevision { candidate["expectedRevision"] = expectedRevision }
        try await MainProductAPI.shared.createHomeworkProposal(childPersonId: childPersonId, snapshotId: snapshot.id, changeKind: changeKind, matchedHomeworkId: matchedTaskId, candidate: candidate, clientRequestId: clientRequestId)
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
    @State private var manualRequestId = UUID().uuidString
    @State private var photoSnapshot: OrbitHomeworkSnapshot?
    @State private var diaryAnalysis = SchoolHomeworkDiaryAnalysis(schoolYear: nil, calendarWeek: nil, pageLabel: nil, entries: [])
    @State private var reviewEntries: [HomeworkReviewCandidate] = []
    @State private var subject = ""
    @State private var assignment = ""
    @State private var lessonDate = ""
    @State private var dueDate = ""
    @State private var diarySchoolYear = ""
    @State private var diaryWeek = ""
    @State private var diaryPageLabel = ""
    @State private var showManual = false
    @State private var showReviewForm = false
    @State private var submittingPhotoReview = false
    @State private var confirmObviousProposals = false
    @State private var showAllHomeworkMatches = false
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
            brainSelectedTaskId = nil; brainQuestion = ""; brainAnswer = nil
            photoData = nil; photoSnapshot = nil; selectedSnapshot = nil
            subject = ""; assignment = ""; lessonDate = ""; dueDate = ""
            noteDrafts = [:]; editingTask = nil; showManual = false; showReviewForm = false; cameraOpen = false
            selectedPhoto = nil; showBrainSendConfirmation = false
            await store.load()
        }
        .refreshable { await store.load() }
        .onChange(of: selectedPhoto) { _, photo in
            guard let photo else { return }
            Task { await loadPhoto(photo) }
        }
        .onChange(of: subject) { _, _ in if showManual && editingTask == nil { manualRequestId = UUID().uuidString } }
        .onChange(of: assignment) { _, _ in if showManual && editingTask == nil { manualRequestId = UUID().uuidString } }
        .onChange(of: lessonDate) { _, _ in if showManual && editingTask == nil { manualRequestId = UUID().uuidString } }
        .onChange(of: dueDate) { _, _ in if showManual && editingTask == nil { manualRequestId = UUID().uuidString } }
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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                childPicker.padding(.horizontal, 4)
                progressSummary
                VStack(alignment: .leading, spacing: 9) {
                    Label("План за днями", systemImage: "calendar").font(.headline)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            dayChip(title: "Усі дні", value: nil)
                            ForEach(homeworkCalendarDays) { day in dayChip(title: day.title, value: day.key) }
                            dayChip(title: "Без дати", value: "undated")
                        }
                    }
                    .accessibilityLabel("Вибір дня домашніх завдань")
                }
                HStack(spacing: 12) {
                    Picker("Предмет", selection: $selectedHomeworkSubject) {
                        Text("Усі предмети").tag(String?.none)
                        ForEach(homeworkSubjects, id: \.self) { Text($0).tag(Optional($0)) }
                    }.pickerStyle(.menu)
                    Picker("Прогрес", selection: $selectedProgressState) {
                        Text("Будь-який статус").tag(String?.none)
                        Text("Не почато").tag(Optional("not_started"))
                        Text("Виконую").tag(Optional("in_progress"))
                        Text("Виконано").tag(Optional("completed"))
                        Text("Потрібна допомога").tag(Optional("needs_help"))
                    }.pickerStyle(.menu)
                    Spacer(minLength: 0)
                }
                if filteredTasks.isEmpty {
                    ContentUnavailableView {
                        Label(store.tasks.isEmpty ? "Домашніх завдань ще немає" : "За цим фільтром порожньо", systemImage: "books.vertical")
                    } description: {
                        Text("Порожній список не означає, що в щоденнику немає домашньої роботи.")
                    } actions: {
                        if canReview { Button("Сфотографувати щоденник") { tab = 1 }.buttonStyle(.borderedProminent) }
                    }
                    .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    ForEach(homeworkTaskDayKeys, id: \.self) { day in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(day == "undated" ? "Дату ще не визначено" : homeworkDayTitle(day))
                                .font(.headline)
                            ForEach(filteredTasks.filter { homeworkGroupKey(for: $0) == day }) { task in homeworkTaskCard(task) }
                        }
                    }
                }
                if canReview {
                    Button { editingTask = nil; subject = ""; assignment = ""; lessonDate = ""; dueDate = ""; manualRequestId = UUID().uuidString; showManual = true } label: {
                        Label("Додати завдання вручну", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered)
                }
            }
            .padding(16)
        }
        .searchable(text: $searchText, prompt: "Предмет або завдання")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { Task { await store.load() } } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("Оновити завдання") } }
    }

    private var progressSummary: some View {
        let relevant = filteredTasks
        let done = relevant.filter { $0.progress.status == "completed" }.count
        return HStack(spacing: 16) {
            ZStack {
                Circle().stroke(Color.accentColor.opacity(0.16), lineWidth: 8)
                Circle().trim(from: 0, to: relevant.isEmpty ? 0 : CGFloat(done) / CGFloat(relevant.count))
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 1) {
                    Text("\(done)/\(relevant.count)").font(.headline.monospacedDigit())
                    Text("готово").font(.caption2).foregroundStyle(.secondary)
                }
            }.frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 5) {
                Text(selectedHomeworkDay.map { homeworkDayTitle($0) } ?? "План домашніх завдань")
                    .font(.headline)
                Text(relevant.isEmpty ? "Нові записи з’являться тут після перевірки батьками." : "Щоденник, прогрес і джерела — в одному місці.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Label("Прогрес учня окремо від запису в щоденнику", systemImage: "checkmark.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func homeworkTaskCard(_ task: OrbitHomeworkTask) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Text(SchoolHubLogic.subjectAbbreviation(task.subject))
                    .font(.caption.weight(.bold)).frame(minWidth: 38, minHeight: 34)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 5) {
                    HStack { Text(task.subject).font(.subheadline.weight(.semibold)); Spacer(); if task.reviewState == "needs_review" { Label("Уточнити", systemImage: "questionmark.circle").font(.caption).foregroundStyle(.orange) } }
                    Text(task.assignmentText).textSelection(.enabled)
                    HStack(spacing: 12) {
                        if let due = task.dueDate { Label("Здати до \(homeworkDayTitle(due))", systemImage: "clock") }
                        else { Label("Термін не вказаний", systemImage: "clock") }
                    }.font(.caption).foregroundStyle(.secondary)
                }
            }
            if canWriteProgress {
                HStack {
                    Picker("Мій прогрес", selection: Binding(get: { task.progress.status }, set: { value in Task { try? await store.setProgress(task, status: value, help: value == "needs_help") } })) {
                        Text("Не почато").tag("not_started"); Text("Виконую").tag("in_progress"); Text("Виконано").tag("completed"); Text("Потрібна допомога").tag("needs_help")
                    }.pickerStyle(.menu)
                    Spacer()
                    if canReview { Button("Змінити") { beginEdit(task) }.font(.caption) }
                }
                TextField("Особиста нотатка", text: Binding(get: { noteDrafts[task.id] ?? task.progress.note }, set: { noteDrafts[task.id] = $0 }), axis: .vertical).lineLimit(1...3)
                Button("Зберегти нотатку") { Task { do { try await store.setProgress(task, status: task.progress.status, help: task.progress.helpRequested, note: noteDrafts[task.id] ?? task.progress.note) } catch { store.error = "Не вдалося зберегти особисту нотатку." } } }.font(.caption)
            } else {
                HStack {
                    Label(progressLabel(task.progress.status), systemImage: task.progress.status == "completed" ? "checkmark.circle.fill" : "circle")
                        .font(.caption.weight(.semibold)).foregroundStyle(task.progress.status == "needs_help" ? .orange : .secondary)
                    Spacer()
                    if canReview { Button("Редагувати") { beginEdit(task) }.font(.caption) }
                }
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func beginEdit(_ task: OrbitHomeworkTask) {
        editingTask = task; subject = task.subject; assignment = task.assignmentText
        lessonDate = task.lessonDate ?? ""; dueDate = task.dueDate ?? ""; showManual = true
    }

    private var homeworkTaskDayKeys: [String] {
        Array(Set(filteredTasks.map(homeworkGroupKey(for:)))).sorted { left, right in
            if left == "undated" { return false }
            if right == "undated" { return true }
            return left < right
        }
    }

    private func homeworkGroupKey(for task: OrbitHomeworkTask) -> String {
        if selectedHomeworkDay == "undated" { return "undated" }
        return task.lessonDate ?? task.dueDate ?? "undated"
    }

    private func homeworkDayTitle(_ value: String) -> String {
        guard let date = Self.parseHomeworkDay(value) else { return value }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "uk_UA"); formatter.dateFormat = "EEEE, d MMMM"
        return formatter.string(from: date).capitalized
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
        Group {
            if !canReview {
                ContentUnavailableView("Джерела щоденника доступні батькам", systemImage: "lock", description: Text("Тут відображаються підтверджені домашні завдання."))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("Фото → завдання → ваша перевірка").font(.title3.weight(.bold))
                            Text("Orbit читає дати й предмети на цьому iPhone. Фото та невпевнений текст не надсилаються до School Brain.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                                    Label("Вибрати фото", systemImage: "photo.on.rectangle.angled").frame(maxWidth: .infinity)
                                }.buttonStyle(.borderedProminent)
                                Button { cameraOpen = true } label: {
                                    Label("Камера", systemImage: "camera").frame(maxWidth: .infinity)
                                }.buttonStyle(.bordered)
                            }
                            if let photoData, let image = UIImage(data: photoData) {
                                HStack(alignment: .top, spacing: 13) {
                                    Image(uiImage: image).resizable().scaledToFill().frame(width: 86, height: 116).clipped().clipShape(RoundedRectangle(cornerRadius: 12))
                                    VStack(alignment: .leading, spacing: 7) {
                                        Label("Розпізнано на пристрої", systemImage: "text.viewfinder").font(.subheadline.weight(.semibold))
                                        Text(recognitionSummary).font(.caption).foregroundStyle(.secondary)
                                        Button("Зняти це фото") { clearPhotoDraft() }.font(.caption)
                                    }
                                }
                                HStack(spacing: 10) {
                                    TextField("Навчальний рік", text: $diarySchoolYear).textInputAutocapitalization(.never).textFieldStyle(.roundedBorder)
                                    TextField("KW", text: $diaryWeek).keyboardType(.numberPad).textFieldStyle(.roundedBorder).frame(width: 74)
                                }
                                TextField("Сторінка (можна виправити)", text: $diaryPageLabel).textFieldStyle(.roundedBorder)
                                Button { showReviewForm = true } label: {
                                    Label("Перевірити розпізнані записи", systemImage: "arrow.triangle.2.circlepath").frame(maxWidth: .infinity)
                                }.buttonStyle(.borderedProminent).disabled(reviewEntries.isEmpty)
                                if reviewEntries.isEmpty {
                                    Button("Додати завдання вручну") { subject = ""; assignment = ""; lessonDate = ""; dueDate = ""; editingTask = nil; manualRequestId = UUID().uuidString; showManual = true }
                                        .buttonStyle(.bordered)
                                }
                                Text("Лише після цієї дії фото буде збережене у приватному зашифрованому щоденнику Orbit. Канонічні завдання зміняться тільки після вашого підтвердження.")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .padding(15)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))

                        if !pendingProposals.isEmpty {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Перевірка батьків").font(.headline)
                                    Text("Очікують рішення: \(pendingProposals.count)").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if !obviousPendingProposals.isEmpty {
                                    Button("Підтвердити очевидні · \(obviousPendingProposals.count)") { confirmObviousProposals = true }
                                        .font(.caption.weight(.semibold))
                                }
                            }
                            ForEach(pendingProposals) { proposal in homeworkProposalCard(proposal) }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Збережені сторінки").font(.headline)
                            if store.snapshots.isEmpty {
                                Text("Після першого фото тут з’явиться історія сторінок.").font(.subheadline).foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(15)
                                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                            } else {
                                ForEach(store.snapshots) { item in
                                    Button { selectedSnapshot = item } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: "book.closed").font(.title3).foregroundStyle(.tint).frame(width: 42, height: 46).background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(item.pageLabel ?? "Щоденник · KW \(item.calendarWeek.map(String.init) ?? "—")").font(.subheadline.weight(.semibold))
                                                Text([item.schoolYear, item.calendarWeek.map { "KW \($0)" }, item.capturedAt.formatted(date: .abbreviated, time: .shortened)].compactMap { $0 }.joined(separator: " · "))
                                                    .font(.caption).foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                                        }
                                        .padding(12).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 15))
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                        Label("Приватність: фото зашифроване; OCR локальний; School Brain бачить лише текст, який ви виберете й підтвердите окремо.", systemImage: "lock.shield")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(16)
                }
                .confirmationDialog("Підтвердити очевидні записи?", isPresented: $confirmObviousProposals, titleVisibility: .visible) {
                    Button("Підтвердити \(obviousPendingProposals.count) записів") { Task { await confirmObvious() } }
                    Button("Скасувати", role: .cancel) {}
                } message: {
                    Text("Це змінить канонічні завдання для вибраного учня. Неоднозначні записи залишаться для окремої перевірки.")
                }
            }
        }
    }

    private var pendingProposals: [OrbitHomeworkProposal] {
        store.proposals.filter { $0.decision == "pending" }.sorted { ($0.candidate.lessonDate ?? "9999") < ($1.candidate.lessonDate ?? "9999") }
    }

    private var obviousPendingProposals: [OrbitHomeworkProposal] {
        pendingProposals.filter { proposal in
            proposal.changeKind != "uncertain" && proposal.candidate.lessonDate != nil &&
            (proposal.candidate.confidence?["assignmentText"] ?? 0) >= 0.85 &&
            (proposal.candidate.confidence?["subject"] ?? 0) >= 0.85
        }
    }

    private var recognitionSummary: String {
        let dates = Set(reviewEntries.compactMap(\.lessonDate))
        let days = dates.count
        let entries = reviewEntries.count
        return entries == 0 ? "Не вдалося скласти записи. Можна додати вручну або сфотографувати сторінку ще раз." :
            "Знайдено \(entries) \(entries == 1 ? "запис" : "записи") за \(days) \(days == 1 ? "датою" : "датами"). Перевірте картки поруч з фото."
    }

    private func homeworkProposalCard(_ proposal: OrbitHomeworkProposal) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(proposal.candidate.subject).font(.subheadline.weight(.bold))
                Spacer()
                Text(proposal.changeKind == "uncertain" ? "Уточнити" : proposal.changeKind == "update" ? "Зміна" : proposal.changeKind == "same" ? "Повтор" : "Нове")
                    .font(.caption.weight(.semibold)).padding(.horizontal, 9).padding(.vertical, 5)
                    .background(proposal.changeKind == "uncertain" ? Color.orange.opacity(0.14) : Color.accentColor.opacity(0.12), in: Capsule())
            }
            if let date = proposal.candidate.lessonDate { Label("Урок · \(homeworkDayTitle(date))", systemImage: "calendar") .font(.caption).foregroundStyle(.secondary) }
            if let due = proposal.candidate.dueDate { Label("Здати до · \(homeworkDayTitle(due))", systemImage: "clock") .font(.caption).foregroundStyle(.secondary) }
            if proposal.changeKind == "update", let previous = proposal.currentAssignmentText {
                LabeledContent("Було", value: previous)
                LabeledContent("Нове розпізнавання", value: proposal.candidate.assignmentText)
            } else { Text(proposal.candidate.assignmentText).textSelection(.enabled) }
            if let confidence = proposal.candidate.confidence?["assignmentText"] {
                Text("Точність тексту OCR · \(Int(confidence * 100))%").font(.caption2).foregroundStyle(.secondary)
            }
            if let source = store.snapshots.first(where: { $0.id == proposal.snapshotId }) {
                Button("Показати сторінку поруч") { selectedSnapshot = source }.font(.caption.weight(.semibold))
            }
            HStack {
                Button("Відхилити") { Task { try? await store.resolve(proposal, accept: false) } }.buttonStyle(.bordered)
                Spacer()
                Button("Підтвердити") { Task { try? await store.resolve(proposal, accept: true) } }
                    .buttonStyle(.borderedProminent).disabled(proposal.changeKind == "uncertain")
            }
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func confirmObvious() async {
        for proposal in obviousPendingProposals {
            do { try await store.resolve(proposal, accept: true) }
            catch { store.error = "Не всі очевидні записи вдалося підтвердити. Оновіть список перед повтором."; return }
        }
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
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let photoData, let image = UIImage(data: photoData) {
                        Image(uiImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 14))
                            .accessibilityLabel("Оригінал сторінки щоденника")
                    }
                    Text("Перевірте записи за датою й предметом. Дедлайн показано окремо лише коли його явно написано.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if reviewEntries.isEmpty {
                        ContentUnavailableView("Записів не розпізнано", systemImage: "text.viewfinder", description: Text("Можна зробити чіткіше фото або додати завдання вручну."))
                    }
                    ForEach(reviewEntries) { entry in reviewEntryCard(entry) }
                    HStack(spacing: 10) {
                        TextField("Навчальний рік", text: $diarySchoolYear).textFieldStyle(.roundedBorder)
                        TextField("KW", text: $diaryWeek).keyboardType(.numberPad).textFieldStyle(.roundedBorder).frame(width: 72)
                    }
                    TextField("Позначка сторінки", text: $diaryPageLabel).textFieldStyle(.roundedBorder)
                    Button { Task { await uploadAndReview() } } label: {
                        if store.saving || submittingPhotoReview { ProgressView().frame(maxWidth: .infinity) }
                        else { Label("Зберегти фото й надіслати вибрані на перевірку", systemImage: "lock.shield").frame(maxWidth: .infinity) }
                    }.buttonStyle(.borderedProminent).disabled(store.saving || submittingPhotoReview || !reviewEntries.contains(where: { $0.selected && !$0.assignmentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }))
                    Text("Канонічні завдання не зміняться, доки батько не підтвердить пропозиції окремо.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(16)
            }
            .navigationTitle("Перевірка щоденника")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Готово") { showReviewForm = false } } }
        }.presentationDetents([.large])
    }

    private func reviewEntryCard(_ entry: HomeworkReviewCandidate) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let crop = sourceCrop(for: entry) {
                Image(uiImage: crop).resizable().scaledToFit().frame(maxHeight: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .accessibilityLabel("Фрагмент щоденника для цього завдання")
            }
            HStack {
                Text(entry.lessonDate.map(homeworkDayTitle) ?? "Дату уроку уточнити").font(.headline)
                Spacer()
                Button { updateReviewEntry(entry.id) { $0.selected.toggle() } } label: {
                    Image(systemName: entry.selected ? "checkmark.circle.fill" : "circle")
                }.accessibilityLabel(entry.selected ? "Не надсилати цей запис" : "Надіслати цей запис на перевірку")
            }
            TextField("Предмет", text: reviewBinding(entry.id, \.subject)).font(.subheadline.weight(.semibold)).textFieldStyle(.roundedBorder)
            TextField("Завдання", text: reviewBinding(entry.id, \.assignmentText), axis: .vertical).lineLimit(2...5).textFieldStyle(.roundedBorder)
            TextField("Дата уроку · РРРР-ММ-ДД", text: reviewOptionalBinding(entry.id, \.lessonDate)).textInputAutocapitalization(.never).textFieldStyle(.roundedBorder)
            TextField("Дедлайн лише якщо вказаний · РРРР-ММ-ДД", text: reviewOptionalBinding(entry.id, \.dueDate)).textInputAutocapitalization(.never).textFieldStyle(.roundedBorder)
            HStack {
                Text("Дедлайн: \(entry.dueDate.map(homeworkDayTitle) ?? "не вказано")").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if entry.needsReview { Label(entry.reviewReason ?? "Перевірте", systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange) }
            }
            if let match = store.tasks.first(where: { $0.id == entry.matchedTaskId }) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.changeKind == "same" ? "Схоже на повтор" : entry.changeKind == "update" ? "Можливе доповнення" : "Схожий запис")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text("Раніше: \(match.assignmentText)").font(.caption).foregroundStyle(.secondary)
                }
            } else if entry.pendingDuplicate {
                Label("Цей запис уже очікує батьківського рішення", systemImage: "clock.badge.checkmark")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            } else {
                Text(entry.changeKind == "new" ? "Нове завдання" : "Потрібна перевірка збігу")
                    .font(.caption.weight(.semibold)).foregroundStyle(entry.needsReview ? .orange : .secondary)
            }
            if entry.needsReview {
                Picker("Рішення", selection: reviewKindBinding(entry.id)) {
                    Text("Уточнити пізніше").tag("uncertain")
                    Text("Нове завдання").tag("new")
                    Text("Доповнити наявне").tag("update")
                    Text("Це той самий запис").tag("same")
                }.pickerStyle(.menu)
                if entry.changeKind == "update" || entry.changeKind == "same" {
                    let matches = homeworkMatches(for: entry)
                    Picker("Збіг за датою й предметом", selection: reviewMatchBinding(entry.id)) {
                        Text("Виберіть завдання").tag(String?.none)
                        ForEach(matches) { task in Text("\(task.subject): \(task.assignmentText.prefix(42))").tag(Optional(task.id)) }
                    }.pickerStyle(.menu)
                    Toggle("Шукати в усіх завданнях", isOn: $showAllHomeworkMatches).font(.caption)
                }
            }
            Text("OCR \(Int((entry.confidence["assignmentText"] ?? 0) * 100))% · фрагмент фото \(Int(entry.sourceRegion.minX * 100))%, \(Int(entry.sourceRegion.minY * 100))%")
                .font(.caption2).foregroundStyle(.tertiary)
        }.padding(14).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private func sourceCrop(for entry: HomeworkReviewCandidate) -> UIImage? {
        guard let photoData, let image = UIImage(data: photoData), let cgImage = image.cgImage else { return nil }
        let width = CGFloat(cgImage.width), height = CGFloat(cgImage.height)
        let region = entry.sourceRegion
        let rect = CGRect(x: CGFloat(region.minX) * width, y: (1 - CGFloat(region.maxY)) * height, width: CGFloat(region.width) * width, height: CGFloat(region.height) * height)
            .integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard rect.width > 1, rect.height > 1, let crop = cgImage.cropping(to: rect) else { return nil }
        return UIImage(cgImage: crop, scale: image.scale, orientation: image.imageOrientation)
    }

    private func updateReviewEntry(_ id: Int, _ update: (inout HomeworkReviewCandidate) -> Void) {
        guard let index = reviewEntries.firstIndex(where: { $0.id == id }) else { return }
        update(&reviewEntries[index])
    }

    private func reviewBinding<Value>(_ id: Int, _ keyPath: WritableKeyPath<HomeworkReviewCandidate, Value>) -> Binding<Value> {
        Binding(get: { reviewEntries.first(where: { $0.id == id })![keyPath: keyPath] }, set: { value in
            updateReviewEntry(id) { $0[keyPath: keyPath] = value; $0.changeKind = "uncertain"; $0.matchedTaskId = nil; $0.pendingDuplicate = false; $0.needsReview = true; $0.selected = false }
        })
    }

    private func reviewOptionalBinding(_ id: Int, _ keyPath: WritableKeyPath<HomeworkReviewCandidate, String?>) -> Binding<String> {
        Binding(get: { reviewEntries.first(where: { $0.id == id })![keyPath: keyPath] ?? "" }, set: { value in
            updateReviewEntry(id) { $0[keyPath: keyPath] = value.nilIfEmpty; $0.changeKind = "uncertain"; $0.matchedTaskId = nil; $0.pendingDuplicate = false; $0.needsReview = true; $0.selected = false }
        })
    }

    private func reviewKindBinding(_ id: Int) -> Binding<String> {
        Binding(get: { reviewEntries.first(where: { $0.id == id })?.changeKind ?? "uncertain" }, set: { value in
            updateReviewEntry(id) { $0.changeKind = value; if value == "new" { $0.matchedTaskId = nil }; $0.needsReview = value == "uncertain"; $0.selected = value == "new" || ((value == "update" || value == "same") && $0.matchedTaskId != nil) }
        })
    }

    private func reviewMatchBinding(_ id: Int) -> Binding<String?> {
        Binding(get: { reviewEntries.first(where: { $0.id == id })?.matchedTaskId }, set: { value in
            updateReviewEntry(id) { $0.matchedTaskId = value; $0.selected = value != nil }
        })
    }

    private func homeworkMatches(for entry: HomeworkReviewCandidate) -> [OrbitHomeworkTask] {
        let confirmed = store.tasks.filter { $0.reviewState == "confirmed" }
        guard !showAllHomeworkMatches else { return confirmed }
        return confirmed.filter { $0.lessonDate == entry.lessonDate && $0.subject.localizedCaseInsensitiveCompare(entry.subject) == .orderedSame }
    }

    private static func photoType(_ data: Data) -> String? {
        let bytes = [UInt8](data.prefix(12))
        if bytes.count >= 3 && bytes[0] == 0xff && bytes[1] == 0xd8 && bytes[2] == 0xff { return "image/jpeg" }
        if bytes.count >= 8 && Array(bytes.prefix(8)) == [0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a] { return "image/png" }
        if bytes.count >= 12 && String(bytes: bytes[4..<8], encoding: .ascii) == "ftyp", let brand = String(bytes: bytes[8..<12], encoding: .ascii), ["heic","heix","mif1","heif"].contains(brand) { return "image/heic" }
        return nil
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self), UIImage(data: data) != nil, let type = Self.photoType(data) else { return }
        await preparePhoto(data, contentType: type)
    }

    private func preparePhoto(_ data: Data, contentType: String) async {
        photoData = data; photoContentType = contentType; photoSnapshot = nil; photoUploadRequestId = UUID().uuidString; reviewEntries = []
        guard let image = UIImage(data: data), let cgImage = image.cgImage else { return }
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
        diaryAnalysis = SchoolHomeworkDiaryAnalyzer.analyze(recognized)
        diarySchoolYear = diaryAnalysis.schoolYear ?? ""
        diaryWeek = diaryAnalysis.calendarWeek.map(String.init) ?? ""
        diaryPageLabel = diaryAnalysis.pageLabel ?? ""
        let pageKey = SchoolHomeworkDiaryAnalyzer.pageKey(schoolYear: diarySchoolYear.nilIfEmpty, calendarWeek: Int(diaryWeek), pageLabel: diaryPageLabel.nilIfEmpty)
        let taskRecords = store.tasks.filter { $0.reviewState == "confirmed" }.map { task in
            let linkedSnapshots = task.sources.compactMap(\.snapshotId).compactMap { id in store.snapshots.first(where: { $0.id == id }) }
            let keys = linkedSnapshots.compactMap { SchoolHomeworkDiaryAnalyzer.pageKey(schoolYear: $0.schoolYear, calendarWeek: $0.calendarWeek, pageLabel: $0.pageLabel) }
            let key = keys.first(where: { $0 == pageKey }) ?? keys.first
            return SchoolHomeworkMatchRecord(id: task.id, subject: task.subject, assignmentText: task.assignmentText, lessonDate: task.lessonDate, sourcePageKey: key)
        }
        let pendingRecords = store.proposals.filter { $0.decision == "pending" }.map { proposal in
            SchoolHomeworkMatchRecord(
                id: "proposal:\(proposal.id)", subject: proposal.candidate.subject,
                assignmentText: proposal.candidate.assignmentText, lessonDate: proposal.candidate.lessonDate,
                sourcePageKey: SchoolHomeworkDiaryAnalyzer.pageKey(schoolYear: proposal.schoolYear, calendarWeek: proposal.calendarWeek, pageLabel: proposal.pageLabel)
            )
        }
        let records = taskRecords + pendingRecords
        reviewEntries = diaryAnalysis.entries.map { entry in
            let match = SchoolHomeworkDiaryAnalyzer.match(entry, against: records, pageKey: pageKey)
            let pendingDuplicate = match.matchedRecordID?.hasPrefix("proposal:") == true
            return HomeworkReviewCandidate(
                id: entry.id, subject: entry.subject ?? "", assignmentText: entry.assignmentText,
                lessonDate: entry.lessonDate, dueDate: entry.dueDate, sourceLineIDs: entry.sourceLineIDs,
                sourceRegion: entry.sourceRegion, confidence: entry.confidence, needsReview: entry.needsReview || match.kind == .uncertain,
                reviewReason: entry.reviewReason ?? (match.kind == .uncertain ? "Збіг неоднозначний" : nil),
                changeKind: match.kind.rawValue, matchedTaskId: pendingDuplicate ? nil : match.matchedRecordID, matchScore: match.score,
                pendingDuplicate: pendingDuplicate, selected: match.kind != .uncertain && !entry.needsReview && !pendingDuplicate,
                clientRequestId: UUID().uuidString
            )
        }
    }

    private func clearPhotoDraft() {
        photoData = nil; photoSnapshot = nil; reviewEntries = []; selectedPhoto = nil
        diaryAnalysis = SchoolHomeworkDiaryAnalysis(schoolYear: nil, calendarWeek: nil, pageLabel: nil, entries: [])
        photoUploadRequestId = UUID().uuidString
    }

    private func uploadAndReview() async {
        guard let photoData, !submittingPhotoReview else { return }
        submittingPhotoReview = true
        defer { submittingPhotoReview = false }
        do {
            if photoSnapshot == nil {
                photoSnapshot = try await store.uploadPhoto(photoData, contentType: photoContentType, schoolYear: diarySchoolYear.nilIfEmpty, calendarWeek: Int(diaryWeek), pageLabel: diaryPageLabel.nilIfEmpty, clientRequestId: photoUploadRequestId)
            }
            guard let photoSnapshot else { return }
            for entry in reviewEntries.filter(\.selected) {
                let cleanSubject = entry.subject.trimmingCharacters(in: .whitespacesAndNewlines)
                let cleanText = entry.assignmentText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleanSubject.isEmpty, !cleanText.isEmpty else { continue }
                let matched = entry.matchedTaskId.flatMap { id in store.tasks.first { $0.id == id } }
                let region = String(format: "vision-unit-rect:%.4f,%.4f,%.4f,%.4f", entry.sourceRegion.minX, entry.sourceRegion.minY, entry.sourceRegion.width, entry.sourceRegion.height)
                try await store.propose(snapshot: photoSnapshot, subject: cleanSubject, text: cleanText, lessonDate: entry.lessonDate, dueDate: entry.dueDate, changeKind: entry.changeKind, matchedTaskId: matched?.id, expectedRevision: matched?.revision, sourceRegion: region, confidence: entry.confidence, clientRequestId: entry.clientRequestId)
            }
            self.photoData = nil; self.photoSnapshot = nil; reviewEntries = []; selectedPhoto = nil; showReviewForm = false
            photoUploadRequestId = UUID().uuidString
            await store.load()
        } catch { store.error = "Фото збережене, але не всі записи вдалося надіслати. Оновіть список і перевірте пропозиції." }
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
