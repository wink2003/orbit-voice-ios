import SwiftUI

/// Building blocks of the Admin panel v2 (owner-only, read-only). Pure presentation: all decisions live in AdminHealthLogic.
extension AdminHealthLevel {
    var color: Color {
        switch self {
        case .ok, .info: return .green
        case .warning: return .orange
        case .critical: return .red
        }
    }
    var symbol: String {
        switch self {
        case .ok: return "checkmark.seal.fill"
        case .info: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.octagon.fill"
        }
    }
}

struct AdminStatusHero: View {
    let level: AdminHealthLevel
    let summary: String
    let subtitle: String
    let updatedText: String
    let isRefreshing: Bool
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: level.symbol).font(.system(size: 34, weight: .semibold)).foregroundStyle(level.color)
            VStack(alignment: .leading, spacing: 3) {
                Text(summary).font(.title2.weight(.bold)).foregroundStyle(Routes05Tokens.ink)
                Text(subtitle).font(.subheadline).foregroundStyle(Routes05Tokens.secondary)
                HStack(spacing: 6) {
                    if isRefreshing { ProgressView().controlSize(.mini) }
                    Text(updatedText).font(.caption).foregroundStyle(Routes05Tokens.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(level.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(level.color.opacity(0.45), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

struct AdminAttentionRow: View {
    let item: AdminAttention
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.level.symbol).foregroundStyle(item.level.color).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.subheadline.weight(.semibold)).foregroundStyle(Routes05Tokens.ink)
                Text(item.detail).font(.caption).foregroundStyle(Routes05Tokens.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if item.target != nil { Image(systemName: "chevron.right").font(.caption).foregroundStyle(Routes05Tokens.secondary) }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

/// Ring gauge for one resource. `fraction` is 0...1; the ring colour follows the supplied level.
struct AdminGaugeTile: View {
    let title: String
    let icon: String
    let valueText: String
    let caption: String
    let fraction: Double
    let level: AdminHealthLevel
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(Routes05Tokens.rule.opacity(0.6), lineWidth: 7)
                Circle().trim(from: 0, to: CGFloat(min(max(fraction, 0), 1)))
                    .stroke(level.color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Image(systemName: icon).font(.caption2).foregroundStyle(Routes05Tokens.secondary)
                    Text(valueText).font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(Routes05Tokens.ink)
                }
            }
            .frame(width: 70, height: 70)
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(Routes05Tokens.ink)
            Text(caption).font(.caption2).foregroundStyle(Routes05Tokens.secondary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Routes05Tokens.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Routes05Tokens.rule, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(valueText). \(caption)")
    }
}

struct AdminSectionHeader: View {
    let title: String
    var body: some View {
        Text(title.uppercased()).font(.caption.weight(.bold)).tracking(0.8).foregroundStyle(Routes05Tokens.secondary)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
    }
}

/// Compact AI spend/limits card: OpenRouter today/7d/balance + Azure Speech worst limit usage.
struct AdminAICard: View {
    let openRouter: OpenRouterStats?
    let azure: AzureSpeechStats?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("AI: витрати та ліміти", systemImage: "sparkles").font(.headline)
            if let o = openRouter, o.status == "ok" {
                HStack(spacing: 0) {
                    metric("Сьогодні", money(o.today.cost, o.currency)); Spacer()
                    metric("7 днів", money(o.last7Days.cost, o.currency)); Spacer()
                    metric("30 днів", money(o.last30Days.cost, o.currency))
                }
                if o.balance.status == "available", let amount = o.balance.amount {
                    Text(o.balance.type == "key_remaining_limit" ? "Залишок ліміту ключа: \(money(amount, o.currency))" : "Баланс: \(money(amount, o.currency))").font(.caption).foregroundStyle(Routes05Tokens.secondary)
                }
            } else {
                Text("OpenRouter: статистика недоступна").font(.caption).foregroundStyle(.orange)
            }
            if let a = azure, a.status == "ok" {
                let worst = azureWorst(a)
                HStack {
                    Text("Azure Speech (F0, $0)").font(.caption).foregroundStyle(Routes05Tokens.secondary); Spacer()
                    Text(worst.map { AdminHealthLogic.percent($0 * 100) + " ліміту" } ?? "без обліку").font(.caption.monospacedDigit())
                }
                if let worst { ProgressView(value: min(max(worst, 0), 1)).tint(worst > 0.85 ? .red : .indigo) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
        .background(Routes05Tokens.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Routes05Tokens.rule, lineWidth: 1))
    }
    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) { Text(title).font(.caption).foregroundStyle(Routes05Tokens.secondary); Text(value).font(.headline.monospacedDigit()) }
    }
    private func money(_ v: Double, _ currency: String?) -> String { (currency == "USD" || currency == nil ? "$" : "") + String(format: "%.2f", v) }
    /// Highest used/limit across all Azure limits (nil when nothing is metered).
    static func worstFraction(_ stats: AzureSpeechStats) -> Double? {
        var worst: Double?
        for task in stats.tasks { for row in AzureSpeechLabels.rows(task) { if let f = row.fraction { worst = max(worst ?? 0, f) } } }
        return worst
    }
    private func azureWorst(_ stats: AzureSpeechStats) -> Double? { Self.worstFraction(stats) }
}

extension ServerOverview {
    /// Primitive inputs for AdminHealthLogic (kept here so the logic file stays free of network models).
    func adminInputs(backups: BackupStatus?, openRouter: OpenRouterStats?, azure: AzureSpeechStats?, orbit: OrbitServicesStatus? = nil, agent: AgentTelemetry? = nil, now: Date = Date()) -> AdminHealthInputs {
        var i = AdminHealthInputs(now: now)
        i.generatedAt = generatedAt
        i.diskUsedPercent = disks.first?.usedPercent
        i.diskAvailableBytes = disks.first?.availableBytes
        i.memoryUsedPercent = memory.usedPercent
        i.swapTotalBytes = memory.swapTotalBytes
        i.swapUsedBytes = memory.swapUsedBytes
        i.load5 = cpu.loadAverage.five
        i.logicalCpus = cpu.logicalCpus
        i.containersTotal = containers.total
        i.containersRunning = containers.running
        i.containersUnhealthy = containers.unhealthy
        i.backupStatus = backups?.status
        i.backupAgeSeconds = backups?.ageSeconds
        i.restoreVerified = backups?.restoreVerified
        i.openRouterStatus = openRouter?.status
        i.azureWorstFraction = azure.flatMap { AdminAICard.worstFraction($0) }
        i.schoolSyncStatus = orbit?.school?.syncStatus
        i.schoolSyncAgeSeconds = orbit?.school?.ageSeconds
        i.schoolSyncError = orbit?.school?.lastError
        i.emailAgeSeconds = orbit?.email?.ageSeconds
        i.emailLastError = orbit?.email?.lastError
        i.emailQuarantined = orbit?.email?.quarantined
        i.weeklyReportFailed = orbit?.weeklyReport?.failed
        if let a = agent, a.available, let w = a.last24h {
            i.agentRuns24h = w.total; i.agentFailed24h = w.failed; i.agentP95Seconds24h = w.p95Seconds
            i.agentFallbackAttempts7d = (a.planner7d ?? []).filter { !$0.binding.hasPrefix("google_gemini") }.reduce(0) { $0 + $1.attempts }
        }
        return i
    }
}

/// School sync, School e-mail channel and weekly report in one card (data from /api/server/overview/orbit).
struct AdminOrbitServicesCard: View {
    let status: OrbitServicesStatus
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Школа та пошта", systemImage: "graduationcap").font(.headline)
            if let school = status.school {
                row("Синхронізація Schulmanager", school.syncStatus == "error" ? "помилка" : (school.ageSeconds.map { AdminHealthLogic.duration($0) + " тому" } ?? "ще не було"), warn: school.syncStatus == "error")
            }
            if let email = status.email {
                row("Пошта школи (опит)", email.lastError.map { "помилка: \($0)" } ?? (email.ageSeconds.map { AdminHealthLogic.duration($0) + " тому" } ?? "ще не було"), warn: email.lastError != nil)
                row("Листів за 7 днів / карантин", "\(email.ingested7d) / \(email.quarantined)", warn: false)
            }
            if let report = status.weeklyReport {
                row("Тижневий звіт", report.weeklySent > 0 ? "надіслано (тиждень \(report.weekStart ?? "?"))" : "ще не надсилався (тиждень \(report.weekStart ?? "?"))", warn: report.failed > 0)
            } else {
                row("Тижневий звіт", "ще не формувався", warn: false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
        .background(Routes05Tokens.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Routes05Tokens.rule, lineWidth: 1))
    }
    private func row(_ title: String, _ value: String, warn: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.caption).foregroundStyle(Routes05Tokens.secondary)
            Spacer()
            Text(value).font(.caption.monospacedDigit()).foregroundStyle(warn ? Color.orange : Routes05Tokens.ink).multilineTextAlignment(.trailing)
        }
    }
}

/// Agent quality at a glance: runs, success rate, latency, failure codes, planner usage (data from /api/server/overview/agent).
struct AdminAgentCard: View {
    let telemetry: AgentTelemetry
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Агент", systemImage: "brain.head.profile").font(.headline)
            if let day = telemetry.last24h {
                HStack(spacing: 0) {
                    metric("Запусків (24 год)", "\(day.total)"); Spacer()
                    metric("Успішно", day.total > 0 ? "\(Int((Double(day.completed) / Double(day.total) * 100).rounded()))%" : "—"); Spacer()
                    metric("p95", day.p95Seconds.map { "\(Int($0.rounded())) с" } ?? "—")
                }
                if day.failed > 0 { row("Помилок за добу", "\(day.failed)", warn: true) }
            } else {
                Text("Дані про запуски недоступні").font(.caption).foregroundStyle(Routes05Tokens.secondary)
            }
            if let week = telemetry.last7d { row("За тиждень", "\(week.completed)/\(week.total) успішно", warn: false) }
            ForEach((telemetry.failuresByCode7d ?? []).prefix(3)) { f in row("Збій: \(AdminAgentLabels.failure(f.code))", "\(f.count)", warn: false) }
            ForEach((telemetry.planner7d ?? []).prefix(2)) { p in
                row(AdminAgentLabels.model(p.binding), "\(p.ok)/\(p.attempts) ок" + (p.timeouts > 0 ? " · таймаутів \(p.timeouts)" : "") + (p.providerErrors > 0 ? " · помилок \(p.providerErrors)" : ""), warn: p.timeouts > 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
        .background(Routes05Tokens.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Routes05Tokens.rule, lineWidth: 1))
    }
    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) { Text(title).font(.caption).foregroundStyle(Routes05Tokens.secondary); Text(value).font(.headline.monospacedDigit()) }
    }
    private func row(_ title: String, _ value: String, warn: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.caption).foregroundStyle(Routes05Tokens.secondary)
            Spacer()
            Text(value).font(.caption.monospacedDigit()).foregroundStyle(warn ? Color.orange : Routes05Tokens.ink).multilineTextAlignment(.trailing)
        }
    }
}
