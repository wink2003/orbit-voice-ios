import SwiftUI

/// Adults only (the entry point is hidden for read-only profiles and the server refuses children): senders whose mail is waiting for a decision,
/// the allowlist, and the mailbox status. Nothing from an undecided sender is translated, summarised or shown as a letter.
struct SchoolEmailView: View {
    private enum Phase { case loading, loaded, failed }
    private struct Pending: Identifiable { let id = UUID(); let pattern: String; let status: String; let title: String; let confirm: String }

    @State private var phase: Phase = .loading
    @State private var status: OrbitSchoolEmailStatus?
    @State private var quarantine: [OrbitSchoolEmailQuarantineSender] = []
    @State private var senders: [OrbitSchoolEmailSender] = []
    @State private var busy = false
    @State private var notice: String?
    @State private var pending: Pending?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            statusSection
            if phase == .failed {
                Section { Label("Не вдалося завантажити. Перевірте з’єднання й потягніть, щоб оновити.", systemImage: "exclamationmark.triangle").font(.footnote) }
            }
            if let notice { Section { Label(notice, systemImage: "info.circle").font(.footnote) } }
            quarantineSection
            sendersSection
            Section {
                Text("Як це працює: у Gmail створіть фільтр на листи від вчителів і секретаріату з дією «Переслати» на адресу скриньки Orbit. Лист від нового відправника спершу чекає тут на ваше рішення. Orbit лише читає скриньку й нічого не надсилає.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Email від вчителів")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .confirmationDialog(pending?.title ?? "", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
            if let p = pending { Button(p.confirm, role: p.status == "blocked" ? .destructive : nil) { decide(p.pattern, p.status) } }
            Button("Скасувати", role: .cancel) { pending = nil }
        }
    }

    private var statusSection: some View {
        Section("Скринька") {
            if let status {
                LabeledContent("Стан") { Text(SchoolEmailLogic.statusLine(enabled: status.enabled, configured: status.configured, lastError: status.lastError)).foregroundStyle(status.lastError == nil && status.configured ? NovaTodayTokens.teal : .secondary) }
                if let last = status.lastPollAt { LabeledContent("Останнє опитування") { Text(last.formatted(date: .abbreviated, time: .shortened)) } }
                LabeledContent("Додано листів") { Text("\(status.counts["ingested"] ?? 0)") }
                if status.forwardersEnforced { Label("Перевіряється адреса, з якої переслано", systemImage: "checkmark.shield").font(.footnote).foregroundStyle(.secondary) }
            } else if phase == .loading { ProgressView() }
        }
    }

    private var quarantineSection: some View {
        Section {
            if quarantine.isEmpty && phase == .loaded { Text("Немає листів, що чекають на рішення.").foregroundStyle(.secondary) }
            ForEach(quarantine) { sender in
                VStack(alignment: .leading, spacing: 6) {
                    Text((sender.name ?? "").isEmpty ? sender.address : "\(sender.name ?? "") · \(sender.address)").font(.subheadline.weight(.semibold))
                    Text("\(sender.messages) лист(ів)" + (sender.latestAt.map { " · \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "")).font(.caption).foregroundStyle(.secondary)
                    if !sender.latestSubject.isEmpty { Text(sender.latestSubject).font(.callout) }
                    if !sender.latestPreview.isEmpty { Text(sender.latestPreview).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                    HStack {
                        Button("Дозволити") { ask(SchoolEmailLogic.exactPattern(for: sender.address), "approved", "Дозволити \(sender.address)?", "Дозволити й додати листи") }
                        if let domain = SchoolEmailLogic.domainPattern(for: sender.address) {
                            Button("Весь домен") { ask(domain, "approved", "Дозволити всіх відправників \(domain)?", "Дозволити домен") }
                        }
                        Button("Блокувати", role: .destructive) { ask(SchoolEmailLogic.exactPattern(for: sender.address), "blocked", "Заблокувати \(sender.address)?", "Заблокувати") }
                    }
                    .buttonStyle(.bordered).disabled(busy).frame(minHeight: OrbitSpacing.minTarget)
                }
                .padding(.vertical, 4)
            }
        } header: { Text("Чекають на рішення (\(quarantine.count))") }
    }

    private var sendersSection: some View {
        Section {
            if senders.isEmpty && phase == .loaded { Text("Рішень ще немає.").foregroundStyle(.secondary) }
            ForEach(senders) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.pattern).font(.subheadline)
                        if let label = item.label, !label.isEmpty { Text(label).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Text(item.status == "approved" ? "Дозволено" : "Заблоковано").font(.caption.weight(.semibold)).foregroundStyle(item.status == "approved" ? NovaTodayTokens.teal : .red)
                }
                .swipeActions {
                    if item.status == "approved" { Button("Блокувати") { ask(item.pattern, "blocked", "Заблокувати \(item.pattern)?", "Заблокувати") }.tint(.red) }
                    else { Button("Дозволити") { ask(item.pattern, "approved", "Дозволити \(item.pattern)?", "Дозволити") }.tint(.green) }
                }
            }
        } header: { Text("Рішення (\(senders.count))") }
    }

    private func ask(_ pattern: String?, _ status: String, _ title: String, _ confirm: String) {
        guard let pattern else { notice = "Некоректна адреса відправника."; return }
        pending = Pending(pattern: pattern, status: status, title: title, confirm: confirm)
    }

    private func decide(_ pattern: String, _ status: String) {
        pending = nil
        Task {
            busy = true; defer { busy = false }
            do {
                let result = try await MainProductAPI.shared.decideSchoolEmailSender(pattern: pattern, status: status)
                notice = SchoolEmailLogic.decisionSummary(status: result.status, released: result.released, rejected: result.rejected, failed: result.failed)
                await load()
            } catch { notice = "Не вдалося зберегти рішення. Спробуйте ще раз." }
        }
    }

    private func load() async {
        do {
            async let s = MainProductAPI.shared.schoolEmailStatus()
            async let q = MainProductAPI.shared.schoolEmailQuarantine()
            async let a = MainProductAPI.shared.schoolEmailSenders()
            let (st, qu, se) = try await (s, q, a)
            status = st; quarantine = qu; senders = se; phase = .loaded
        } catch is CancellationError {
        } catch { phase = .failed }
    }
}
