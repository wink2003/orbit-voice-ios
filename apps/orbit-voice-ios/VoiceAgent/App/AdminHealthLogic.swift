import Foundation

/// Pure rules for the Admin panel "what needs attention" list. No networking, no UI: unit-tested in CI.
/// Thresholds are deliberate and documented here so the panel never alarms on things that are normal
/// (e.g. intentionally stopped containers are INFO, not a problem).
enum AdminHealthLevel: Int, Comparable {
    case ok = 0, info = 1, warning = 2, critical = 3
    static func < (lhs: AdminHealthLevel, rhs: AdminHealthLevel) -> Bool { lhs.rawValue < rhs.rawValue }
    var headline: String {
        switch self {
        case .ok: return "Усе гаразд"
        case .info: return "Усе працює"
        case .warning: return "Є що перевірити"
        case .critical: return "Потрібна увага"
        }
    }
}

struct AdminAttention: Identifiable, Equatable {
    let id: String
    let level: AdminHealthLevel
    let title: String
    let detail: String
    /// Optional deep link target in the panel: host, docker, disk, cpu, memory, backups, ai.
    let target: String?
}

struct AdminHealthInputs {
    var generatedAt: Date?
    var now: Date
    var diskUsedPercent: Double?
    var diskAvailableBytes: Double?
    var memoryUsedPercent: Double?
    var swapTotalBytes: Double = 0
    var swapUsedBytes: Double = 0
    var load5: Double?
    var logicalCpus: Int = 0
    var containersTotal: Int = 0
    var containersRunning: Int = 0
    var containersUnhealthy: Int = 0
    var backupStatus: String?          // success | stale | failed | running | unknown | nil (not loaded)
    var backupAgeSeconds: Double?
    var restoreVerified: Bool?
    var openRouterStatus: String?      // ok | unavailable | nil
    var azureWorstFraction: Double?    // highest used/limit across Azure speech limits
    // Orbit services (nil = not loaded / not configured: never alarms)
    var schoolSyncStatus: String?      // idle | running | error
    var schoolSyncAgeSeconds: Double?
    var schoolSyncError: String?
    var emailAgeSeconds: Double?
    var emailLastError: String?
    var emailQuarantined: Int?
    var weeklyReportFailed: Int?
    // Agent telemetry (nil = not loaded)
    var agentRuns24h: Int?
    var agentFailed24h: Int?
    var agentP95Seconds24h: Double?
    var agentFallbackAttempts7d: Int?
}

enum AdminHealthLogic {
    static let diskWarnPercent = 80.0, diskCriticalPercent = 90.0, diskCriticalFreeBytes = 3.0 * 1_073_741_824
    static let memoryWarnPercent = 85.0, memoryCriticalPercent = 92.0
    static let swapWarnFraction = 0.5
    static let loadWarnPerCpu = 1.2, loadCriticalPerCpu = 2.0
    static let staleWarnSeconds = 15.0 * 60, staleCriticalSeconds = 60.0 * 60
    static let azureWarnFraction = 0.85, azureCriticalFraction = 0.95
    static let schoolSyncWarnSeconds = 26.0 * 3600      // full sync runs every 12 h
    static let emailPollWarnSeconds = 30.0 * 60         // mailbox is polled every 2 min
    static let agentMinRunsForRate = 5, agentFailWarnRate = 0.2, agentFailCriticalRate = 0.5, agentSlowP95Seconds = 45.0

    static func attention(_ i: AdminHealthInputs) -> [AdminAttention] {
        var out: [AdminAttention] = []
        func add(_ id: String, _ level: AdminHealthLevel, _ title: String, _ detail: String, _ target: String?) {
            out.append(AdminAttention(id: id, level: level, title: title, detail: detail, target: target))
        }
        if let generated = i.generatedAt {
            let age = max(0, i.now.timeIntervalSince(generated))
            if age >= staleCriticalSeconds { add("stale", .critical, "Дані сервера застаріли", "Знімок оновлювався \(duration(age)) тому. Колектор може не працювати.", "host") }
            else if age >= staleWarnSeconds { add("stale", .warning, "Дані сервера не свіжі", "Знімок оновлювався \(duration(age)) тому.", "host") }
        }
        if let disk = i.diskUsedPercent {
            let free = i.diskAvailableBytes
            if disk >= diskCriticalPercent || (free.map { $0 < diskCriticalFreeBytes } ?? false) { add("disk", .critical, "Закінчується місце на диску", "Зайнято \(percent(disk))" + (free.map { ", вільно \(bytes($0))" } ?? "") + ".", "disk") }
            else if disk >= diskWarnPercent { add("disk", .warning, "Диск заповнюється", "Зайнято \(percent(disk))" + (free.map { ", вільно \(bytes($0))" } ?? "") + ".", "disk") }
        }
        if let mem = i.memoryUsedPercent {
            if mem >= memoryCriticalPercent { add("memory", .critical, "Майже вичерпана памʼять", "Використано \(percent(mem)) оперативної памʼяті.", "memory") }
            else if mem >= memoryWarnPercent { add("memory", .warning, "Памʼяті лишається мало", "Використано \(percent(mem)).", "memory") }
        }
        if i.swapTotalBytes > 0, i.swapUsedBytes / i.swapTotalBytes >= swapWarnFraction {
            add("swap", .warning, "Активно використовується swap", "\(bytes(i.swapUsedBytes)) із \(bytes(i.swapTotalBytes)).", "memory")
        }
        if let load = i.load5, i.logicalCpus > 0 {
            let perCpu = load / Double(i.logicalCpus)
            if perCpu >= loadCriticalPerCpu { add("load", .critical, "Дуже високе навантаження CPU", "Середнє за 5 хв: \(String(format: "%.2f", load)) на \(i.logicalCpus) vCPU.", "cpu") }
            else if perCpu >= loadWarnPerCpu { add("load", .warning, "Підвищене навантаження CPU", "Середнє за 5 хв: \(String(format: "%.2f", load)) на \(i.logicalCpus) vCPU.", "cpu") }
        }
        if i.containersUnhealthy > 0 {
            add("unhealthy", .critical, "\(i.containersUnhealthy) контейнер(ів) unhealthy", "Docker повідомляє, що перевірка здоровʼя не проходить.", "docker")
        }
        let stopped = max(0, i.containersTotal - i.containersRunning)
        if stopped > 0 { add("stopped", .info, "Зупинено контейнерів: \(stopped)", "Це може бути навмисно. Перевірте список, якщо щось має працювати.", "docker") }
        switch i.backupStatus {
        case "failed": add("backup", .critical, "Резервна копія не вдалась", "Остання спроба завершилась помилкою.", "backups")
        case "stale": add("backup", .warning, "Резервна копія застаріла", i.backupAgeSeconds.map { "Остання успішна: \(duration($0)) тому." } ?? "Давно не було успішної копії.", "backups")
        case "unknown": add("backup", .warning, "Статус резервних копій невідомий", "Не вдалося прочитати стан копій.", "backups")
        case "running": add("backup", .info, "Триває резервне копіювання", "Дочекайтесь завершення.", "backups")
        case "success": if i.restoreVerified == false { add("restore", .info, "Відновлення з копії не перевірялось", "Копії є, але тест відновлення не підтверджено.", "backups") }
        default: break
        }
        if i.openRouterStatus == "unavailable" { add("openrouter", .warning, "OpenRouter: статистика недоступна", "Не вдалося отримати витрати й баланс.", "ai") }
        if let worst = i.azureWorstFraction {
            if worst >= azureCriticalFraction { add("azure", .critical, "Azure Speech: ліміт майже вичерпано", "Використано \(percent(worst * 100)) безкоштовного ліміту.", "ai") }
            else if worst >= azureWarnFraction { add("azure", .warning, "Azure Speech: ліміт наближається", "Використано \(percent(worst * 100)) безкоштовного ліміту.", "ai") }
        }
        if i.schoolSyncStatus == "error" || (i.schoolSyncError?.isEmpty == false && i.schoolSyncStatus != "running") {
            add("school_sync", .warning, "Синхронізація школи: помилка", i.schoolSyncError.map { "Остання помилка: \($0)" } ?? "Schulmanager не відповідає.", nil)
        } else if let age = i.schoolSyncAgeSeconds, age >= schoolSyncWarnSeconds {
            add("school_sync", .warning, "Школа давно не синхронізувалась", "Остання синхронізація \(duration(age)) тому.", nil)
        }
        if let err = i.emailLastError, !err.isEmpty { add("email", .warning, "Пошта школи: помилка", "Код: \(err).", nil) }
        else if let age = i.emailAgeSeconds, age >= emailPollWarnSeconds { add("email_poll", .warning, "Пошту школи давно не опитували", "Останній опит \(duration(age)) тому.", nil) }
        if let q = i.emailQuarantined, q > 0 { add("email_quarantine", .info, "Листів у карантині: \(q)", "Чекають вашого рішення про відправника.", nil) }
        if let f = i.weeklyReportFailed, f > 0 { add("weekly_report", .warning, "Тижневий звіт: невдалі відправки", "Невдалих спроб: \(f).", nil) }
        if let runs = i.agentRuns24h, let failed = i.agentFailed24h, runs >= agentMinRunsForRate {
            let rate = Double(failed) / Double(runs)
            if rate >= agentFailCriticalRate { add("agent_fail", .critical, "Агент часто не відповідає", "За добу \(failed) з \(runs) запусків завершились помилкою.", "agent") }
            else if rate >= agentFailWarnRate { add("agent_fail", .warning, "Агент іноді не відповідає", "За добу \(failed) з \(runs) запусків завершились помилкою.", "agent") }
        }
        if let p95 = i.agentP95Seconds24h, (i.agentRuns24h ?? 0) >= agentMinRunsForRate, p95 >= agentSlowP95Seconds {
            add("agent_slow", .warning, "Агент відповідає повільно", "95% відповідей за добу вкладаються в \(Int(p95.rounded())) с.", "agent")
        }
        if let fb = i.agentFallbackAttempts7d, fb > 0 { add("agent_fallback", .info, "Агент користувався резервною моделлю", "Спроб через резервного провайдера за тиждень: \(fb).", "agent") }
        return out.sorted { $0.level != $1.level ? $0.level > $1.level : $0.id < $1.id }
    }

    static func overall(_ items: [AdminAttention]) -> AdminHealthLevel {
        let top = items.map(\.level).max() ?? .ok
        return top
    }

    /// "Усе гаразд" / "3 проблеми" etc. (info-only lists stay green).
    static func summary(_ items: [AdminAttention]) -> String {
        let problems = items.filter { $0.level >= .warning }.count
        if problems == 0 { return items.isEmpty ? "Усе гаразд" : "Усе працює" }
        return "\(problems) \(plural(problems, "проблема", "проблеми", "проблем"))"
    }

    static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let n100 = n % 100, n10 = n % 10
        if n100 >= 11 && n100 <= 14 { return many }
        if n10 == 1 { return one }
        if n10 >= 2 && n10 <= 4 { return few }
        return many
    }

    static func duration(_ seconds: Double) -> String {
        let s = Int(max(0, seconds))
        if s < 90 { return "менше хвилини" }
        if s < 3600 { return "\(s / 60) хв" }
        if s < 86_400 { return "\(s / 3600) год" }
        return "\(s / 86_400) дн."
    }

    static func percent(_ value: Double) -> String { "\(Int(value.rounded()))%" }

    static func bytes(_ value: Double) -> String {
        let gib = value / 1_073_741_824
        if gib >= 1 { return String(format: "%.1f ГБ", gib) }
        return String(format: "%.0f МБ", value / 1_048_576)
    }

    /// Plain-text snapshot the owner can paste into a chat or an issue. Contains no secrets, only aggregates.
    static func diagnosticsText(_ i: AdminHealthInputs, items: [AdminAttention]) -> String {
        var lines = ["Orbit · Admin · \(summary(items))"]
        if let g = i.generatedAt { lines.append("Знімок: \(ISO8601DateFormatter().string(from: g))") }
        if let d = i.diskUsedPercent { lines.append("Диск: \(percent(d))" + (i.diskAvailableBytes.map { ", вільно \(bytes($0))" } ?? "")) }
        if let m = i.memoryUsedPercent { lines.append("Памʼять: \(percent(m))" + (i.swapTotalBytes > 0 ? ", swap \(bytes(i.swapUsedBytes))/\(bytes(i.swapTotalBytes))" : "")) }
        if let l = i.load5 { lines.append("Навантаження 5хв: \(String(format: "%.2f", l)) (vCPU \(i.logicalCpus))") }
        lines.append("Контейнери: \(i.containersRunning)/\(i.containersTotal) працює, unhealthy \(i.containersUnhealthy)")
        if let b = i.backupStatus { lines.append("Копії: \(b)" + (i.backupAgeSeconds.map { ", \(duration($0)) тому" } ?? "")) }
        if let st = i.schoolSyncStatus { lines.append("Школа: синк \(st)" + (i.schoolSyncAgeSeconds.map { ", \(duration($0)) тому" } ?? "")) }
        for item in items { lines.append("[\(item.level)] \(item.title) — \(item.detail)") }
        return lines.joined(separator: "\n")
    }
}
