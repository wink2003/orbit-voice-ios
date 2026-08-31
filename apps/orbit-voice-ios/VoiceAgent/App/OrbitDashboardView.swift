import Foundation
import SwiftUI

struct OrbitDashboardView: View {
    let isSelected: Bool
    @StateObject private var store = ServerOverviewStore()
    var body: some View {
        NavigationStack { ScrollView { VStack(alignment: .leading, spacing: 16) { content }.padding(16) }.background(Color(uiColor: .systemGroupedBackground)).navigationTitle("Огляд").toolbar { Button { store.loadIfNeeded(force: true) } label: { Image(systemName: "arrow.clockwise") }.disabled(store.isLoading) }.refreshable { store.loadIfNeeded(force: true) } }
        .task(id: isSelected) { if isSelected { store.loadIfNeeded() } }
    }
    @ViewBuilder private var content: some View {
        if store.isLoading && store.overview == nil { ProgressView("Завантаження огляду…").frame(maxWidth: .infinity, minHeight: 180) }
        else if let value = store.overview {
            NavigationLink { ServerOverviewDetailView(section: .host) } label: { header(value) }.buttonStyle(.plain)
            NavigationLink { ServerOverviewDetailView(section: .docker) } label: { section("Docker", icon: "shippingbox.fill") { grid([("Запущено", "\(value.containers.running)"), ("Зупинено", "\(value.containers.stopped)"), ("Всього", "\(value.containers.total)"), ("Проєктів", "\(value.containers.composeProjects)")]) } }.buttonStyle(.plain)
            if let disk = value.disks.first { NavigationLink { ServerOverviewDetailView(section: .disk) } label: { resource("Диск", icon: "internaldrive.fill", used: disk.usedBytes, total: disk.totalBytes, available: disk.availableBytes, percent: disk.usedPercent) }.buttonStyle(.plain) }
            NavigationLink { ServerOverviewDetailView(section: .cpu) } label: { section("CPU", icon: "cpu") { Text(value.cpu.model ?? "CPU").font(.headline); Text("\(value.cpu.logicalCpus) vCPU").foregroundStyle(.secondary); if let usage = value.cpu.utilizationPercent { LabeledContent("Навантаження", value: "\(String(format: "%.1f", usage))%") }; LabeledContent("Load", value: "\(String(format: "%.2f", value.cpu.loadAverage.one)) / \(String(format: "%.2f", value.cpu.loadAverage.five)) / \(String(format: "%.2f", value.cpu.loadAverage.fifteen))") } }.buttonStyle(.plain)
            NavigationLink { ServerOverviewDetailView(section: .memory) } label: { resource("Оперативна памʼять", icon: "memorychip.fill", used: value.memory.usedBytes, total: value.memory.totalBytes, available: value.memory.availableBytes, percent: value.memory.usedPercent) }.buttonStyle(.plain)
            if value.memory.swapTotalBytes > 0 { section("Swap", icon: "arrow.left.arrow.right") { Text("\(bytes(value.memory.swapUsedBytes)) із \(bytes(value.memory.swapTotalBytes))") } }
        } else { ContentUnavailableView("Огляд недоступний", systemImage: "exclamationmark.triangle", description: Text(store.error ?? "Спробуйте оновити ще раз.")); Button("Повторити") { store.loadIfNeeded(force: true) }.buttonStyle(.borderedProminent) }
    }
    private func header(_ v: ServerOverview) -> some View { section("main-server", icon: "server.rack") { Text("\(v.server.os) • \(v.server.architecture.uppercased())").foregroundStyle(.secondary); Text("Працює: \(uptime(v.server.uptimeSeconds))").foregroundStyle(.secondary); Text("Оновлено: \(v.generatedAt.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.tertiary) } }
    private func resource(_ title: String, icon: String, used: Double, total: Double, available: Double, percent: Double) -> some View { section(title, icon: icon) { Text("Використано \(bytes(used)) із \(bytes(total))").font(.headline); Text("Доступно \(bytes(available))").foregroundStyle(.secondary); ProgressView(value: min(max(percent, 0), 100), total: 100).tint(percent > 85 ? .red : .indigo); Text("\(String(format: "%.0f", percent))%").font(.caption).foregroundStyle(.secondary) } }
    private func section<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View { VStack(alignment: .leading, spacing: 10) { Label(title, systemImage: icon).font(.headline); content() }.frame(maxWidth: .infinity, alignment: .leading).padding().background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous)).overlay(alignment: .trailing) { Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary).padding(.trailing, 14) } }
    private func grid(_ values: [(String, String)]) -> some View { LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) { ForEach(values, id: \.0) { Text("\($0.0)\n\($0.1)").font(.subheadline) } } }
    private func bytes(_ value: Double) -> String { ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .binary) }
    private func uptime(_ seconds: Double) -> String { let d = Int(seconds); return "\(d / 86400) дн. \((d % 86400) / 3600) год." }
}

struct ServerOverviewDetailView: View {
    let section: ServerOverviewDetailSection
    @StateObject private var store: ServerOverviewDetailStore
    init(section: ServerOverviewDetailSection) { self.section = section; _store = StateObject(wrappedValue: ServerOverviewDetailStore(section: section)) }
    var body: some View {
        ScrollView { Group { if store.isLoading && store.detail == nil { ProgressView("Завантаження…").frame(maxWidth: .infinity, minHeight: 180) } else if let detail = store.detail { detailContent(detail) } else { ContentUnavailableView("Деталі недоступні", systemImage: "exclamationmark.triangle", description: Text(store.error ?? "Спробуйте ще раз.")); Button("Повторити") { store.load(force: true) }.buttonStyle(.borderedProminent) } }.padding(16) }
            .background(Color(uiColor: .systemGroupedBackground)).navigationTitle(section.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { Button { store.load(force: true) } label: { Image(systemName: "arrow.clockwise") }.disabled(store.isLoading) }.refreshable { store.load(force: true) }.task { store.load() }
    }
    @ViewBuilder private func detailContent(_ d: ServerOverviewDetail) -> some View {
        switch section {
        case .host: if let h = d.server { detailSection("Сервер", icon: section.icon) { row("Імʼя", h.hostname); row("ОС", h.os); if let kernel = h.kernel { row("Ядро", kernel) }; row("Архітектура", h.architecture); row("Працює", uptime(h.uptimeSeconds)); if let ms = d.collectionMs { row("Збір snapshot", "\(String(format: "%.0f", ms)) мс") }; row("Snapshot", d.generatedAt.formatted(date: .abbreviated, time: .standard)) } }
        case .docker: if let containers = d.containers { VStack(alignment: .leading, spacing: 10) { ForEach(containers) { c in NavigationLink { ContainerDetailView(container: c) } label: { containerRow(c) }.buttonStyle(.plain) } } }
        case .disk: if let disks = d.disks { ForEach(disks, id: \.mount) { disk in detailSection(disk.mount, icon: "internaldrive.fill") { row("Файлова система", disk.filesystem ?? "—"); row("Всього", bytes(disk.totalBytes)); row("Використано", "\(bytes(disk.usedBytes)) (\(String(format: "%.1f", disk.usedPercent))%)"); row("Доступно", bytes(disk.availableBytes)); ProgressView(value: min(max(disk.usedPercent, 0), 100), total: 100).tint(disk.usedPercent > 85 ? .red : .indigo) } } }
        case .cpu: if let cpu = d.cpu { detailSection("CPU", icon: section.icon) { row("Модель", cpu.model ?? "Недоступно"); if let arch = cpu.architecture { row("Архітектура", arch) }; row("Логічні CPU", "\(cpu.logicalCpus) vCPU"); if let usage = cpu.utilizationPercent { row("Навантаження", "\(String(format: "%.1f", usage))%") }; row("Load 1 / 5 / 15", "\(String(format: "%.2f", cpu.loadAverage.one)) / \(String(format: "%.2f", cpu.loadAverage.five)) / \(String(format: "%.2f", cpu.loadAverage.fifteen))"); if cpu.frequency.available, let current = cpu.frequency.currentMhz { row("Частота", "\(String(format: "%.0f", current)) MHz") } else { row("Частота", "Недоступна для VM") } } }
        case .memory: if let memory = d.memory { detailSection("Памʼять", icon: section.icon) { row("Всього", bytes(memory.totalBytes)); row("Використано", "\(bytes(memory.usedBytes)) (\(String(format: "%.1f", memory.usedPercent))%)"); row("Доступно", bytes(memory.availableBytes)); ProgressView(value: min(max(memory.usedPercent, 0), 100), total: 100).tint(memory.usedPercent > 85 ? .red : .indigo); row("Swap", memory.swapTotalBytes > 0 ? "\(bytes(memory.swapUsedBytes)) із \(bytes(memory.swapTotalBytes))" : "Немає") } }
        }
    }
    private func detailSection<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View { VStack(alignment: .leading, spacing: 10) { Label(title, systemImage: icon).font(.headline); content() }.frame(maxWidth: .infinity, alignment: .leading).padding().background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous)) }
    private func row(_ title: String, _ value: String) -> some View { LabeledContent(title, value: value).font(.subheadline) }
    private func bytes(_ value: Double) -> String { ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .binary) }
    private func uptime(_ seconds: Double) -> String { let d = Int(seconds); return "\(d / 86400) дн. \((d % 86400) / 3600) год." }
    private func containerRow(_ c: ServerOverviewDetail.Container) -> some View { HStack(spacing: 10) { Image(systemName: c.status == "running" ? "circle.fill" : "circle").foregroundStyle(c.status == "running" ? .green : .orange).font(.caption); VStack(alignment: .leading) { Text(c.name).font(.headline); Text("\(c.service ?? c.project ?? "") • \(c.health ?? c.status)").font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary) }.padding().background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous)) }
}

struct ContainerDetailView: View {
    let container: ServerOverviewDetail.Container
    var body: some View {
        List { Section("Стан") { LabeledContent("Назва", value: container.name); LabeledContent("Статус", value: container.status); if let health = container.health { LabeledContent("Здоровʼя", value: health) }; if let started = container.startedAt { LabeledContent("Запущено", value: started) } }; Section("Образ") { if let image = container.image { Text(image).textSelection(.enabled) }; if let service = container.service { LabeledContent("Compose service", value: service) }; if let project = container.project { LabeledContent("Проєкт", value: project) }; if let policy = container.restartPolicy { LabeledContent("Restart policy", value: policy) } }; if !container.ports.isEmpty { Section("Порти") { ForEach(container.ports.indices, id: \.self) { i in let p = container.ports[i]; Text("\(p.hostIp ?? "*"):\(p.host ?? "—") → \(p.container ?? "—")") } } }; if !container.networks.isEmpty { Section("Мережі") { ForEach(container.networks, id: \.self) { Text($0) } } }; if !container.mounts.isEmpty { Section("Підключення") { ForEach(container.mounts.indices, id: \.self) { i in let m = container.mounts[i]; LabeledContent(m.name ?? "Mount", value: m.destination ?? "—") } } } }
            .navigationTitle(container.name).navigationBarTitleDisplayMode(.inline)
    }
}
