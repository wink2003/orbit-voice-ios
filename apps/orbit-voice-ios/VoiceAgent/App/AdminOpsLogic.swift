import Foundation

/// Admin "operations" data (GET /api/server/overview/ops) and its wording. Pure: unit-tested in CI.
/// Dates arrive as ISO strings with fractional seconds, so they are decoded as String and parsed here (never `.iso8601`).
struct OpsStatus: Decodable {
    struct Container: Decodable, Identifiable { let name: String; let status: String; let health: String?; let startedAt: String?; let expectedStopped: Bool; var id: String { name } }
    struct Service: Decodable, Identifiable { let name: String; let status: String; let health: String?; var id: String { name } }
    struct Point: Decodable { let t: Double; let cpuLoad: Double?; let memoryAvailable: Double?; let diskPercent: Double? }
    struct Event: Decodable, Identifiable { let time: Double; let kind: String; let label: String; var id: String { "\(time)|\(kind)|\(label)" } }
    struct Job: Decodable, Identifiable { let id: String; let label: String; let status: String; let result: String?; let lastRunAt: String?; let ageSeconds: Double?; let nextRunAt: String?; let timerActive: Bool }
    struct LastBackup: Decodable { let status: String; let updatedAt: String?; let totalSizeBytes: Double?; let componentCount: Int?; let componentsSucceeded: Int? }
    struct Replication: Decodable { let status: String; let updatedAt: String?; let uploadedCount: Int?; let verifiedCount: Int?; let failedCount: Int?; let incompleteCount: Int? }
    struct SideStore: Decodable { let status: String; let localIpaCount: Int?; let feedMissingCount: Int?; let unreferencedCount: Int? }
    struct Secrets: Decodable { let lastArchiveAt: String? }
    struct Retention: Decodable { let mode: String?; let deletionEnabled: Bool; let itemCount: Int?; let protectedCount: Int?; let reviewOnlyCount: Int? }
    struct Release: Decodable { let state: String?; let releaseId: String?; let target: String?; let prepareState: String?; let expiresAt: String?; let stale: Bool }
    struct Backups: Decodable {
        let overall: String; let measuredAt: String?; let pending: Bool; let jobs: [Job]
        let lastBackup: LastBackup?; let replication: Replication?; let sideStore: SideStore?; let secrets: Secrets?; let retention: Retention?; let release: Release?
    }
    let generatedAt: String
    let containers: [Container]
    let services: [Service]
    let history: [Point]
    let events: [Event]
    let backups: Backups?
}

enum AdminOpsLogic {
    static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let withFraction = ISO8601DateFormatter(); withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: value) { return d }
        return ISO8601DateFormatter().date(from: value)
    }

    /// Backup manager overall -> panel level. Unknown is informational (the collector may simply not have measured yet).
    static func level(forOverall overall: String) -> AdminHealthLevel {
        switch overall {
        case "Healthy": return .ok
        case "Warning": return .warning
        case "Critical": return .critical
        default: return .info
        }
    }

    static func stateLabel(_ status: String) -> String {
        switch status {
        case "Healthy": return "справно"
        case "Warning": return "потрібна увага"
        case "Critical": return "помилка"
        default: return "невідомо"
        }
    }

    /// "через 4 год" / "зараз" / "—".
    static func nextRunText(_ next: String?, now: Date) -> String {
        guard let date = parseDate(next) else { return "—" }
        let delta = date.timeIntervalSince(now)
        return delta <= 60 ? "зараз" : "через " + AdminHealthLogic.duration(delta)
    }

    /// "успішно · 12 год тому · наступний через 4 год" for one job.
    static func jobLine(_ job: OpsStatus.Job, now: Date) -> String {
        var parts: [String] = []
        parts.append(job.result == "success" ? "успішно" : (job.result ?? stateLabel(job.status)))
        if let age = job.ageSeconds { parts.append(AdminHealthLogic.duration(age) + " тому") }
        parts.append(job.timerActive ? "наступний " + nextRunText(job.nextRunAt, now: now) : "таймер вимкнено")
        return parts.joined(separator: " · ")
    }

    static func retentionText(_ r: OpsStatus.Retention) -> String {
        if r.mode == "DRY_RUN_ONLY" || !r.deletionEnabled { return "лише перегляд, автовидалення вимкнене" }
        return "автовидалення увімкнене"
    }

    /// Containers that are not running and are not expected to be stopped.
    static func unexpectedlyStopped(_ containers: [OpsStatus.Container]) -> [OpsStatus.Container] {
        containers.filter { $0.status != "running" && !$0.expectedStopped }
    }
    static func expectedStoppedCount(_ containers: [OpsStatus.Container]) -> Int {
        containers.filter { $0.status != "running" && $0.expectedStopped }.count
    }

    /// Orbit application containers (shown on the «Сервіси Orbit» page); everything else is infrastructure (shown on «Сервер»).
    static let appContainerNames: [String] = ["orbit-core", "orbit-realtime-web", "orbit-realtime-agent", "orbit-calendar", "orbit-schulmanager-worker", "orbit-whatsapp-baileys"]
    static func appContainers(_ all: [OpsStatus.Container]) -> [OpsStatus.Container] { all.filter { appContainerNames.contains($0.name) } }
    static func infraContainers(_ all: [OpsStatus.Container]) -> [OpsStatus.Container] { all.filter { !appContainerNames.contains($0.name) } }

    /// "працює · 3 год" / "зупинено навмисно" / "зупинено".
    static func containerState(_ c: OpsStatus.Container, now: Date) -> String {
        if c.status == "running" {
            var text = c.health == "unhealthy" ? "працює · unhealthy" : "працює"
            if let started = parseDate(c.startedAt) { text += " · " + AdminHealthLogic.duration(max(0, now.timeIntervalSince(started))) }
            return text
        }
        return c.expectedStopped ? "зупинено навмисно" : "зупинено"
    }

    /// Ukrainian date/time for the panel regardless of the phone's region (the app UI is Ukrainian).
    static func dateText(_ date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "uk_UA"); f.timeZone = timeZone; f.dateStyle = .medium; f.timeStyle = .short
        return f.string(from: date)
    }
    static func timeText(_ date: Date, timeZone: TimeZone = .current) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "uk_UA"); f.timeZone = timeZone; f.dateStyle = .none; f.timeStyle = .short
        return f.string(from: date)
    }

    /// Release-gate preparation state as shown to the owner (raw values are English enum names).
    static func prepareStateLabel(_ state: String?) -> String {
        switch state {
        case "COMPLETED": return "завершена"
        case "PREPARATION_READY": return "готова"
        case "EXPIRED": return "прострочена"
        case .some(let other): return other
        case nil: return "—"
        }
    }

    static func eventText(_ e: OpsStatus.Event) -> String {
        switch e.kind {
        case "appeared": return "зʼявився: " + e.label
        case "disappeared": return "зник: " + e.label
        case "status": return "змінив стан: " + e.label
        default: return e.label
        }
    }

    /// Values scaled to 0...1 for a sparkline (flat series -> 0.5).
    static func normalized(_ values: [Double]) -> [Double] {
        guard let lo = values.min(), let hi = values.max() else { return [] }
        if hi - lo < 1e-9 { return values.map { _ in 0.5 } }
        return values.map { ($0 - lo) / (hi - lo) }
    }
}
