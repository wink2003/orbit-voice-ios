import SwiftUI
import WidgetKit

// Issue #119: add as the ONLY Swift source of a dedicated WidgetKit extension,
// plus SchoolTasksWidgetProjection.swift as shared target membership.
// The extension has no network, account session, task write or sensitive credential.
private enum SchoolWidgetTheme {
    static let paper = Color(red: 0.957, green: 0.953, blue: 0.914)
    static let ink = Color(red: 0.094, green: 0.125, blue: 0.110)
    static let mint = Color(red: 0.39, green: 0.85, blue: 0.75)
    static let overdue = Color(red: 0.85, green: 0.28, blue: 0.23)
}

private struct SchoolWidgetReadResult {
    let snapshot: SchoolTasksWidgetSnapshot?
    let statusCode: String
}

private enum SchoolWidgetStorage {
    // Configuration requires actual matching App Group entitlement on both targets.
    static let group = "group.net.opik.orbit.voice"
    static let key = "school.tasks.widget.snapshot.v1"

    static func current(at date: Date) -> SchoolWidgetReadResult {
        let groupContainerAvailable = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: group) != nil
        guard groupContainerAvailable else { return SchoolWidgetReadResult(snapshot: nil, statusCode: "R_GROUP_UNAVAILABLE") }
        guard let defaults = UserDefaults(suiteName: group) else {
            return SchoolWidgetReadResult(snapshot: nil, statusCode: "R_SUITE_UNAVAILABLE")
        }
        guard let data = defaults.data(forKey: key) else {
            return SchoolWidgetReadResult(snapshot: nil, statusCode: "R_SNAPSHOT_MISSING")
        }
        guard let snapshot = try? JSONDecoder().decode(SchoolTasksWidgetSnapshot.self, from: data) else {
            return SchoolWidgetReadResult(snapshot: nil, statusCode: "R_DECODE_FAILED")
        }
        if let reason = snapshot.unusableReason(at: date) {
            let code: String
            switch reason {
            case "schema_mismatch": code = "R_SCHEMA"
            case "generated_in_future": code = "R_FUTURE"
            case "stale": code = "R_STALE"
            case "week_mismatch": code = "R_WEEK"
            default: code = "R_INVALID"
            }
            return SchoolWidgetReadResult(snapshot: nil, statusCode: code)
        }
        return SchoolWidgetReadResult(snapshot: snapshot, statusCode: "R_OK")
    }
}

private enum SchoolWidgetLink {
    static func tasks(_ taskID: String? = nil) -> URL {
        var parts = URLComponents()
        parts.scheme = "orbit"
        parts.host = "school"
        parts.path = "/tasks"
        if let taskID { parts.queryItems = [URLQueryItem(name: "task", value: taskID)] }
        return parts.url ?? URL(string: "orbit://school/tasks")!
    }
}

private struct SchoolWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: SchoolTasksWidgetSnapshot?
    let diagnosticStatus: String
}

private struct SchoolWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> SchoolWidgetEntry {
        let now = Date()
        return SchoolWidgetEntry(date: now, snapshot: SchoolTasksWidgetSnapshot(
            schemaVersion: 1, generatedAt: now,
            weekStart: SchoolTasksWidgetSnapshot.schoolWeekStart(for: now),
            openCount: 3, overdue: [
                .init(id: "fixture-o", title: "Приклад простроченої справи", effectiveDay: nil, completed: false)
            ], thisWeek: [
                .init(id: "fixture-1", title: "Підготувати матеріали", effectiveDay: nil, completed: false),
                .init(id: "fixture-2", title: "Узгодити зустріч", effectiveDay: nil, completed: true),
                .init(id: "fixture-3", title: "Перевірити завдання", effectiveDay: nil, completed: false),
                .init(id: "fixture-4", title: "Зібрати речі", effectiveDay: nil, completed: true)
            ], completedThisWeek: 2, totalThisWeek: 4, coverageComplete: true), diagnosticStatus: "PREVIEW")
    }

    func getSnapshot(in context: Context, completion: @escaping (SchoolWidgetEntry) -> Void) {
        let now = Date()
        if context.isPreview {
            completion(placeholder(in: context))
        } else {
            let result = SchoolWidgetStorage.current(at: now)
            completion(SchoolWidgetEntry(date: now, snapshot: result.snapshot, diagnosticStatus: "SNAPSHOT/\(result.statusCode)"))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SchoolWidgetEntry>) -> Void) {
        let now = Date()
        let result = SchoolWidgetStorage.current(at: now)
        completion(Timeline(entries: [SchoolWidgetEntry(
            date: now, snapshot: result.snapshot,
            diagnosticStatus: "TIMELINE/\(result.statusCode)"
        )], policy: .after(now.addingTimeInterval(15 * 60))))
    }
}

private struct SchoolTasksWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .caption) private var captionPointSize: CGFloat = 11
    @ScaledMetric(relativeTo: .largeTitle) private var countPointSize: CGFloat = 35
    let entry: SchoolWidgetEntry

    private var ink: Color { scheme == .dark ? .white : SchoolWidgetTheme.ink }
    private var secondary: Color { scheme == .dark ? Color.white.opacity(0.68) : SchoolWidgetTheme.ink.opacity(0.57) }

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                if family == .systemSmall { small(snapshot) }
                else { medium(snapshot) }
            } else {
                VStack(alignment: .leading, spacing: 9) {
                    header
                    Spacer(minLength: 0)
                    Text("Відкрийте Orbit")
                        .font(.system(size: captionPointSize + 2, weight: .bold, design: .rounded))
                    Text("Щоб оновити справи школи")
                        .font(.system(size: captionPointSize))
                        .foregroundStyle(secondary)
                    Text("\(entry.diagnosticStatus) · \(entry.date.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: max(8, captionPointSize - 3), design: .monospaced))
                        .foregroundStyle(secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .widgetURL(SchoolWidgetLink.tasks())
            }
        }
        .foregroundStyle(ink)
        .padding(11)
        .containerBackground(for: .widget) {
            if scheme == .dark { Color(red: 0.11, green: 0.14, blue: 0.13) }
            else { SchoolWidgetTheme.paper }
        }
    }

    private var header: some View {
        HStack(spacing: 5) {
            Circle().fill(SchoolWidgetTheme.mint).frame(width: 7, height: 7)
            Text("orbit / Школа")
                .font(.system(size: captionPointSize + 1, weight: .black, design: .rounded))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private func small(_ snapshot: SchoolTasksWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            Spacer(minLength: 0)
            Text(String(snapshot.openCount))
                .font(.system(size: countPointSize, weight: .black, design: .rounded))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text("Відкритих справ")
                .font(.system(size: captionPointSize, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
            Label("\(snapshot.overdue.count) прострочених", systemImage: "square")
                .font(.system(size: max(9, captionPointSize - 1), weight: .semibold))
                .foregroundStyle(SchoolWidgetTheme.overdue)
                .lineLimit(1)
            Label("Тиждень: \(snapshot.completedThisWeek)/\(snapshot.totalThisWeek)", systemImage: "checkmark.square.fill")
                .font(.system(size: max(9, captionPointSize - 1)))
                .foregroundStyle(secondary)
                .lineLimit(1)
            if !snapshot.coverageComplete {
                Text("Неповні дані").font(.system(size: max(9, captionPointSize - 2))).foregroundStyle(secondary)
            }
        }
        .widgetURL(SchoolWidgetLink.tasks())
    }

    private func medium(_ snapshot: SchoolTasksWidgetSnapshot) -> some View {
        GeometryReader { geometry in
            // A medium widget is not scrollable. Determine a truthful row budget
            // without hiding overflow. At standard Dynamic Type aim for 1+4 rows.
            let rowHeight = max(16, captionPointSize + (typeSize.isAccessibilitySize ? 9 : 5))
            let maximumRows = SchoolTasksWidgetLayout.mediumRowBudget(
                availableHeight: Double(geometry.size.height),
                captionPointSize: Double(captionPointSize),
                accessibilitySize: typeSize.isAccessibilitySize,
                coverageComplete: snapshot.coverageComplete)
            let prioritized = snapshot.allPrioritized
            let overflows = prioritized.count > maximumRows
            let visibleCount = SchoolTasksWidgetLayout.visibleRowCount(totalRows: prioritized.count, rowBudget: maximumRows)
            let overdueRows = Array(snapshot.overdue.prefix(visibleCount))
            let weekRows = Array(snapshot.thisWeek.prefix(max(0, visibleCount - overdueRows.count)))
            let hidden = SchoolTasksWidgetLayout.hiddenRowCount(
                totalRows: prioritized.count,
                visibleRows: overdueRows.count + weekRows.count)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    header
                    Text(typeSize.isAccessibilitySize
                         ? "\(snapshot.openCount) відкритих · \(snapshot.completedThisWeek)/\(snapshot.totalThisWeek) тижня"
                         : "\(snapshot.openCount) відкритих")
                        .font(.system(size: max(9, captionPointSize - 1), weight: .bold))
                        .lineLimit(1)
                }
                .frame(height: max(19, captionPointSize + 8))
                if !overdueRows.isEmpty {
                    if !typeSize.isAccessibilitySize {
                        section("ПРОСТРОЧЕНІ", color: SchoolWidgetTheme.overdue)
                    }
                    ForEach(overdueRows) { item in row(item, overdue: true, height: rowHeight) }
                }
                if !weekRows.isEmpty {
                    if !typeSize.isAccessibilitySize {
                        HStack {
                            section("ЦЕЙ ТИЖДЕНЬ", color: secondary)
                            Spacer(minLength: 3)
                            Text("\(snapshot.completedThisWeek)/\(snapshot.totalThisWeek)")
                                .font(.system(size: max(9, captionPointSize - 2)))
                                .foregroundStyle(secondary)
                        }
                    }
                    ForEach(weekRows) { item in row(item, overdue: false, height: rowHeight) }
                }
                if snapshot.allPrioritized.isEmpty {
                    Text(snapshot.coverageComplete
                         ? (snapshot.openCount == 0 ? "Усі справи виконані" : "Цього тижня справ немає")
                         : "Список тимчасово недоступний")
                        .font(.system(size: captionPointSize, weight: .medium))
                        .foregroundStyle(secondary)
                        .lineLimit(2)
                        .padding(.top, 5)
                }
                if hidden > 0 {
                    Link(destination: SchoolWidgetLink.tasks()) {
                        Text("Ще \(hidden) справ · відкрити всі")
                            .font(.system(size: max(9, captionPointSize - 1), weight: .semibold))
                            .foregroundStyle(secondary)
                            .lineLimit(1)
                    }
                    .frame(height: rowHeight, alignment: .leading)
                }
                if !snapshot.coverageComplete {
                    Text("Часткові дані")
                        .font(.system(size: max(9, captionPointSize - 2)))
                        .foregroundStyle(SchoolWidgetTheme.overdue)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func section(_ title: String, color: Color) -> some View {
        Text(title).font(.system(size: max(9, captionPointSize - 2), weight: .black, design: .rounded))
            .foregroundStyle(color).frame(height: max(13, captionPointSize + 2), alignment: .bottomLeading)
    }

    private func row(_ item: SchoolTasksWidgetRow, overdue: Bool, height: CGFloat) -> some View {
        Link(destination: SchoolWidgetLink.tasks(item.id)) {
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: item.completed ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(overdue ? SchoolWidgetTheme.overdue : ink)
                    .frame(width: 15)
                Text(item.title)
                    .font(.system(size: captionPointSize, weight: item.completed ? .regular : .semibold))
                    .foregroundStyle(item.completed ? secondary : ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .privacySensitive()
                Spacer(minLength: 0)
            }
            .frame(height: height, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.completed ? "Виконано" : overdue ? "Прострочено" : "Не виконано"), \(item.title)")
    }
}

@main
struct OrbitSchoolTasksWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "orbit.school.tasks", provider: SchoolWidgetProvider()) { entry in
            SchoolTasksWidgetView(entry: entry)
        }
        .configurationDisplayName("Справи школи")
        .description("Прострочені справи й справи поточного тижня з Main Orbit.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}
