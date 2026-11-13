import Foundation

@main
struct AdminHealthLogicTests {
    static func main() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func base() -> AdminHealthInputs {
            var i = AdminHealthInputs(now: now)
            i.generatedAt = now.addingTimeInterval(-30); i.diskUsedPercent = 40; i.diskAvailableBytes = 20 * 1_073_741_824
            i.memoryUsedPercent = 50; i.load5 = 0.4; i.logicalCpus = 2
            i.containersTotal = 10; i.containersRunning = 10; i.backupStatus = "success"; i.backupAgeSeconds = 3600; i.restoreVerified = true
            i.openRouterStatus = "ok"; i.azureWorstFraction = 0.1
            return i
        }
        // healthy
        precondition(AdminHealthLogic.attention(base()).isEmpty)
        precondition(AdminHealthLogic.summary([]) == "Усе гаразд")
        precondition(AdminHealthLogic.overall([]) == .ok)

        // disk thresholds (the owner's real case: 86%)
        var d = base(); d.diskUsedPercent = 86; d.diskAvailableBytes = 6.4 * 1_073_741_824
        var a = AdminHealthLogic.attention(d)
        precondition(a.count == 1 && a[0].id == "disk" && a[0].level == .warning && a[0].target == "disk" && a[0].detail.contains("86%"))
        d.diskUsedPercent = 91; a = AdminHealthLogic.attention(d)
        precondition(a[0].level == .critical)
        d.diskUsedPercent = 70; d.diskAvailableBytes = 2 * 1_073_741_824; a = AdminHealthLogic.attention(d)
        precondition(a[0].level == .critical, "very low free space is critical even at 70%")

        // stopped containers are INFO only, unhealthy is critical
        var c = base(); c.containersRunning = 9
        a = AdminHealthLogic.attention(c)
        precondition(a.count == 1 && a[0].level == .info)
        precondition(AdminHealthLogic.summary(a) == "Усе працює", "info does not count as a problem")
        precondition(AdminHealthLogic.overall(a) == .info)
        c.containersUnhealthy = 1; a = AdminHealthLogic.attention(c)
        precondition(a[0].id == "unhealthy" && a[0].level == .critical, "critical sorts first")
        precondition(AdminHealthLogic.summary(a) == "1 проблема")

        // staleness
        var s = base(); s.generatedAt = now.addingTimeInterval(-20 * 60)
        a = AdminHealthLogic.attention(s); precondition(a.count == 1 && a[0].level == .warning)
        s.generatedAt = now.addingTimeInterval(-2 * 3600); a = AdminHealthLogic.attention(s); precondition(a[0].level == .critical && a[0].detail.contains("2 год"))

        // memory, swap, load
        var m = base(); m.memoryUsedPercent = 88; m.swapTotalBytes = 4_000_000_000; m.swapUsedBytes = 3_000_000_000; m.load5 = 5; m.logicalCpus = 2
        a = AdminHealthLogic.attention(m)
        precondition(Set(a.map(\.id)) == ["memory", "swap", "load"])
        precondition(a.first?.id == "load" && a.first?.level == .critical)

        // backups
        var b = base(); b.backupStatus = "failed"; precondition(AdminHealthLogic.attention(b)[0].level == .critical)
        b.backupStatus = "stale"; b.backupAgeSeconds = 3 * 86_400; a = AdminHealthLogic.attention(b)
        precondition(a[0].level == .warning && a[0].detail.contains("3 дн."))
        b.backupStatus = "success"; b.restoreVerified = false; a = AdminHealthLogic.attention(b)
        precondition(a.count == 1 && a[0].level == .info)
        b.backupStatus = nil; b.restoreVerified = nil; precondition(AdminHealthLogic.attention(b).isEmpty, "not loaded = no false alarm")

        // providers
        var p = base(); p.openRouterStatus = "unavailable"; p.azureWorstFraction = 0.9
        a = AdminHealthLogic.attention(p); precondition(Set(a.map(\.id)) == ["openrouter", "azure"] && a.allSatisfy { $0.level == .warning })
        p.azureWorstFraction = 0.97; precondition(AdminHealthLogic.attention(p).contains { $0.id == "azure" && $0.level == .critical })

        // orbit services
        var o = base(); o.schoolSyncStatus = "idle"; o.schoolSyncAgeSeconds = 3600; o.emailAgeSeconds = 120; o.emailQuarantined = 0; o.weeklyReportFailed = 0
        precondition(AdminHealthLogic.attention(o).isEmpty)
        o.schoolSyncAgeSeconds = 30 * 3600; a = AdminHealthLogic.attention(o)
        precondition(a.count == 1 && a[0].id == "school_sync" && a[0].level == .warning && a[0].detail.contains("30 год") == false && a[0].detail.contains("1 дн."))
        o.schoolSyncAgeSeconds = 3600; o.schoolSyncStatus = "error"; o.schoolSyncError = "auth_failed"; a = AdminHealthLogic.attention(o)
        precondition(a[0].id == "school_sync" && a[0].detail.contains("auth_failed"))
        o.schoolSyncStatus = "running"; o.schoolSyncError = "old"; precondition(AdminHealthLogic.attention(o).isEmpty, "a running sync is not an error even if an old error text remains")
        o.emailLastError = "imap_auth_failed"; a = AdminHealthLogic.attention(o); precondition(a.count == 1 && a[0].id == "email")
        o.emailLastError = nil; o.emailAgeSeconds = 3600; a = AdminHealthLogic.attention(o); precondition(a.count == 1 && a[0].id == "email_poll")
        o.emailAgeSeconds = 60; o.emailQuarantined = 3; a = AdminHealthLogic.attention(o); precondition(a.count == 1 && a[0].level == .info && a[0].title.contains("3"))
        o.emailQuarantined = 0; o.weeklyReportFailed = 1; a = AdminHealthLogic.attention(o); precondition(a.count == 1 && a[0].id == "weekly_report" && a[0].level == .warning)
        var nilOrbit = base(); nilOrbit.schoolSyncStatus = nil; precondition(AdminHealthLogic.attention(nilOrbit).isEmpty, "orbit services not loaded = no false alarm")

        // ukrainian plurals + formatting
        precondition(AdminHealthLogic.plural(1, "проблема", "проблеми", "проблем") == "проблема")
        precondition(AdminHealthLogic.plural(2, "проблема", "проблеми", "проблем") == "проблеми")
        precondition(AdminHealthLogic.plural(5, "проблема", "проблеми", "проблем") == "проблем")
        precondition(AdminHealthLogic.plural(11, "проблема", "проблеми", "проблем") == "проблем")
        precondition(AdminHealthLogic.plural(21, "проблема", "проблеми", "проблем") == "проблема")
        precondition(AdminHealthLogic.duration(30) == "менше хвилини" && AdminHealthLogic.duration(600) == "10 хв" && AdminHealthLogic.duration(7200) == "2 год" && AdminHealthLogic.duration(200_000) == "2 дн.")

        // diagnostics text: aggregates only
        let text = AdminHealthLogic.diagnosticsText(d, items: AdminHealthLogic.attention(d))
        precondition(text.contains("Диск: 70%") && text.contains("Контейнери: 10/10") && text.hasPrefix("Orbit · Admin"))
        print("AdminHealthLogicTests passed")
    }
}
