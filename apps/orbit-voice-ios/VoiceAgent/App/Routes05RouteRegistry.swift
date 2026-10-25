import Foundation

/// The checked-in ROUTES 05 handoff is the screen inventory.  This registry
/// keeps that inventory explicit in the native app so every design route has a
/// verified owner instead of silently falling through to a generic screen.
struct Routes05RouteDescriptor: Identifiable, Hashable {
    let id: String
    let title: String
    let group: String
    let owner: String

    var identity: String { id }
}
enum Routes05RouteRegistry {
    static let all: [Routes05RouteDescriptor] = [
        .init(id: "today", title: "Today", group: "Core", owner: "OrbitTodayView"),
        .init(id: "chats", title: "Розмови", group: "Core", owner: "OrbitChatsView"),
        .init(id: "conversation", title: "Розмова", group: "Core", owner: "OrbitChatsView"),
        .init(id: "school", title: "Школа", group: "Core", owner: "SchoolHubView"),
        .init(id: "family", title: "Сім’я", group: "Core", owner: "MainOrbit3FamilyView"),
        .init(id: "calendar", title: "Календар", group: "Core", owner: "OrbitCalendarView"),
        .init(id: "contacts", title: "Контакти", group: "Core", owner: "OrbitContactsView"),
        .init(id: "memory", title: "Пам’ять", group: "Core", owner: "MemoryCenterView"),
        .init(id: "inbox", title: "Вхідні", group: "School", owner: "SchoolInboxView"),
        .init(id: "letter", title: "Лист", group: "School", owner: "SchoolInboxView"),
        .init(id: "tasks", title: "Справи", group: "School", owner: "SchoolTaskListView"),
        .init(id: "timetable", title: "Розклад", group: "School", owner: "SchoolHubV2View"),
        .init(id: "exams", title: "Іспити", group: "School", owner: "SchoolHubV2View"),
        .init(id: "schoolbrain", title: "School Brain", group: "School", owner: "SchoolBrainView"),
        .init(id: "schoolcalendar", title: "Календар школи", group: "School", owner: "SchoolWeekCalendarView"),
        .init(id: "schoolsearch", title: "Пошук у школі", group: "School", owner: "SchoolUnifiedSearchView"),
        .init(id: "voice", title: "Голос", group: "System", owner: "MainVoiceHomeView"),
        .init(id: "familychat", title: "Родинний чат", group: "System", owner: "FamilyMessengerView"),
        .init(id: "settings", title: "Налаштування", group: "System", owner: "OrbitSettingsView"),
        .init(id: "integrations", title: "Інтеграції", group: "System", owner: "OrbitToolsView"),
        .init(id: "memorydetail", title: "Факт пам’яті", group: "System", owner: "MemoryCenterView"),
        .init(id: "contactdetail", title: "Контакт", group: "System", owner: "OrbitContactsView"),
        .init(id: "actionconfirm", title: "Підтвердження дії", group: "System", owner: "OrbitChatsView"),
        .init(id: "admin", title: "Admin", group: "System", owner: "OrbitDashboardView"),
        .init(id: "schooltimeline", title: "Хронологія школи", group: "Discovery", owner: "SchoolTimelineView"),
        .init(id: "schoolbriefing", title: "Огляд школи", group: "Discovery", owner: "SchoolTasksView"),
        .init(id: "schoolnotes", title: "Нотатки", group: "Discovery", owner: "SchoolNotesView"),
        .init(id: "schoolhistory", title: "Історія справ", group: "Discovery", owner: "SchoolActionHistoryView"),
        .init(id: "profile", title: "Профіль і доступ", group: "Discovery", owner: "OrbitSettingsView"),
        .init(id: "notifications", title: "Сповіщення", group: "Discovery", owner: "OrbitMoreView"),
        .init(id: "memoryimports", title: "Імпорти пам’яті", group: "Discovery", owner: "MemoryCenterView"),
        .init(id: "unknown", title: "Новий розділ — шаблон", group: "Discovery", owner: "Routes05UnavailableView")
    ]

    static func descriptor(for id: String) -> Routes05RouteDescriptor? {
        all.first { $0.id == id }
    }
}
