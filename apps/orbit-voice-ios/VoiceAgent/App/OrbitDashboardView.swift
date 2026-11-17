import Foundation
import SwiftUI

/// Admin hub (owner-only): overall status, what needs attention, resource gauges and one entry per section. Every section has its own page
/// (AdminSections.swift); the drill-down detail views below use the same card design.
struct OrbitDashboardView: View {
    let isSelected: Bool
    let isWidgetDiagnosticsOwner: Bool
    @StateObject private var store = ServerOverviewStore()
    @StateObject private var stagingStore = StagingCleanupStore()
    @StateObject private var aiProvidersStore = AIProvidersStore()
    @StateObject private var aiModelsStore = AIModelsStore()
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 16) {
            Routes05ContextHeader(section: "system", eyebrow: "SYSTEM / 24", title: "Admin", detail: "Read-only operational overview; actions remain guarded.", accent: Routes05Tokens.mint)
            if isWidgetDiagnosticsOwner { SchoolTasksWidgetDiagnosticsCard() }
            content
        }.padding(.bottom, 16) }.background(Routes05Tokens.canvas).routes05ContextSurface().navigationTitle("Admin · сервер").toolbar { Button { store.loadIfNeeded(force: true) } label: { Image(systemName: "arrow.clockwise") }.disabled(store.isLoading) }.refreshable { store.loadIfNeeded(force: true) }
        .sheet(isPresented: Binding(get: { stagingStore.proposal != nil }, set: { if !$0 { stagingStore.clear() } })) { StagingCleanupConfirmationView(store: stagingStore) }
        .task(id: isSelected) {
            guard isSelected else { return }
            store.loadIfNeeded()
            // Light auto-refresh while the panel is on screen; cancelled automatically when it is not selected.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                if Task.isCancelled { break }
                store.loadIfNeeded(force: true)
            }
        }
    }
    @ViewBuilder private var content: some View {
        if store.isLoading && store.overview == nil { ProgressView("Завантаження огляду…").frame(maxWidth: .infinity, minHeight: 180) }
        else if let value = store.overview {
            hub(value)
        } else { ContentUnavailableView("Огляд недоступний", systemImage: "exclamationmark.triangle", description: Text(store.error ?? "Спробуйте оновити ще раз.")); Button("Повторити") { store.loadIfNeeded(force: true) }.buttonStyle(.borderedProminent) }
    }
    @ViewBuilder private func hub(_ value: ServerOverview) -> some View {
        let inputs = value.adminInputs(backups: store.backups, openRouter: store.openRouter, azure: store.azureSpeech, orbit: store.orbitServices, agent: store.agentTelemetry, ops: store.ops)
        let items = AdminHealthLogic.attention(inputs)
        let level = AdminHealthLogic.overall(items)
        VStack(alignment: .leading, spacing: 12) {
            AdminStatusHero(level: level, summary: AdminHealthLogic.summary(items), subtitle: "main-server · \(value.containers.running)/\(value.containers.total - (store.ops.map { AdminOpsLogic.expectedStoppedCount($0.containers) } ?? 0)) контейнерів працює", updatedText: updatedText(value), isRefreshing: store.isLoading)
            if !items.isEmpty {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        attentionLink(item, items: items)
                        if item.id != items.last?.id { Divider() }
                    }
                }.padding(.horizontal, 14).background(Routes05Tokens.surface, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Routes05Tokens.rule, lineWidth: 1))
            }
            HStack(spacing: 10) {
                AdminGaugeTile(title: "CPU", icon: "cpu", valueText: value.cpu.utilizationPercent.map { AdminHealthLogic.percent($0) } ?? String(format: "%.1f", value.cpu.loadAverage.five), caption: "load \(String(format: "%.2f", value.cpu.loadAverage.five)) · \(value.cpu.logicalCpus) vCPU", fraction: value.cpu.utilizationPercent.map { $0 / 100 } ?? (value.cpu.logicalCpus > 0 ? value.cpu.loadAverage.five / Double(value.cpu.logicalCpus) : 0), level: gaugeLevel(items, "load"))
                AdminGaugeTile(title: "Памʼять", icon: "memorychip", valueText: AdminHealthLogic.percent(value.memory.usedPercent), caption: AdminHealthLogic.bytes(value.memory.availableBytes) + " вільно", fraction: value.memory.usedPercent / 100, level: gaugeLevel(items, "memory"))
                if let disk = value.disks.first {
                    AdminGaugeTile(title: "Диск", icon: "internaldrive", valueText: AdminHealthLogic.percent(disk.usedPercent), caption: AdminHealthLogic.bytes(disk.availableBytes) + " вільно", fraction: disk.usedPercent / 100, level: gaugeLevel(items, "disk"))
                }
            }
            AdminSectionHeader(title: "Розділи")
            ForEach(AdminSection.allCases) { section in
                NavigationLink { sectionPage(section, items: items) } label: {
                    AdminSectionLinkLabel(icon: section.icon, title: section.title, summary: AdminSectionsLogic.summary(section, overview: value, backups: store.backups, openRouter: store.openRouter, orbit: store.orbitServices, agent: store.agentTelemetry, ops: store.ops), level: section.level(items))
                }.buttonStyle(.plain)
            }
            Button { UIPasteboard.general.string = AdminHealthLogic.diagnosticsText(inputs, items: items) } label: { Label("Скопіювати діагностику", systemImage: "doc.on.doc").font(.subheadline) }.buttonStyle(.bordered)
        }.padding(.horizontal, 16)
    }
    @ViewBuilder private func sectionPage(_ section: AdminSection, items: [AdminAttention]) -> some View {
        switch section {
        case .server: AdminServerPage(store: store, items: items)
        case .storage: AdminStoragePage(store: store, stagingStore: stagingStore, items: items)
        case .backups: AdminBackupsPage(store: store, items: items)
        case .ai: AdminAIPage(store: store, providersStore: aiProvidersStore, modelsStore: aiModelsStore)
        case .orbit: AdminOrbitPage(store: store)
        }
    }
    private func gaugeLevel(_ items: [AdminAttention], _ id: String) -> AdminHealthLevel { items.first { $0.id == id }?.level ?? .ok }
    private func updatedText(_ value: ServerOverview) -> String {
        let age = max(0, Date().timeIntervalSince(value.generatedAt))
        return "Знімок: \(AdminHealthLogic.duration(age)) тому · автооновлення щохвилини"
    }
    /// Attention rows open the section page that explains them.
    @ViewBuilder private func attentionLink(_ item: AdminAttention, items: [AdminAttention]) -> some View {
        if let section = AdminSection.allCases.first(where: { $0.attentionIds.contains(item.id) }) {
            NavigationLink { sectionPage(section, items: items) } label: { AdminAttentionRow(item: item) }.buttonStyle(.plain)
        } else {
            AdminAttentionRow(item: item)
        }
    }
}

/// Owner-only technical state for issue #119. It contains no task, profile or account data.
private struct SchoolTasksWidgetDiagnosticsCard: View {
    @AppStorage("orbit.schoolTasksWidgetDiagnostics.load.v1") private var loadStatus = "not_run"
    @AppStorage("orbit.schoolTasksWidgetDiagnostics.load.v1.updatedAt") private var loadUpdatedAt = 0.0
    @AppStorage("orbit.schoolTasksWidgetDiagnostics.eligibility.v1") private var eligibilityStatus = "not_run"
    @AppStorage("orbit.schoolTasksWidgetDiagnostics.eligibility.v1.updatedAt") private var eligibilityUpdatedAt = 0.0
    @AppStorage("orbit.schoolTasksWidgetDiagnostics.appGroup.v1") private var appGroupStatus = "not_checked"
    @AppStorage("orbit.schoolTasksWidgetDiagnostics.appGroup.v1.updatedAt") private var appGroupUpdatedAt = 0.0
    @AppStorage("orbit.schoolTasksWidgetDiagnostics.write.v1") private var writeStatus = "not_run"
    @AppStorage("orbit.schoolTasksWidgetDiagnostics.write.v1.updatedAt") private var writeUpdatedAt = 0.0
    @AppStorage("orbit.schoolTasksWidgetDiagnostics.reload.v1") private var reloadStatus = "not_requested"
    @AppStorage("orbit.schoolTasksWidgetDiagnostics.reloadAt.v1") private var reloadAt = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("School Tasks Widget · технічний стан")
                .font(.headline.weight(.semibold))
            statusRow("Producer reads", value: loadStatus, at: loadUpdatedAt)
            statusRow("Eligibility", value: eligibilityStatus, at: eligibilityUpdatedAt)
            statusRow("App Group container (app)", value: appGroupStatus, at: appGroupUpdatedAt)
            statusRow("Snapshot write/read-back (app)", value: writeStatus, at: writeUpdatedAt)
            statusRow("WidgetKit reload request", value: reloadStatus, at: reloadAt)
            Text("Reader-код і час виклику timeline provider показуються у віджеті. Тут немає назв справ, ідентифікаторів, профілю чи секретів.")
                .font(.caption)
                .foregroundStyle(Routes05Tokens.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Routes05Tokens.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Routes05Tokens.rule, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private func statusRow(_ title: String, value: String, at timestamp: Double) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.caption.weight(.medium))
            Spacer(minLength: 8)
            Text(timestamp > 0 ? "\(value) · \(Date(timeIntervalSince1970: timestamp).formatted(date: .omitted, time: .shortened))" : value)
                .font(.caption.monospaced())
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}

struct BackupStatusDetailView: View {
    let status: BackupStatus
    var showLegacyClaims = true   // the old status file only says «cloud copy pending configuration» / «restore not verified»; the backup manager (ops) is authoritative when available
    var body: some View { ScrollView { VStack(alignment: .leading, spacing: 16) { detailSection("Резервні копії", icon: "externaldrive.badge.checkmark") { HStack { Image(systemName: status.status == "success" ? "checkmark.circle.fill" : "exclamationmark.triangle.fill").foregroundStyle(status.status == "success" ? .green : .orange); Text(statusLabel).font(.headline) }; if let date = status.lastSuccessAt { row("Остання копія", date.formatted(date: .abbreviated, time: .shortened)) }; if let age = status.ageSeconds { row("Вік", ageLabel(age)) }; if let size = status.totalSizeBytes { row("Розмір", ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .binary)) } } ; detailSection("Компоненти", icon: "shippingbox") { if status.components.isEmpty { Text("Розміри компонентів поки недоступні.").font(.subheadline).foregroundStyle(.secondary) } else { ForEach(status.components) { component in row(component.id, component.sizeBytes.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .binary) } ?? "—") } } }; if showLegacyClaims { detailSection("Хмарна копія", icon: "cloud") { row(status.remote.provider, status.remote.status == "pending_configuration" ? "Очікує налаштування" : status.remote.status) } }; detailSection("Політика", icon: "clock") { row("Розклад", "Щодня о \(status.schedule.timeUtc) UTC"); row("Автовидалення", status.local.retentionMode == "dry_run" ? "Не активне" : status.local.retentionMode) }; if showLegacyClaims { detailSection("Відновлення", icon: "arrow.uturn.backward") { Text(status.restoreVerified ? "Перевірено" : "Відновлення не перевірено").foregroundStyle(.secondary) } } }.padding(16) }.background(Routes05Tokens.canvas).navigationTitle("Резервні копії") }
    private var statusLabel: String { switch status.status { case "success": "Локальна копія успішна"; case "stale": "Копія застаріла"; case "failed": "Помилка локальної копії"; case "running": "Копія виконується"; default: "Статус недоступний" } }
    private func ageLabel(_ seconds: Double) -> String { let hours = Int(seconds) / 3600; return hours < 24 ? "\(hours) год" : "\(hours / 24) дн." }
    private func row(_ title: String, _ value: String) -> some View { HStack { Text(title); Spacer(); Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing) } }
    private func detailSection<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View { VStack(alignment: .leading, spacing: 10) { Label(title, systemImage: icon).font(.headline); content() }.frame(maxWidth: .infinity, alignment: .leading).padding().background(Routes05Tokens.surface, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Routes05Tokens.rule, lineWidth: 1)) }
}

struct OpenRouterStatsDetailView: View {
    let stats: OpenRouterStats
    var body: some View { ScrollView { VStack(alignment: .leading, spacing: 16) { detailSection("OpenRouter", icon: "chart.bar.fill") { row("Сьогодні", money(stats.today.cost)); row("7 днів", money(stats.last7Days.cost)); row("30 днів", money(stats.last30Days.cost)); row("Баланс", balanceText); }; detailSection("За весь час OpenRouter", icon: "infinity") { row("Витрати", money(stats.allTime.cost)); row("Запити", "\(stats.allTime.requests)"); row("Вхідні токени", "\(stats.allTime.inputTokens)"); row("Вихідні токени", "\(stats.allTime.outputTokens)") }; if !stats.models90Days.isEmpty { detailSection("Моделі за 3 місяці", icon: "list.number") { ForEach(stats.models90Days) { model in VStack(alignment: .leading, spacing: 2) { row(model.model, "\(model.requests ?? 0) запитів · \(money(model.cost))"); if let input = model.inputTokens, let output = model.outputTokens { Text("\(input) вхідних · \(output) вихідних токенів").font(.caption).foregroundStyle(.secondary) } } } } }; detailSection("Джерело й оновлення", icon: "clock") { row("Використання", "OpenRouter API"); row("Баланс", "OpenRouter API"); if let date = stats.updatedAt { row("Оновлено", date.formatted(date: .abbreviated, time: .shortened)) }; Text("Статистика використання та витрат надана OpenRouter для цього акаунта.").font(.caption).foregroundStyle(.secondary) } }.padding(16) }.background(Routes05Tokens.canvas).navigationTitle("OpenRouter") }
    private var balanceText: String { if stats.balance.status == "available", let amount = stats.balance.amount { return stats.balance.type == "key_remaining_limit" ? "Залишок ліміту ключа: \(money(amount))" : money(amount) }; return "Недоступний" }
    private func money(_ value: Double) -> String { "\(stats.currency == "USD" ? "$" : "")\(String(format: "%.2f", value)) \(stats.currency ?? "")".trimmingCharacters(in: .whitespaces) }
    private func row(_ title: String, _ value: String) -> some View { HStack { Text(title); Spacer(); Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing) } }
    private func detailSection<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View { VStack(alignment: .leading, spacing: 10) { Label(title, systemImage: icon).font(.headline); content() }.frame(maxWidth: .infinity, alignment: .leading).padding().background(Routes05Tokens.surface, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Routes05Tokens.rule, lineWidth: 1)) }
}

struct AzureSpeechDetailView: View {
    let stats: AzureSpeechStats
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                detailSection("Azure Speech", icon: "waveform") {
                    row("Тариф", "Безкоштовний F0"); row("Витрати", "$0.00"); row("Статус", stats.status == "ok" ? "Працює" : "Недоступно")
                    if let reset = stats.resetsAt { row("Скидання ліміту", String(reset.prefix(10))) }
                }
                ForEach(stats.tasks) { task in
                    detailSection(AzureSpeechLabels.task(task.taskId), icon: "gauge.with.dots.needle.33percent") {
                        row("Запитів цього місяця", "\(task.calls)")
                        if let tier = task.tier { row("Правило", tier.enforcement == "hard_stop" ? "Жорсткий ліміт" : "Без обліку") }
                        ForEach(AzureSpeechLabels.rows(task), id: \.title) { item in row(item.title, item.value) }
                    }
                }
                Text("Ліміти задає менеджер моделей Orbit. Після ліміту нові сесії не видаються, платних списань немає.").font(.footnote).foregroundStyle(.secondary)
            }.padding()
        }.navigationTitle("Azure Speech")
    }
    private func row(_ title: String, _ value: String) -> some View { HStack { Text(title); Spacer(); Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing) } }
    private func detailSection<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View { VStack(alignment: .leading, spacing: 10) { Label(title, systemImage: icon).font(.headline); content() }.frame(maxWidth: .infinity, alignment: .leading).padding().background(Routes05Tokens.surface, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Routes05Tokens.rule, lineWidth: 1)) }
}

struct ServerOverviewDetailView: View {
    let section: ServerOverviewDetailSection
    @StateObject private var store: ServerOverviewDetailStore
    @StateObject private var cleanupStore = CacheCleanupStore()
    init(section: ServerOverviewDetailSection) { self.section = section; _store = StateObject(wrappedValue: ServerOverviewDetailStore(section: section)) }
    var body: some View {
        ScrollView { Group { if store.isLoading && store.detail == nil { ProgressView("Завантаження…").frame(maxWidth: .infinity, minHeight: 180) } else if let detail = store.detail { detailContent(detail) } else { ContentUnavailableView("Деталі недоступні", systemImage: "exclamationmark.triangle", description: Text(store.error ?? "Спробуйте ще раз.")); Button("Повторити") { store.load(force: true) }.buttonStyle(.borderedProminent) } }.padding(16) }
            .background(Routes05Tokens.canvas).navigationTitle(section.title).navigationBarTitleDisplayMode(.inline)
            .toolbar { Button { store.load(force: true) } label: { Image(systemName: "arrow.clockwise") }.disabled(store.isLoading) }.refreshable { store.load(force: true) }.task { store.load() }
            .onChange(of: cleanupStore.result?.actionId) { _, _ in
                if cleanupStore.result?.status == "completed" { store.load(force: true) }
            }
            .sheet(isPresented: Binding(get: { cleanupStore.proposal != nil }, set: { if !$0 { cleanupStore.clearProposal() } })) { CacheCleanupConfirmationView(store: cleanupStore) }
    }
    @ViewBuilder private func detailContent(_ d: ServerOverviewDetail) -> some View {
        switch section {
        case .host: if let h = d.server { detailSection("Сервер", icon: section.icon) { row("Імʼя", h.hostname); row("ОС", h.os); if let kernel = h.kernel { row("Ядро", kernel) }; row("Архітектура", h.architecture); row("Працює", uptime(h.uptimeSeconds)); if let ms = d.collectionMs { row("Збір snapshot", "\(String(format: "%.0f", ms)) мс") }; row("Snapshot", d.generatedAt.formatted(date: .abbreviated, time: .standard)) } }
        case .docker: if let containers = d.containers { VStack(alignment: .leading, spacing: 10) { ForEach(containers) { c in NavigationLink { ContainerDetailView(container: c) } label: { containerRow(c) }.buttonStyle(.plain) } } }
        case .disk:
            if let disks = d.disks { ForEach(disks, id: \.mount) { disk in detailSection(disk.mount, icon: "internaldrive.fill") { row("Файлова система", disk.filesystem ?? "—"); row("Всього", bytes(disk.totalBytes)); row("Використано", "\(bytes(disk.usedBytes)) (\(String(format: "%.1f", disk.usedPercent))%)"); row("Доступно", bytes(disk.availableBytes)); ProgressView(value: min(max(disk.usedPercent, 0), 100), total: 100).tint(disk.usedPercent > 85 ? .red : .indigo) } } }
            if let storage = d.dockerStorage { detailSection("Docker: записувані шари", icon: "shippingbox.fill") { row("Разом", bytes(storage.writableLayerTotalBytes)); Text("Лише дані, записані всередині файлової системи контейнера. Volumes, bind mounts та спільні образи не додаються.").font(.caption).foregroundStyle(.secondary); ForEach(storage.containers.sorted { resourceSort($0.writableLayerBytes, $1.writableLayerBytes, $0.name, $1.name) }) { container in resourceRow(container, value: bytes(container.writableLayerBytes ?? 0), percent: nil) } } }
            if let storage = d.storage { storageCard(storage) }
        case .cpu:
            if let cpu = d.cpu { detailSection("CPU", icon: section.icon) { row("Модель", cpu.model ?? "Недоступно"); if let arch = cpu.architecture { row("Архітектура", arch) }; row("Логічні CPU", "\(cpu.logicalCpus) vCPU"); if let usage = cpu.utilizationPercent { row("Навантаження", "\(String(format: "%.1f", usage))%") }; row("Load 1 / 5 / 15", "\(String(format: "%.2f", cpu.loadAverage.one)) / \(String(format: "%.2f", cpu.loadAverage.five)) / \(String(format: "%.2f", cpu.loadAverage.fifteen))"); if cpu.frequency.available, let current = cpu.frequency.currentMhz { row("Частота", "\(String(format: "%.0f", current)) MHz") } else { row("Частота", "Недоступна для VM") } } }
            if let containers = d.containers { detailSection("Використання по контейнерах", icon: "shippingbox.fill") { Text("Поточний відсоток CPU Docker за інтервал вимірювання; не обовʼязково дорівнює навантаженню хоста.").font(.caption).foregroundStyle(.secondary); ForEach(containers.sorted { resourceSort($0.cpuPercent, $1.cpuPercent, $0.name, $1.name) }) { resourceRow($0, value: String(format: "%.2f%%", $0.cpuPercent ?? 0), percent: $0.cpuPercent) } } }
        case .memory:
            if let memory = d.memory { detailSection("Памʼять", icon: section.icon) { row("Всього", bytes(memory.totalBytes)); row("Використано", "\(bytes(memory.usedBytes)) (\(String(format: "%.1f", memory.usedPercent))%)"); row("Доступно", bytes(memory.availableBytes)); ProgressView(value: min(max(memory.usedPercent, 0), 100), total: 100).tint(memory.usedPercent > 85 ? .red : .indigo); row("Swap", memory.swapTotalBytes > 0 ? "\(bytes(memory.swapUsedBytes)) із \(bytes(memory.swapTotalBytes))" : "Немає") } }
            if let containers = d.containers { detailSection("Використання по контейнерах", icon: "shippingbox.fill") { Text("Показано Docker Linux working set та частку від усієї памʼяті хоста.").font(.caption).foregroundStyle(.secondary); ForEach(containers.sorted { resourceSort($0.memoryUsedBytes, $1.memoryUsedBytes, $0.name, $1.name) }) { resourceRow($0, value: "\(bytes($0.memoryUsedBytes ?? 0)) • \(String(format: "%.2f", $0.memoryHostPercent ?? 0))% хоста", percent: $0.memoryHostPercent) } } }
        }
    }
    @ViewBuilder private func storageCard(_ storage: ServerOverviewDetail.Storage) -> some View {
        detailSection("Сховище", icon: "externaldrive.fill") {
            Text("Категорії показані окремо; спільні та зведені значення не додаються між собою.")
                .font(.caption).foregroundStyle(.secondary)
            storageGlobalSection(storage.global, domain: "system", title: "Система", icon: "server.rack", ids: ["system-files", "system-cache"])
            storageGlobalSection(storage.global, domain: "development", title: "Розробка", icon: "hammer.fill")
            storageGlobalSection(storage.global, domain: "orbit_service", title: "Orbit", icon: "circle.grid.2x2.fill", ids: ["orbit-imports"])
            if let residual = storage.global.first(where: { $0.id == "host-storage-residual" }) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Інше та перехресне сховище", systemImage: "square.stack.3d.up.fill")
                        .font(.subheadline.weight(.semibold)).padding(.top, 6)
                    storageCompactRow(residual)
                    Text("Деталізація нижче входить у цю категорію або перетинається між собою. Ці значення не потрібно додавати повторно.")
                        .font(.caption).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 8) {
                        storageGlobalSection(storage.global, domain: "system", title: "Системні логи", icon: "doc.text.fill", ids: ["system-logs"])
                        storageGlobalSection(storage.global, domain: "docker", title: "Docker", icon: "shippingbox.fill")
                        if let cache = storage.global.first(where: { $0.id == "docker-build-cache" }), let reclaimable = cache.reclaimableBytes, reclaimable > 0 {
                            Button { Task { await cleanupStore.propose() } } label: {
                                Label(cleanupStore.isLoading ? "Підготовка…" : "Очистити кеш збірок", systemImage: "trash.slash")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.borderedProminent).tint(.orange).disabled(cleanupStore.isLoading)
                        } else if storage.global.contains(where: { $0.id == "docker-build-cache" }) {
                            Text("Немає кешу, який можна безпечно очистити.").font(.caption).foregroundStyle(.secondary)
                        }
                        if let error = cleanupStore.error { Text(error).font(.caption).foregroundStyle(.red) }
                        if let result = cleanupStore.result, result.status == "completed" {
                            Text("Кеш очищено. Звільнено: \(bytes(result.cacheFreedBytes ?? 0)) кешу · \(bytes(result.rootFreedBytes ?? 0)) на диску.").font(.caption).foregroundStyle(.secondary)
                        }
                        storageGlobalSection(storage.global, domain: "orbit_service", title: "Orbit", icon: "circle.grid.2x2.fill", ids: ["orbit-persistent-data", "orbit-bind-data", "orbit-project-tree"])
                        if !storage.services.isEmpty {
                            DisclosureGroup {
                                ForEach(storage.services) { service in
                                    NavigationLink { StorageServiceDetailView(service: service) } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(service.service).font(.subheadline.weight(.medium))
                                                Text(storageServiceSummary(service)).font(.caption).foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                        }
                                    }.buttonStyle(.plain)
                                }
                            } label: {
                                Label("Orbit-сервіси", systemImage: "list.bullet.rectangle")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(.leading, 10)
                }
            }
            if storage.stale { Text("Дані можуть бути застарілими.").font(.caption).foregroundStyle(.orange) }
            Text("Виміряно: \(Date(timeIntervalSince1970: storage.measuredAt).formatted(date: .abbreviated, time: .shortened)) • збір \(String(format: "%.0f", storage.collectionMs ?? 0)) мс")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }
    @ViewBuilder private func storageGlobalSection(_ items: [ServerOverviewDetail.StorageItem], domain: String, title: String, icon: String, ids: Set<String>? = nil) -> some View {
        let matching = items.filter { $0.domain == domain && (ids == nil || ids!.contains($0.id)) }.sorted { storagePriority($0) < storagePriority($1) }
        if !matching.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: icon).font(.subheadline.weight(.semibold)).padding(.top, 4)
                ForEach(matching) { item in storageCompactRow(item) }
            }
        }
    }
    private func storagePriority(_ item: ServerOverviewDetail.StorageItem) -> Int {
        switch item.id {
        case "system-files": return 0
        case "system-logs": return 1
        case "system-cache": return 2
        case "host-storage-residual": return 3
        case "orbit-persistent-data": return 0
        case "orbit-bind-data": return 1
        case "orbit-project-tree": return 2
        case "orbit-imports": return 3
        default: return 10
        }
    }
    private func storageCompactRow(_ item: ServerOverviewDetail.StorageItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(storageLabel(item)).font(.subheadline)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(item.bytes.map(bytes) ?? "Недоступно").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                if let reclaimable = item.reclaimableBytes, reclaimable > 0 { Text("Можна звільнити: \(bytes(reclaimable))").font(.caption2).foregroundStyle(.orange) }
            }
        }
    }
    private func storageServiceSummary(_ service: ServerOverviewDetail.StorageService) -> String {
        let available = service.items.filter { $0.bytes != nil }
        let image = available.first(where: { $0.type == "image" })?.bytes.map { "Образ \(bytes($0))" }
        let writable = available.first(where: { $0.type == "writable_layer" })?.bytes.map { "Шар \(bytes($0))" }
        if let image, let writable { return "\(image) · \(writable)" }
        if let image { return image }
        if let writable { return writable }
        if let persistent = available.first(where: { $0.type == "persistent_data" }), let value = persistent.bytes { return "Постійні дані · \(bytes(value))" }
        return "\(service.items.count) компонентів"
    }
    private func storageLabel(_ item: ServerOverviewDetail.StorageItem) -> String {
        switch item.label {
        case "Docker build cache": return "Кеш збірок Docker"
        case "Named volumes": return "Іменовані томи"
        case "Bind-mounted дані Orbit": return "Підключені дані Orbit"
        case "Docker-образи": return "Образи Docker"
        default: return item.label
        }
    }
    @ViewBuilder private func storageItemRow(_ item: ServerOverviewDetail.StorageItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.label).font(.subheadline)
                Spacer()
                Text(item.bytes.map(bytes) ?? "Недоступно").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                Text(storageSemantic(item)).font(.caption2).foregroundStyle(.tertiary)
                if let reclaimable = item.reclaimableBytes, reclaimable > 0 { Text("Можна звільнити: \(bytes(reclaimable))").font(.caption2).foregroundStyle(.orange) }
            }
            if let note = item.note { Text(note).font(.caption2).foregroundStyle(.tertiary) }
        }
    }
    private func storageSemantic(_ item: ServerOverviewDetail.StorageItem) -> String {
        let attribution = item.attribution == "shared" ? "спільне" : item.attribution == "exclusive" ? "ексклюзивне" : item.attribution == "global" ? "глобальне" : item.attribution
        let measurement = item.measurement == "docker_reported" ? "Docker" : item.measurement == "filesystem_measured" ? "виміряно на диску" : item.measurement
        return "\(attribution) • \(measurement)\(item.rollup == true ? " • зведене" : "")"
    }
    private func detailSection<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View { VStack(alignment: .leading, spacing: 10) { Label(title, systemImage: icon).font(.headline); content() }.frame(maxWidth: .infinity, alignment: .leading).padding().background(Routes05Tokens.surface, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Routes05Tokens.rule, lineWidth: 1)) }
    private func row(_ title: String, _ value: String) -> some View { LabeledContent(title, value: value).font(.subheadline) }
    private func bytes(_ value: Double) -> String { value <= 0 ? "0 KB" : ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .binary) }
    private func uptime(_ seconds: Double) -> String { let d = Int(seconds); return "\(d / 86400) дн. \((d % 86400) / 3600) год." }
    private func containerRow(_ c: ServerOverviewDetail.Container) -> some View { HStack(spacing: 10) { Image(systemName: c.status == "running" ? "circle.fill" : "circle").foregroundStyle(c.status == "running" ? .green : .orange).font(.caption); VStack(alignment: .leading) { Text(c.name).font(.headline); Text("\(c.service ?? c.project ?? "") • \(c.health ?? c.status)").font(.caption).foregroundStyle(.secondary) }; Spacer(); VStack(alignment: .trailing, spacing: 2) { if let cpu = c.cpuPercent { Text(String(format: "%.2f%% CPU", cpu)).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }; if let memory = c.memoryUsedBytes { Text(bytes(memory)).font(.caption.monospacedDigit()).foregroundStyle(.secondary) } }; Image(systemName: "chevron.right").foregroundStyle(.tertiary) }.padding().background(Routes05Tokens.surface, in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Routes05Tokens.rule, lineWidth: 1)) }
    private func resourceRow(_ c: ServerOverviewDetail.Container, value: String, percent: Double?) -> some View { VStack(alignment: .leading, spacing: 4) { HStack { Text(c.name).font(.subheadline.weight(.medium)); Spacer(); Text(value).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary) }; if let percent { ProgressView(value: min(max(percent, 0), 100), total: 100).tint(percent > 85 ? .red : .indigo) } } }
    private func resourceSort(_ lhs: Double?, _ rhs: Double?, _ lhsName: String, _ rhsName: String) -> Bool { switch (lhs, rhs) { case let (left?, right?): return left == right ? lhsName < rhsName : left > right; case (_?, nil): return true; case (nil, _?): return false; default: return lhsName < rhsName } }
}

struct CacheCleanupConfirmationView: View {
    @ObservedObject var store: CacheCleanupStore
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                if let result = store.result {
                    let completed = result.status == "completed"
                    let nothingToDo = result.status == "nothing_to_do"
                    Label(completed ? "Кеш очищено" : nothingToDo ? "Немає кешу для очищення" : "Не вдалося очистити кеш", systemImage: completed ? "checkmark.circle.fill" : nothingToDo ? "checkmark.circle" : "exclamationmark.triangle.fill").font(.title3.weight(.semibold))
                    if completed {
                        if let value = result.cacheFreedBytes { Text("Звільнено кешу: \(bytes(value))") }
                        if let value = result.rootFreedBytes { Text("Вільного місця стало більше на: \(bytes(value))") }
                        if let value = result.after?.cacheBytes { Text("Кеш збірок зараз: \(bytes(value))") }
                        if let value = result.after?.reclaimableBytes { Text("Можна звільнити: \(bytes(value))") }
                    } else if nothingToDo { Text("Свіжа перевірка не знайшла невикористовуваного кешу. Жодної операції очищення не виконано.").foregroundStyle(.secondary) }
                    else { Text("Операцію не підтверджено після перевірки стану сервера.").foregroundStyle(.secondary) }
                    Spacer()
                    Button("Готово") { store.clearProposal() }.buttonStyle(.borderedProminent)
                } else if let proposal = store.proposal {
                    Text("Буде очищено лише невикористовуваний BuildKit-кеш.").font(.headline)
                    Text("Контейнери, образи, томи та постійні дані не видаляються.").foregroundStyle(.secondary)
                    LabeledContent("Поточний кеш", value: bytes(proposal.cacheBytes ?? 0))
                    LabeledContent("Можна звільнити", value: bytes(proposal.reclaimableBytes))
                    Spacer()
                    HStack {
                        Button("Скасувати") { Task { await store.cancel() } }.buttonStyle(.bordered)
                        Spacer()
                        Button("Очистити кеш") { Task { await store.confirm() } }.buttonStyle(.borderedProminent).tint(.red).disabled(store.isLoading)
                    }
                }
            }.padding(20).navigationTitle("Кеш збірок Docker").navigationBarTitleDisplayMode(.inline)
        }
    }
    private func bytes(_ value: Double) -> String { value <= 0 ? "0 KB" : ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .binary) }
}

struct StorageServiceDetailView: View {
    let service: ServerOverviewDetail.StorageService
    var body: some View {
        List {
            Section("Компоненти сховища") {
                ForEach(service.items) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(item.label).font(.subheadline)
                            Spacer()
                            Text(item.bytes.map(bytes) ?? "Недоступно").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        Text(semantic(item)).font(.caption).foregroundStyle(.secondary)
                        if let reclaimable = item.reclaimableBytes, reclaimable > 0 { Text("Можна звільнити: \(bytes(reclaimable))").font(.caption).foregroundStyle(.orange) }
                        if let note = item.note { Text(note).font(.caption).foregroundStyle(.tertiary) }
                    }
                    .padding(.vertical, 3)
                }
            }
            Section("Про вимірювання") {
                Text("Компоненти можуть бути спільними або перетинатися, тому їх не слід підсумовувати без урахування семантики.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(service.service)
        .navigationBarTitleDisplayMode(.inline)
    }
    private func bytes(_ value: Double) -> String { value <= 0 ? "0 KB" : ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .binary) }
    private func semantic(_ item: ServerOverviewDetail.StorageItem) -> String {
        let attribution = item.attribution == "shared" ? "Спільне" : item.attribution == "exclusive" ? "Ексклюзивне" : item.attribution == "global" ? "Глобальне" : item.attribution
        let measurement = item.measurement == "docker_reported" ? "Docker" : item.measurement == "filesystem_measured" ? "Виміряно на диску" : item.measurement
        return "\(attribution) · \(measurement)\(item.additive ? " · додається" : " · не додається")"
    }
}

struct ContainerDetailView: View {
    let container: ServerOverviewDetail.Container
    var body: some View {
        List { Section("Стан") { LabeledContent("Назва", value: container.name); LabeledContent("Статус", value: container.status); if let health = container.health { LabeledContent("Здоровʼя", value: health) }; if let started = container.startedAt { LabeledContent("Запущено", value: started) } }; if container.cpuPercent != nil || container.memoryUsedBytes != nil || container.writableLayerBytes != nil { Section("Ресурси") { if let cpu = container.cpuPercent { LabeledContent("CPU", value: String(format: "%.2f%%", cpu)) }; if let memory = container.memoryUsedBytes { LabeledContent("Памʼять", value: ByteCountFormatter.string(fromByteCount: Int64(memory), countStyle: .binary)); if let hostPercent = container.memoryHostPercent { LabeledContent("Частка памʼяті хоста", value: String(format: "%.2f%%", hostPercent)) } }; if let writable = container.writableLayerBytes { LabeledContent("Записуваний шар", value: ByteCountFormatter.string(fromByteCount: Int64(writable), countStyle: .binary)); Text("Volumes, bind mounts і спільні образи не включено.").font(.caption).foregroundStyle(.secondary) } } }; Section("Образ") { if let image = container.image { Text(image).textSelection(.enabled) }; if let service = container.service { LabeledContent("Compose service", value: service) }; if let project = container.project { LabeledContent("Проєкт", value: project) }; if let policy = container.restartPolicy { LabeledContent("Restart policy", value: policy) } }; if !container.ports.isEmpty { Section("Порти") { ForEach(container.ports.indices, id: \.self) { i in let p = container.ports[i]; Text("\(p.hostIp ?? "*"):\(p.host ?? "—") → \(p.container ?? "—")") } } }; if !container.networks.isEmpty { Section("Мережі") { ForEach(container.networks, id: \.self) { Text($0) } } }; if !container.mounts.isEmpty { Section("Підключення") { ForEach(container.mounts.indices, id: \.self) { i in let m = container.mounts[i]; LabeledContent(m.name ?? "Mount", value: m.destination ?? "—") } } } }
            .navigationTitle(container.name).navigationBarTitleDisplayMode(.inline)
    }
}
