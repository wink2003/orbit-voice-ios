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
            if let backups = store.backups {
                NavigationLink { BackupStatusDetailView(status: backups) } label: { backupCard(backups) }.buttonStyle(.plain)
            } else {
                section("Резервні копії", icon: "externaldrive.badge.checkmark") { Text("Статус недоступний").foregroundStyle(.secondary) }
            }
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
    private func backupCard(_ backup: BackupStatus) -> some View { section("Резервні копії", icon: "externaldrive.badge.checkmark") { HStack { Image(systemName: backup.status == "success" ? "checkmark.circle.fill" : "exclamationmark.triangle.fill").foregroundStyle(backup.status == "success" ? .green : .orange); Text(backupStatusLabel(backup.status)).font(.subheadline.weight(.medium)) }; if let date = backup.lastSuccessAt { Text("Остання копія: \(date.formatted(date: .abbreviated, time: .shortened))").font(.subheadline) }; Text(backup.remote.status == "pending_configuration" ? "Локально · Хмара: очікує налаштування" : "Локально · Хмара: \(backup.remote.status)").font(.caption).foregroundStyle(.secondary); Text("Щодня о \(backup.schedule.timeUtc) UTC").font(.caption).foregroundStyle(.secondary) } }
    private func backupStatusLabel(_ status: String) -> String { switch status { case "success": "Успішно"; case "stale": "Потрібна увага"; case "failed": "Помилка"; case "running": "Виконується"; default: "Недоступно" } }
}

struct BackupStatusDetailView: View {
    let status: BackupStatus
    var body: some View { ScrollView { VStack(alignment: .leading, spacing: 16) { detailSection("Резервні копії", icon: "externaldrive.badge.checkmark") { HStack { Image(systemName: status.status == "success" ? "checkmark.circle.fill" : "exclamationmark.triangle.fill").foregroundStyle(status.status == "success" ? .green : .orange); Text(statusLabel).font(.headline) }; if let date = status.lastSuccessAt { row("Остання копія", date.formatted(date: .abbreviated, time: .shortened)) }; if let age = status.ageSeconds { row("Вік", ageLabel(age)) }; if let size = status.totalSizeBytes { row("Розмір", ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .binary)) } } ; detailSection("Компоненти", icon: "shippingbox") { if status.components.isEmpty { Text("Розміри компонентів поки недоступні.").font(.subheadline).foregroundStyle(.secondary) } else { ForEach(status.components) { component in row(component.id, component.sizeBytes.map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .binary) } ?? "—") } } }; detailSection("Хмарна копія", icon: "cloud") { row(status.remote.provider, status.remote.status == "pending_configuration" ? "Очікує налаштування" : status.remote.status) }; detailSection("Політика", icon: "clock") { row("Розклад", "Щодня о \(status.schedule.timeUtc) UTC"); row("Локальне зберігання", "\(status.local.retentionDays) днів"); row("Автовидалення", status.local.retentionMode == "dry_run" ? "Не активне" : status.local.retentionMode) }; detailSection("Відновлення", icon: "arrow.uturn.backward") { Text(status.restoreVerified ? "Перевірено" : "Відновлення не перевірено").foregroundStyle(.secondary) } }.padding(16) }.background(Color(uiColor: .systemGroupedBackground)).navigationTitle("Резервні копії") }
    private var statusLabel: String { switch status.status { case "success": "Локальна копія успішна"; case "stale": "Копія застаріла"; case "failed": "Помилка локальної копії"; case "running": "Копія виконується"; default: "Статус недоступний" } }
    private func ageLabel(_ seconds: Double) -> String { let hours = Int(seconds) / 3600; return hours < 24 ? "\(hours) год" : "\(hours / 24) дн." }
    private func row(_ title: String, _ value: String) -> some View { HStack { Text(title); Spacer(); Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing) } }
    private func detailSection<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View { VStack(alignment: .leading, spacing: 10) { Label(title, systemImage: icon).font(.headline); content() }.frame(maxWidth: .infinity, alignment: .leading).padding().background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous)) }
}

struct ServerOverviewDetailView: View {
    let section: ServerOverviewDetailSection
    @StateObject private var store: ServerOverviewDetailStore
    @StateObject private var cleanupStore = CacheCleanupStore()
    init(section: ServerOverviewDetailSection) { self.section = section; _store = StateObject(wrappedValue: ServerOverviewDetailStore(section: section)) }
    var body: some View {
        ScrollView { Group { if store.isLoading && store.detail == nil { ProgressView("Завантаження…").frame(maxWidth: .infinity, minHeight: 180) } else if let detail = store.detail { detailContent(detail) } else { ContentUnavailableView("Деталі недоступні", systemImage: "exclamationmark.triangle", description: Text(store.error ?? "Спробуйте ще раз.")); Button("Повторити") { store.load(force: true) }.buttonStyle(.borderedProminent) } }.padding(16) }
            .background(Color(uiColor: .systemGroupedBackground)).navigationTitle(section.title).navigationBarTitleDisplayMode(.inline)
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
    private func detailSection<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View { VStack(alignment: .leading, spacing: 10) { Label(title, systemImage: icon).font(.headline); content() }.frame(maxWidth: .infinity, alignment: .leading).padding().background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous)) }
    private func row(_ title: String, _ value: String) -> some View { LabeledContent(title, value: value).font(.subheadline) }
    private func bytes(_ value: Double) -> String { value <= 0 ? "0 KB" : ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .binary) }
    private func uptime(_ seconds: Double) -> String { let d = Int(seconds); return "\(d / 86400) дн. \((d % 86400) / 3600) год." }
    private func containerRow(_ c: ServerOverviewDetail.Container) -> some View { HStack(spacing: 10) { Image(systemName: c.status == "running" ? "circle.fill" : "circle").foregroundStyle(c.status == "running" ? .green : .orange).font(.caption); VStack(alignment: .leading) { Text(c.name).font(.headline); Text("\(c.service ?? c.project ?? "") • \(c.health ?? c.status)").font(.caption).foregroundStyle(.secondary) }; Spacer(); VStack(alignment: .trailing, spacing: 2) { if let cpu = c.cpuPercent { Text(String(format: "%.2f%% CPU", cpu)).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }; if let memory = c.memoryUsedBytes { Text(bytes(memory)).font(.caption.monospacedDigit()).foregroundStyle(.secondary) } }; Image(systemName: "chevron.right").foregroundStyle(.tertiary) }.padding().background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous)) }
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
