import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// Medical section (orbit-family-ai#379). Per person: medication schedule, appointments, diagnoses, scanned documents.
// The server decides access (self; a parent sees minor children; external records such as the owner's parents are visible only to their keeper) and
// answers 404 `medical_disabled` until the owner enables the section. Nothing here reads or writes anything except through /api/medical.

struct MedSchedule: Decodable, Hashable {
    let times: [String]?
    let days: [Int]?
    let asNeeded: Bool?
    private enum CodingKeys: String, CodingKey { case times, days, asNeeded = "as_needed" }
}
struct MedSubject: Decodable, Identifiable, Hashable {
    let id: String
    let kind: String
    let displayName: String
    let relation: String?
    let notes: String?
}
struct MedMedication: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let doseText: String?
    let instructions: String?
    let schedule: MedSchedule?
    let status: String
}
struct MedAppointment: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let provider: String?
    let location: String?
    let startsAt: String?
    let status: String
}
struct MedDiagnosis: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let code: String?
    let status: String
    let notes: String?
}
struct MedDocument: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let kind: String
    let filename: String
    let contentType: String
    let sizeBytes: Int
}
struct MedSummary: Decodable {
    let subject: MedSubject
    let medications: [MedMedication]
    let appointments: [MedAppointment]
    let diagnoses: [MedDiagnosis]
    let documents: [MedDocument]
}

enum MedicalAPI {
    private struct SubjectsResponse: Decodable { let subjects: [MedSubject] }
    private struct Empty: Decodable {}

    static func subjects() async throws -> [MedSubject] {
        let response: SubjectsResponse = try await MainProductAPI.shared.request(path: "/api/medical/subjects", cachePolicy: .reloadIgnoringLocalCacheData, preserveHTTPStatus: true)
        return response.subjects
    }
    static func summary(_ id: String) async throws -> MedSummary {
        try await MainProductAPI.shared.request(path: "/api/medical/subjects/\(id)", cachePolicy: .reloadIgnoringLocalCacheData, preserveHTTPStatus: true)
    }
    static func createExternal(name: String, relation: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["displayName": name, "relation": relation])
        let _: Empty = try await MainProductAPI.shared.request(path: "/api/medical/subjects", method: "POST", body: body, preserveHTTPStatus: true)
    }
    static func add(subject: String, collection: String, fields: [String: Any]) async throws {
        let body = try JSONSerialization.data(withJSONObject: fields)
        let _: Empty = try await MainProductAPI.shared.request(path: "/api/medical/subjects/\(subject)/\(collection)", method: "POST", body: body, preserveHTTPStatus: true)
    }
    static func remove(subject: String, collection: String, id: String) async throws {
        let _: Empty = try await MainProductAPI.shared.request(path: "/api/medical/subjects/\(subject)/\(collection)/\(id)", method: "DELETE", preserveHTTPStatus: true)
    }
    static func message(for error: Error) -> String {
        if let failure = error as? OrbitHTTPResponseFailure {
            switch failure.code {
            case "medical_disabled": return "Медичний розділ ще не ввімкнено."
            case "medical_adult_required": return "Медичний розділ доступний лише дорослим."
            case "medical_storage_unavailable": return "Сховище сканів ще не налаштоване."
            case "unsupported_document": return "Підтримуються лише PDF, JPEG, PNG та HEIC."
            case "invalid_document": return "Файл порожній або більший за 10 МБ."
            default: return "Не вдалося виконати дію (\(failure.status))."
            }
        }
        return "Не вдалося підключитися до Orbit."
    }
}

struct MedicalHomeView: View {
    @State private var subjects: [MedSubject] = []
    @State private var loading = true
    @State private var errorText: String?
    @State private var showingAdd = false
    @State private var newName = ""
    @State private var newRelation = ""

    var body: some View {
        List {
            if let errorText {
                Section { Text(errorText).foregroundStyle(.secondary) }
            } else if loading {
                Section { ProgressView() }
            } else {
                Section("Люди") {
                    ForEach(subjects) { subject in
                        NavigationLink(value: subject) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(subject.displayName).font(.body.weight(.semibold))
                                if subject.kind == "external" { Text(subject.relation ?? "Запис без акаунта").font(.footnote).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
                Section { Button("Додати людину (наприклад, маму)") { showingAdd = true } }
                Section { Text("Лише ви бачите записи, які створили. Дані не доступні ні голосу, ні чату.").font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Медицина")
        .navigationDestination(for: MedSubject.self) { MedicalSubjectView(subject: $0) }
        .task { await load() }
        .alert("Нова людина", isPresented: $showingAdd) {
            TextField("Ім’я", text: $newName)
            TextField("Хто це (мама, тато…)", text: $newRelation)
            Button("Додати") { Task { await addExternal() } }
            Button("Скасувати", role: .cancel) { newName = ""; newRelation = "" }
        }
    }

    private func load() async {
        loading = true; defer { loading = false }
        do { subjects = try await MedicalAPI.subjects(); errorText = nil } catch { errorText = MedicalAPI.message(for: error) }
    }
    private func addExternal() async {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do { try await MedicalAPI.createExternal(name: name, relation: newRelation.trimmingCharacters(in: .whitespacesAndNewlines)); newName = ""; newRelation = ""; await load() }
        catch { errorText = MedicalAPI.message(for: error) }
    }
}

private enum MedicalSheet: Identifiable {
    case medication, appointment, diagnosis, document
    var id: Int { hashValue }
}

struct MedicalSubjectView: View {
    let subject: MedSubject
    @State private var summary: MedSummary?
    @State private var errorText: String?
    @State private var sheet: MedicalSheet?
    @State private var sharedFile: URL?

    var body: some View {
        List {
            if let errorText { Section { Text(errorText).foregroundStyle(.secondary) } }
            if let summary {
                Section("Ліки") {
                    ForEach(summary.medications) { med in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(med.name).font(.body.weight(.semibold))
                            Text([med.doseText, med.schedule?.times?.joined(separator: ", "), med.status == "active" ? nil : med.status].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")).font(.footnote).foregroundStyle(.secondary)
                        }
                        .swipeActions { Button("Видалити", role: .destructive) { Task { await remove("medications", med.id) } } }
                    }
                    Button("Додати ліки") { sheet = .medication }
                }
                Section("Прийоми") {
                    ForEach(summary.appointments) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.body.weight(.semibold))
                            Text([Self.display(item.startsAt), item.provider, item.location].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")).font(.footnote).foregroundStyle(.secondary)
                        }
                        .swipeActions { Button("Видалити", role: .destructive) { Task { await remove("appointments", item.id) } } }
                    }
                    Button("Додати прийом") { sheet = .appointment }
                }
                Section("Діагнози") {
                    ForEach(summary.diagnoses) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(.body.weight(.semibold))
                            Text([item.code, item.status].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")).font(.footnote).foregroundStyle(.secondary)
                        }
                        .swipeActions { Button("Видалити", role: .destructive) { Task { await remove("diagnoses", item.id) } } }
                    }
                    Button("Додати діагноз") { sheet = .diagnosis }
                }
                Section("Документи") {
                    ForEach(summary.documents) { doc in
                        Button { Task { await open(doc) } } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(doc.title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                                Text("\(doc.kind) · \(doc.sizeBytes / 1024) КБ").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions { Button("Видалити", role: .destructive) { Task { await remove("documents", doc.id) } } }
                    }
                    Button("Додати скан або документ") { sheet = .document }
                }
            } else if errorText == nil {
                Section { ProgressView() }
            }
        }
        .navigationTitle(subject.displayName)
        .task { await load() }
        .sheet(item: $sheet) { which in
            NavigationStack { MedicalFormView(kind: which, subjectID: subject.id) { sheet = nil; Task { await load() } } }
        }
        .sheet(item: Binding(get: { sharedFile.map { MedicalShare(url: $0) } }, set: { if $0 == nil { sharedFile = nil } })) { MedicalShareSheet(url: $0.url) }
    }

    private static func display(_ iso: String?) -> String? {
        guard let iso, let date = ISO8601DateFormatter().date(from: iso) ?? { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f.date(from: iso) }() else { return nil }
        return date.formatted(.dateTime.day().month().year().hour().minute().locale(Locale(identifier: "uk_UA")))
    }
    private func load() async {
        do { summary = try await MedicalAPI.summary(subject.id); errorText = nil } catch { errorText = MedicalAPI.message(for: error) }
    }
    private func remove(_ collection: String, _ id: String) async {
        do { try await MedicalAPI.remove(subject: subject.id, collection: collection, id: id); await load() } catch { errorText = MedicalAPI.message(for: error) }
    }
    private func open(_ doc: MedDocument) async {
        do {
            let data = try await MainProductAPI.shared.medicalDownloadDocument(subjectID: subject.id, documentID: doc.id)
            let ext = doc.contentType == "application/pdf" ? "pdf" : doc.contentType == "image/png" ? "png" : doc.contentType == "image/heic" ? "heic" : "jpg"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("orbit-med-\(doc.id).\(ext)")
            try data.write(to: url, options: .completeFileProtection)
            sharedFile = url
        } catch { errorText = MedicalAPI.message(for: error) }
    }
}

private struct MedicalShare: Identifiable { let url: URL; var id: String { url.absoluteString } }
private struct MedicalShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private struct MedicalFormView: View {
    let kind: MedicalSheet
    let subjectID: String
    let done: () -> Void
    @State private var title = ""
    @State private var detail = ""
    @State private var times = "08:00"
    @State private var date = Date().addingTimeInterval(86400)
    @State private var status = "active"
    @State private var docKind = "report"
    @State private var importing = false
    @State private var photo: PhotosPickerItem?
    @State private var picked: (data: Data, filename: String, type: String)?
    @State private var errorText: String?
    @State private var busy = false

    var body: some View {
        Form {
            switch kind {
            case .medication:
                TextField("Назва ліків", text: $title)
                TextField("Доза (наприклад, 500 мг)", text: $detail)
                TextField("Час прийому (08:00, 20:00)", text: $times)
            case .appointment:
                TextField("Що за прийом", text: $title)
                TextField("Лікар або заклад", text: $detail)
                DatePicker("Дата і час", selection: $date)
            case .diagnosis:
                TextField("Діагноз", text: $title)
                TextField("Код (необов’язково)", text: $detail)
                Picker("Стан", selection: $status) { Text("Активний").tag("active"); Text("Хронічний").tag("chronic"); Text("Минув").tag("resolved") }
            case .document:
                TextField("Назва документа", text: $title)
                Picker("Тип", selection: $docKind) {
                    Text("Висновок").tag("report"); Text("Рецепт").tag("prescription"); Text("Аналізи").tag("lab")
                    Text("Знімок").tag("imaging"); Text("Щеплення").tag("vaccination"); Text("Інше").tag("other")
                }
                Button(picked == nil ? "Обрати файл (PDF, фото)" : "Файл: \(picked?.filename ?? "")") { importing = true }
                PhotosPicker("Обрати фото з галереї", selection: $photo, matching: .images)
            }
            if let errorText { Text(errorText).foregroundStyle(.red) }
        }
        .navigationTitle("Додати")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Скасувати") { done() } }
            ToolbarItem(placement: .confirmationAction) { Button("Зберегти") { Task { await save() } }.disabled(busy || title.trimmingCharacters(in: .whitespaces).isEmpty) }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, .jpeg, .png, .heic]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { errorText = "Не вдалося прочитати файл."; return }
            let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            picked = (data, url.lastPathComponent, type)
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) { picked = (data, "photo.jpg", "image/jpeg") }
            }
        }
    }

    private func save() async {
        busy = true; defer { busy = false }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let extra = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            switch kind {
            case .medication:
                let list = times.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                try await MedicalAPI.add(subject: subjectID, collection: "medications", fields: ["name": name, "doseText": extra, "schedule": ["times": list]])
            case .appointment:
                try await MedicalAPI.add(subject: subjectID, collection: "appointments", fields: ["title": name, "provider": extra, "startsAt": ISO8601DateFormatter().string(from: date)])
            case .diagnosis:
                try await MedicalAPI.add(subject: subjectID, collection: "diagnoses", fields: ["name": name, "code": extra, "status": status])
            case .document:
                guard let picked else { errorText = "Оберіть файл."; return }
                try await MainProductAPI.shared.medicalUploadDocument(subjectID: subjectID, title: name, kind: docKind, filename: picked.filename, contentType: picked.type, data: picked.data)
            }
            done()
        } catch { errorText = MedicalAPI.message(for: error) }
    }
}
