import SwiftUI

/// Admin panel v3: one design for the hub and every section page (owner decision 2026-11-15: hub + a detailed page per section).
/// Pure presentation; decisions live in AdminHealthLogic / AdminSectionsLogic.

struct AdminCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(Routes05Tokens.surface, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Routes05Tokens.rule, lineWidth: 1))
    }
}

extension View {
    func adminCard() -> some View { modifier(AdminCardStyle()) }
}

/// Titled card with an optional status dot; the body is the caller's rows.
struct AdminCard<Content: View>: View {
    let title: String
    let icon: String
    var level: AdminHealthLevel? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label(title, systemImage: icon).font(.headline).foregroundStyle(Routes05Tokens.ink)
                Spacer(minLength: 0)
                if let level { Image(systemName: level.symbol).foregroundStyle(level.color).font(.subheadline) }
            }
            content
        }.adminCard()
    }
}

/// Label/value row (secondary label left, value right).
struct AdminRow: View {
    let title: String
    let value: String
    var warn = false
    init(_ title: String, _ value: String, warn: Bool = false) { self.title = title; self.value = value; self.warn = warn }
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.subheadline).foregroundStyle(Routes05Tokens.secondary)
            Spacer(minLength: 12)
            Text(value).font(.subheadline.monospacedDigit()).foregroundStyle(warn ? Color.orange : Routes05Tokens.ink).multilineTextAlignment(.trailing)
        }
    }
}

/// Tappable row that opens a deeper page: icon, title, short value, optional status, chevron. Use inside a NavigationLink.
struct AdminNavLabel: View {
    let icon: String
    let title: String
    var value: String? = nil
    var level: AdminHealthLevel? = nil
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).frame(width: 24).foregroundStyle(Routes05Tokens.secondary)
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Routes05Tokens.ink)
            Spacer(minLength: 8)
            if let value { Text(value).font(.subheadline.monospacedDigit()).foregroundStyle(Routes05Tokens.secondary).lineLimit(1) }
            if let level, level >= .warning { Image(systemName: level.symbol).foregroundStyle(level.color).font(.subheadline) }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Routes05Tokens.secondary)
        }.contentShape(Rectangle())
    }
}

/// Hub entry for one section: icon, title, one-line summary, status.
struct AdminSectionLinkLabel: View {
    let icon: String
    let title: String
    let summary: String
    var level: AdminHealthLevel = .ok
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title3).frame(width: 30).foregroundStyle(Routes05Tokens.mint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline).foregroundStyle(Routes05Tokens.ink)
                Text(summary).font(.caption).foregroundStyle(Routes05Tokens.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if level >= .warning { Image(systemName: level.symbol).foregroundStyle(level.color) }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Routes05Tokens.secondary)
        }
        .adminCard()
        .contentShape(Rectangle())
    }
}

/// Page shell shared by every section page: canvas background, uniform padding, title.
struct AdminPage<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 12) { content }.padding(.horizontal, 16).padding(.vertical, 12) }
            .background(Routes05Tokens.canvas).navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Section pages

struct AdminServerPage: View {
    @ObservedObject var store: ServerOverviewStore
    let items: [AdminAttention]
    var body: some View {
        AdminPage(title: "Сервер") {
            if let v = store.overview {
                AdminCard(title: "main-server", icon: "server.rack", level: AdminSection.server.level(items)) {
                    AdminRow("ОС", "\(v.server.os) · \(v.server.architecture.uppercased())")
                    AdminRow("Працює", AdminHealthLogic.duration(v.server.uptimeSeconds))
                    AdminRow("Знімок", AdminHealthLogic.duration(max(0, Date().timeIntervalSince(v.generatedAt))) + " тому")
                }
                VStack(spacing: 0) {
                    NavigationLink { ServerOverviewDetailView(section: .cpu) } label: {
                        AdminNavLabel(icon: "cpu", title: "CPU", value: (v.cpu.utilizationPercent.map { AdminHealthLogic.percent($0) } ?? String(format: "load %.1f", v.cpu.loadAverage.five)) + " · \(v.cpu.logicalCpus) vCPU")
                    }.buttonStyle(.plain).padding(.vertical, 10)
                    Divider()
                    NavigationLink { ServerOverviewDetailView(section: .memory) } label: {
                        AdminNavLabel(icon: "memorychip", title: "Памʼять", value: AdminHealthLogic.percent(v.memory.usedPercent) + " · " + AdminHealthLogic.bytes(v.memory.availableBytes) + " вільно")
                    }.buttonStyle(.plain).padding(.vertical, 10)
                    Divider()
                    NavigationLink { ServerOverviewDetailView(section: .docker) } label: {
                        AdminNavLabel(icon: "shippingbox", title: "Docker", value: "\(v.containers.running)/\(v.containers.total - (store.ops.map { AdminOpsLogic.expectedStoppedCount($0.containers) } ?? 0)) працює", level: v.containers.unhealthy > 0 ? .critical : nil)
                    }.buttonStyle(.plain).padding(.vertical, 10)
                    Divider()
                    NavigationLink { ServerOverviewDetailView(section: .host) } label: {
                        AdminNavLabel(icon: "info.circle", title: "Хост: деталі")
                    }.buttonStyle(.plain).padding(.vertical, 10)
                }.padding(.horizontal, 16).background(Routes05Tokens.surface, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Routes05Tokens.rule, lineWidth: 1))
                if let ops = store.ops { AdminOpsServerCards(ops: ops) }
                if v.memory.swapTotalBytes > 0 {
                    AdminCard(title: "Swap", icon: "arrow.left.arrow.right") { AdminRow("Використано", "\(AdminHealthLogic.bytes(v.memory.swapUsedBytes)) із \(AdminHealthLogic.bytes(v.memory.swapTotalBytes))") }
                }
            } else {
                ContentUnavailableView("Огляд недоступний", systemImage: "exclamationmark.triangle", description: Text(store.error ?? "Спробуйте оновити ще раз."))
            }
        }
    }
}

struct AdminStoragePage: View {
    @ObservedObject var store: ServerOverviewStore
    @ObservedObject var stagingStore: StagingCleanupStore
    let items: [AdminAttention]
    var body: some View {
        AdminPage(title: "Сховище") {
            if let disk = store.overview?.disks.first {
                AdminCard(title: "Диск \(disk.mount)", icon: "internaldrive", level: AdminSection.storage.level(items)) {
                    AdminRow("Використано", "\(AdminHealthLogic.bytes(disk.usedBytes)) із \(AdminHealthLogic.bytes(disk.totalBytes)) (\(AdminHealthLogic.percent(disk.usedPercent)))")
                    AdminRow("Вільно", AdminHealthLogic.bytes(disk.availableBytes))
                    ProgressView(value: min(max(disk.usedPercent, 0), 100), total: 100).tint(disk.usedPercent > 85 ? .red : .indigo)
                }
                NavigationLink { ServerOverviewDetailView(section: .disk) } label: {
                    AdminNavLabel(icon: "chart.pie", title: "Розбивка сховища та очищення кешу").adminCard()
                }.buttonStyle(.plain)
            }
            AdminStagingCleanupCard(store: stagingStore)
        }
    }
}

struct AdminBackupsPage: View {
    @ObservedObject var store: ServerOverviewStore
    let items: [AdminAttention]
    var body: some View {
        AdminPage(title: "Резервні копії") {
            if let m = store.ops?.backups { AdminBackupManagerCards(backups: m) }
            if let b = store.backups {
                AdminCard(title: "Локальна копія", icon: "externaldrive.badge.checkmark", level: AdminSection.backups.level(items)) {
                    AdminRow("Стан", AdminSectionsLogic.backupStatusLabel(b.status), warn: b.status != "success")
                    if let date = b.lastSuccessAt { AdminRow("Остання успішна", date.formatted(date: .abbreviated, time: .shortened)) }
                    if let age = b.ageSeconds { AdminRow("Вік", AdminHealthLogic.duration(age)) }
                    if let size = b.totalSizeBytes { AdminRow("Розмір", AdminHealthLogic.bytes(size)) }
                    if store.ops?.backups == nil { AdminRow("Відновлення", b.restoreVerified ? "перевірено" : "не перевірено", warn: !b.restoreVerified) }
                }
                NavigationLink { BackupStatusDetailView(status: b, showLegacyClaims: store.ops?.backups == nil) } label: {
                    AdminNavLabel(icon: "list.bullet.rectangle", title: "Компоненти копії").adminCard()
                }.buttonStyle(.plain)
            } else {
                ContentUnavailableView("Статус копій недоступний", systemImage: "externaldrive.badge.exclamationmark", description: Text("Оновіть сторінку пізніше."))
            }
        }
    }
}

struct AdminAIPage: View {
    @ObservedObject var store: ServerOverviewStore
    @ObservedObject var providersStore: AIProvidersStore
    @ObservedObject var modelsStore: AIModelsStore
    var body: some View {
        AdminPage(title: "AI") {
            AdminAICard(openRouter: store.openRouter, azure: store.azureSpeech)
            AdminAIProvidersCard(store: providersStore)
            AdminAIModelsCard(store: modelsStore)
            VStack(spacing: 0) {
                if let o = store.openRouter {
                    NavigationLink { OpenRouterStatsDetailView(stats: o) } label: { AdminNavLabel(icon: "chart.bar", title: "OpenRouter: детально") }.buttonStyle(.plain).padding(.vertical, 10)
                }
                if store.openRouter != nil && store.azureSpeech != nil { Divider() }
                if let a = store.azureSpeech {
                    NavigationLink { AzureSpeechDetailView(stats: a) } label: { AdminNavLabel(icon: "waveform", title: "Azure Speech: детально") }.buttonStyle(.plain).padding(.vertical, 10)
                }
            }.padding(.horizontal, 16).background(Routes05Tokens.surface, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Routes05Tokens.rule, lineWidth: 1))
        }
    }
}

struct AdminOrbitPage: View {
    @ObservedObject var store: ServerOverviewStore
    var body: some View {
        AdminPage(title: "Сервіси Orbit") {
            if let orbit = store.orbitServices { AdminOrbitServicesCard(status: orbit) }
            if let agent = store.agentTelemetry, agent.available { AdminAgentCard(telemetry: agent) }
            if store.orbitServices == nil && !(store.agentTelemetry?.available ?? false) {
                ContentUnavailableView("Даних немає", systemImage: "tray", description: Text("Статус сервісів Orbit тимчасово недоступний."))
            }
        }
    }
}

/// Small pure helpers (unit-tested in CI through AdminHealthLogicTests-style checks).
enum AdminSectionsLogic {
    static func backupStatusLabel(_ status: String) -> String {
        switch status {
        case "success": return "Успішно"
        case "stale": return "Потрібна увага"
        case "failed": return "Помилка"
        case "running": return "Виконується"
        default: return "Недоступно"
        }
    }

    /// One-line hub summary per section.
    static func summary(_ section: AdminSection, overview: ServerOverview?, backups: BackupStatus?, openRouter: OpenRouterStats?, orbit: OrbitServicesStatus?, agent: AgentTelemetry?, ops: OpsStatus? = nil) -> String {
        switch section {
        case .server:
            guard let v = overview else { return "дані недоступні" }
            let frozen = ops.map { AdminOpsLogic.expectedStoppedCount($0.containers) } ?? 0
            return "\(v.containers.running)/\(v.containers.total - frozen) контейнерів · CPU " + (v.cpu.utilizationPercent.map { AdminHealthLogic.percent($0) } ?? "—") + " · памʼять " + AdminHealthLogic.percent(v.memory.usedPercent)
        case .storage:
            guard let d = overview?.disks.first else { return "дані недоступні" }
            return "диск \(AdminHealthLogic.percent(d.usedPercent)) · вільно " + AdminHealthLogic.bytes(d.availableBytes)
        case .backups:
            if let m = ops?.backups {
                let last = m.lastBackup?.updatedAt.flatMap { AdminOpsLogic.parseDate($0) }.map { AdminHealthLogic.duration(max(0, Date().timeIntervalSince($0))) + " тому" }
                return AdminOpsLogic.stateLabel(m.overall) + " · завдань: \(m.jobs.count)" + (last.map { " · копія " + $0 } ?? "")
            }
            guard let b = backups else { return "статус недоступний" }
            return backupStatusLabel(b.status) + (b.ageSeconds.map { " · " + AdminHealthLogic.duration($0) + " тому" } ?? "")
        case .ai:
            guard let o = openRouter, o.status == "ok" else { return "статистика недоступна" }
            return "сьогодні $" + String(format: "%.2f", o.today.cost) + " · 7 днів $" + String(format: "%.2f", o.last7Days.cost)
        case .orbit:
            var parts: [String] = []
            if let s = orbit?.school { parts.append(s.syncStatus == "error" ? "школа: помилка" : "школа: " + (s.ageSeconds.map { AdminHealthLogic.duration($0) + " тому" } ?? "ще не було")) }
            if let a = agent, a.available, let d = a.last24h { parts.append("агент: \(d.total) запусків за добу") }
            return parts.isEmpty ? "дані недоступні" : parts.joined(separator: " · ")
        }
    }
}


// MARK: - Operations cards (stage 2: data from /api/server/overview/ops)

struct AdminSparkline: View {
    let values: [Double]
    var tint: Color = .indigo
    var body: some View {
        GeometryReader { geo in
            Path { path in
                let n = values.count
                guard n > 1 else { return }
                for (i, v) in AdminOpsLogic.normalized(values).enumerated() {
                    let point = CGPoint(x: geo.size.width * CGFloat(i) / CGFloat(n - 1), y: geo.size.height * (1 - CGFloat(v)))
                    if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
            }.stroke(tint, lineWidth: 1.5)
        }.frame(height: 28)
    }
}

struct AdminOpsServerCards: View {
    let ops: OpsStatus
    var body: some View {
        if ops.history.count > 1 {
            AdminCard(title: "Останні 10 хвилин", icon: "waveform.path.ecg") {
                trend("Навантаження CPU (load)", ops.history.compactMap(\.cpuLoad), last: ops.history.last?.cpuLoad.map { String(format: "%.2f", $0) })
                trend("Вільна памʼять", ops.history.compactMap(\.memoryAvailable), last: ops.history.last?.memoryAvailable.map { AdminHealthLogic.bytes($0) }, tint: .teal)
                trend("Диск", ops.history.compactMap(\.diskPercent), last: ops.history.last?.diskPercent.map { AdminHealthLogic.percent($0) }, tint: .orange)
            }
        }
        AdminCard(title: "Контейнери", icon: "shippingbox") {
            ForEach(ops.containers) { c in
                AdminRow(c.name, containerState(c), warn: c.status != "running" && !c.expectedStopped)
            }
        }
        if !ops.services.isEmpty {
            AdminCard(title: "Системні служби", icon: "gearshape.2") {
                ForEach(ops.services) { sv in AdminRow(sv.name.replacingOccurrences(of: ".service", with: ""), sv.status == "running" ? "працює" : sv.status, warn: sv.status != "running") }
            }
        }
        if !ops.events.isEmpty {
            AdminCard(title: "Останні події", icon: "clock.arrow.circlepath") {
                ForEach(ops.events.prefix(8)) { e in
                    HStack(alignment: .firstTextBaseline) {
                        Text(Date(timeIntervalSince1970: e.time).formatted(date: .omitted, time: .shortened)).font(.caption.monospacedDigit()).foregroundStyle(Routes05Tokens.secondary)
                        Text(AdminOpsLogic.eventText(e)).font(.caption).foregroundStyle(Routes05Tokens.ink).lineLimit(2)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }
    private func containerState(_ c: OpsStatus.Container) -> String {
        if c.status == "running" { return (c.health == "unhealthy" ? "працює · unhealthy" : "працює") + (c.startedAt.flatMap { AdminOpsLogic.parseDate($0) }.map { " · " + AdminHealthLogic.duration(max(0, Date().timeIntervalSince($0))) } ?? "") }
        return c.expectedStopped ? "зупинено навмисно" : "зупинено"
    }
    private func trend(_ title: String, _ values: [Double], last: String?, tint: Color = .indigo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(title).font(.caption).foregroundStyle(Routes05Tokens.secondary); Spacer(); if let last { Text(last).font(.caption.monospacedDigit()) } }
            AdminSparkline(values: values, tint: tint)
        }
    }
}

struct AdminBackupManagerCards: View {
    let backups: OpsStatus.Backups
    var body: some View {
        let now = Date()
        let level = AdminOpsLogic.level(forOverall: backups.overall)
        AdminCard(title: "Завдання копіювання", icon: "calendar.badge.clock", level: level) {
            ForEach(backups.jobs) { job in
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.label).font(.subheadline.weight(.semibold)).foregroundStyle(Routes05Tokens.ink)
                    Text(AdminOpsLogic.jobLine(job, now: now)).font(.caption).foregroundStyle(job.status == "Healthy" ? Routes05Tokens.secondary : Color.orange)
                }
            }
        }
        if let last = backups.lastBackup {
            AdminCard(title: "Остання копія", icon: "externaldrive") {
                if let date = AdminOpsLogic.parseDate(last.updatedAt) { AdminRow("Час", date.formatted(date: .abbreviated, time: .shortened)) }
                if let size = last.totalSizeBytes { AdminRow("Розмір", AdminHealthLogic.bytes(size)) }
                if let total = last.componentCount, let ok = last.componentsSucceeded { AdminRow("Компоненти", "\(ok) із \(total) успішно", warn: ok < total) }
            }
        }
        if let rep = backups.replication {
            AdminCard(title: "Хмарна копія (OCI)", icon: "cloud", level: AdminOpsLogic.level(forOverall: rep.status)) {
                AdminRow("Стан", AdminOpsLogic.stateLabel(rep.status), warn: rep.status != "Healthy")
                if let v = rep.verifiedCount { AdminRow("Перевірено в хмарі", "\(v)") }
                if let u = rep.uploadedCount { AdminRow("Завантажено востаннє", "\(u)") }
                if let f = rep.failedCount, f > 0 { AdminRow("Невдалих", "\(f)", warn: true) }
                if let i = rep.incompleteCount, i > 0 { AdminRow("Незавершених", "\(i)", warn: true) }
            }
        }
        if backups.sideStore != nil || backups.secrets != nil {
            AdminCard(title: "AltStore та секрети", icon: "lock.shield") {
                if let ss = backups.sideStore {
                    AdminRow("AltStore IPA", "\(ss.localIpaCount ?? 0) файлів", warn: (ss.feedMissingCount ?? 0) > 0)
                    if let m = ss.feedMissingCount, m > 0 { AdminRow("Відсутні у фіді", "\(m)", warn: true) }
                }
                if let sec = backups.secrets, let date = AdminOpsLogic.parseDate(sec.lastArchiveAt) { AdminRow("Архів секретів", date.formatted(date: .abbreviated, time: .shortened)) }
            }
        }
        if let r = backups.retention {
            AdminCard(title: "Очищення старих копій", icon: "trash.slash") {
                AdminRow("Режим", AdminOpsLogic.retentionText(r))
                if let n = r.itemCount { AdminRow("Об'єктів у плані", "\(n)") }
                if let p = r.protectedCount { AdminRow("Захищено", "\(p)") }
                if let rv = r.reviewOnlyCount, rv > 0 { AdminRow("На розгляд", "\(rv)") }
            }
        }
        if let rel = backups.release, let id = rel.releaseId {
            AdminCard(title: "Release gate", icon: "shippingbox.and.arrow.backward") {
                AdminRow("Останній реліз", id)
                if let t = rel.target { AdminRow("Ціль", t) }
                AdminRow("Підготовка", rel.stale ? "застаріла (потрібна нова перед релізом)" : (rel.prepareState ?? "—"))
            }
        }
    }
}
