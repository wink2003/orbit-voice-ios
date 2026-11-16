import Foundation

@main
struct AdminOpsLogicTests {
    static func main() {
        let json = """
        {"generatedAt":"2026-11-15T22:28:22.123Z",
         "containers":[{"name":"orbit-core","status":"running","health":"none","startedAt":"2026-11-15T16:14:46.753Z","expectedStopped":false},
                       {"name":"orbit-telegram-user","status":"stopped","health":"none","startedAt":null,"expectedStopped":true},
                       {"name":"x-broken","status":"stopped","health":null,"startedAt":null,"expectedStopped":false}],
         "services":[{"name":"nginx.service","status":"running","health":"healthy"}],
         "history":[{"t":1,"cpuLoad":0.5,"memoryAvailable":5e9,"diskPercent":81},{"t":2,"cpuLoad":null,"memoryAvailable":null,"diskPercent":null}],
         "events":[{"time":2000,"kind":"appeared","label":"u1"},{"time":2001,"kind":"disappeared","label":"u2"},{"time":2002,"kind":"status","label":"u3"}],
         "backups":{"overall":"Healthy","measuredAt":"2026-11-15T22:28:22Z","pending":false,
           "jobs":[{"id":"b","label":"Щоденний backup Orbit","status":"Healthy","result":"success","lastRunAt":"2026-11-15T09:51:21.000Z","ageSeconds":45421,"nextRunAt":"2026-11-16T02:31:48.000Z","timerActive":true},
                   {"id":"c","label":"Старий","status":"Warning","result":null,"lastRunAt":null,"ageSeconds":null,"nextRunAt":null,"timerActive":false}],
           "lastBackup":{"status":"Healthy","updatedAt":"2026-11-15T09:51:20.000Z","totalSizeBytes":18391828,"componentCount":4,"componentsSucceeded":4},
           "replication":{"status":"Healthy","updatedAt":"2026-11-15T09:51:23.000Z","uploadedCount":1,"verifiedCount":115,"failedCount":0,"incompleteCount":0},
           "sideStore":{"status":"Healthy","localIpaCount":128,"feedMissingCount":0,"unreferencedCount":0},"secrets":{"lastArchiveAt":"2026-11-15T04:49:39.000Z"},
           "retention":{"mode":"DRY_RUN_ONLY","deletionEnabled":false,"itemCount":444,"protectedCount":434,"reviewOnlyCount":10},
           "release":{"state":"EXPIRED","releaseId":"guard-events-db-085","target":"orbit-core","prepareState":"PREPARATION_READY","expiresAt":"2026-11-15T10:51:24.000Z","stale":true}}}
        """
        let ops = try! JSONDecoder().decode(OpsStatus.self, from: Data(json.utf8))
        precondition(ops.containers.count == 3 && ops.history[1].cpuLoad == nil, "nullable numbers decode")
        precondition(AdminOpsLogic.expectedStoppedCount(ops.containers) == 1)
        precondition(AdminOpsLogic.unexpectedlyStopped(ops.containers).map(\.name) == ["x-broken"], "only unexpected stops are problems")

        // Dates with and without fractional seconds both parse.
        precondition(AdminOpsLogic.parseDate("2026-11-15T22:28:22.123Z") != nil && AdminOpsLogic.parseDate("2026-11-15T22:28:22Z") != nil)
        precondition(AdminOpsLogic.parseDate(nil) == nil && AdminOpsLogic.parseDate("garbage") == nil)

        let now = AdminOpsLogic.parseDate("2026-11-15T22:31:48.000Z")!
        let job = ops.backups!.jobs[0]
        precondition(AdminOpsLogic.nextRunText(job.nextRunAt, now: now) == "через 4 год", AdminOpsLogic.nextRunText(job.nextRunAt, now: now))
        precondition(AdminOpsLogic.nextRunText("2026-11-15T22:31:50.000Z", now: now) == "зараз")
        precondition(AdminOpsLogic.nextRunText(nil, now: now) == "—")
        precondition(AdminOpsLogic.jobLine(job, now: now) == "успішно · 12 год тому · наступний через 4 год", AdminOpsLogic.jobLine(job, now: now))
        precondition(AdminOpsLogic.jobLine(ops.backups!.jobs[1], now: now) == "потрібна увага · таймер вимкнено")

        precondition(AdminOpsLogic.level(forOverall: "Healthy") == .ok && AdminOpsLogic.level(forOverall: "Warning") == .warning && AdminOpsLogic.level(forOverall: "Critical") == .critical && AdminOpsLogic.level(forOverall: "Unknown") == .info)
        precondition(AdminOpsLogic.retentionText(ops.backups!.retention!) == "лише перегляд, автовидалення вимкнене")
        precondition(AdminOpsLogic.eventText(ops.events[0]) == "зʼявився: u1" && AdminOpsLogic.eventText(ops.events[1]) == "зник: u2" && AdminOpsLogic.eventText(ops.events[2]) == "змінив стан: u3")
        precondition(AdminOpsLogic.normalized([1, 2, 3]) == [0, 0.5, 1] && AdminOpsLogic.normalized([4, 4]) == [0.5, 0.5] && AdminOpsLogic.normalized([]).isEmpty)

        // Health: an intentionally stopped container is not even an info item; an unexpected one still is; a warning backup manager is surfaced.
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        var i = AdminHealthInputs(now: t)
        i.generatedAt = t.addingTimeInterval(-30); i.diskUsedPercent = 40; i.diskAvailableBytes = 20 * 1_073_741_824; i.memoryUsedPercent = 50; i.load5 = 0.4; i.logicalCpus = 2
        i.containersTotal = 10; i.containersRunning = 9; i.containersExpectedStopped = 1; i.backupStatus = "success"; i.backupAgeSeconds = 3600; i.restoreVerified = false; i.backupManagerOverall = "Healthy"
        precondition(AdminHealthLogic.attention(i).isEmpty, "frozen container + healthy manager: nothing to flag (no stale 'restore not verified' either)")
        i.containersRunning = 8
        precondition(AdminHealthLogic.attention(i).map(\.id) == ["stopped"])
        i.backupManagerOverall = "Warning"
        precondition(AdminHealthLogic.attention(i).contains { $0.id == "backup_manager" && $0.level == .warning })
        i.backupManagerOverall = nil
        precondition(AdminHealthLogic.attention(i).contains { $0.id == "restore" }, "without ops the old restore hint still works")
        // Container split: app containers go to the Orbit page, the rest is infrastructure; state wording.
        let all = [OpsStatus.Container(name: "orbit-core", status: "running", health: "none", startedAt: "2026-11-15T16:14:46.000Z", expectedStopped: false),
                   OpsStatus.Container(name: "postgres", status: "running", health: "unhealthy", startedAt: nil, expectedStopped: false),
                   OpsStatus.Container(name: "orbit-telegram-user", status: "stopped", health: nil, startedAt: nil, expectedStopped: true),
                   OpsStatus.Container(name: "orbit-whatsapp-baileys", status: "stopped", health: nil, startedAt: nil, expectedStopped: false)]
        precondition(AdminOpsLogic.appContainers(all).map(\.name) == ["orbit-core", "orbit-whatsapp-baileys"])
        precondition(AdminOpsLogic.infraContainers(all).map(\.name) == ["postgres", "orbit-telegram-user"])
        let t0 = AdminOpsLogic.parseDate("2026-11-15T19:14:46.000Z")!
        precondition(AdminOpsLogic.containerState(all[0], now: t0) == "працює · 3 год", AdminOpsLogic.containerState(all[0], now: t0))
        precondition(AdminOpsLogic.containerState(all[1], now: t0) == "працює · unhealthy")
        precondition(AdminOpsLogic.containerState(all[2], now: t0) == "зупинено навмисно" && AdminOpsLogic.containerState(all[3], now: t0) == "зупинено")
        print("AdminOpsLogicTests: ok")
    }
}
