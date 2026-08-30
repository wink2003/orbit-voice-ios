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
        else if let value = store.overview { header(value); section("Docker", icon: "shippingbox.fill") { grid([("Запущено", "\(value.containers.running)"),("Зупинено", "\(value.containers.stopped)"),("Всього", "\(value.containers.total)"),("Проєктів", "\(value.containers.composeProjects)")]) }; if let disk = value.disks.first { resource("Диск", icon: "internaldrive.fill", used: disk.usedBytes, total: disk.totalBytes, available: disk.availableBytes, percent: disk.usedPercent) }; section("CPU", icon: "cpu") { Text(value.cpu.model ?? "CPU").font(.headline); Text("\(value.cpu.logicalCpus) vCPU").foregroundStyle(.secondary); if let usage = value.cpu.utilizationPercent { LabeledContent("Навантаження", value: "\(usage, specifier: "%.1f")%") }; LabeledContent("Load", value: "\(value.cpu.loadAverage.one, specifier: "%.2f") / \(value.cpu.loadAverage.five, specifier: "%.2f") / \(value.cpu.loadAverage.fifteen, specifier: "%.2f")") }; resource("Оперативна памʼять", icon: "memorychip.fill", used: value.memory.usedBytes, total: value.memory.totalBytes, available: value.memory.availableBytes, percent: value.memory.usedPercent); if value.memory.swapTotalBytes > 0 { section("Swap", icon: "arrow.left.arrow.right") { Text("\(bytes(value.memory.swapUsedBytes)) із \(bytes(value.memory.swapTotalBytes))") } } }
        else { ContentUnavailableView("Огляд недоступний", systemImage: "exclamationmark.triangle", description: Text(store.error ?? "Спробуйте оновити ще раз.")); Button("Повторити") { store.loadIfNeeded(force: true) }.buttonStyle(.borderedProminent) }
    }
    private func header(_ v: ServerOverview) -> some View { section("main-server", icon: "server.rack") { Text("\(v.server.os) • \(v.server.architecture.uppercased())").foregroundStyle(.secondary); Text("Працює: \(uptime(v.server.uptimeSeconds))").foregroundStyle(.secondary); Text("Оновлено: \(v.generatedAt.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.tertiary) } }
    private func resource(_ title: String, icon: String, used: Double, total: Double, available: Double, percent: Double) -> some View { section(title, icon: icon) { Text("Використано \(bytes(used)) із \(bytes(total))").font(.headline); Text("Доступно \(bytes(available))").foregroundStyle(.secondary); ProgressView(value: min(max(percent, 0), 100), total: 100).tint(percent > 85 ? .red : .indigo); Text("\(percent, specifier: "%.0f")%").font(.caption).foregroundStyle(.secondary) } }
    private func section<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View { VStack(alignment: .leading, spacing: 10) { Label(title, systemImage: icon).font(.headline); content() }.frame(maxWidth: .infinity, alignment: .leading).padding().background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous)) }
    private func grid(_ values: [(String,String)]) -> some View { LazyVGrid(columns: [GridItem(.flexible()),GridItem(.flexible())], alignment: .leading, spacing: 12) { ForEach(values, id: \.0) { Text("\($0.0)\n\($0.1)").font(.subheadline) } } }
    private func bytes(_ value: Double) -> String { ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .binary) }
    private func uptime(_ seconds: Double) -> String { let d=Int(seconds); return "\(d / 86400) дн. \((d % 86400) / 3600) год." }
}
