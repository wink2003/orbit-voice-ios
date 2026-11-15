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
                        AdminNavLabel(icon: "shippingbox", title: "Docker", value: "\(v.containers.running)/\(v.containers.total) працює", level: v.containers.unhealthy > 0 ? .critical : nil)
                    }.buttonStyle(.plain).padding(.vertical, 10)
                    Divider()
                    NavigationLink { ServerOverviewDetailView(section: .host) } label: {
                        AdminNavLabel(icon: "info.circle", title: "Хост: деталі")
                    }.buttonStyle(.plain).padding(.vertical, 10)
                }.padding(.horizontal, 16).background(Routes05Tokens.surface, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Routes05Tokens.rule, lineWidth: 1))
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
            if let b = store.backups {
                AdminCard(title: "Локальна копія", icon: "externaldrive.badge.checkmark", level: AdminSection.backups.level(items)) {
                    AdminRow("Стан", AdminSectionsLogic.backupStatusLabel(b.status), warn: b.status != "success")
                    if let date = b.lastSuccessAt { AdminRow("Остання успішна", date.formatted(date: .abbreviated, time: .shortened)) }
                    if let age = b.ageSeconds { AdminRow("Вік", AdminHealthLogic.duration(age)) }
                    if let size = b.totalSizeBytes { AdminRow("Розмір", AdminHealthLogic.bytes(size)) }
                    AdminRow("Відновлення", b.restoreVerified ? "перевірено" : "не перевірено", warn: !b.restoreVerified)
                }
                NavigationLink { BackupStatusDetailView(status: b) } label: {
                    AdminNavLabel(icon: "list.bullet.rectangle", title: "Компоненти, політика, хмарна копія").adminCard()
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
    static func summary(_ section: AdminSection, overview: ServerOverview?, backups: BackupStatus?, openRouter: OpenRouterStats?, orbit: OrbitServicesStatus?, agent: AgentTelemetry?) -> String {
        switch section {
        case .server:
            guard let v = overview else { return "дані недоступні" }
            return "\(v.containers.running)/\(v.containers.total) контейнерів · CPU " + (v.cpu.utilizationPercent.map { AdminHealthLogic.percent($0) } ?? "—") + " · памʼять " + AdminHealthLogic.percent(v.memory.usedPercent)
        case .storage:
            guard let d = overview?.disks.first else { return "дані недоступні" }
            return "диск \(AdminHealthLogic.percent(d.usedPercent)) · вільно " + AdminHealthLogic.bytes(d.availableBytes)
        case .backups:
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
