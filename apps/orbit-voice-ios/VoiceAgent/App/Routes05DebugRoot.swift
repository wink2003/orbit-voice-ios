import SwiftUI

#if DEBUG
struct Routes05DebugRoot: View {
    private let arguments = ProcessInfo.processInfo.arguments
    @State private var selection: OrbitMainTab

    init() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--routes05-today") { _selection = State(initialValue: .home) }
        else if args.contains("--routes05-orbit") || args.contains("--routes05-conversation") { _selection = State(initialValue: .orbit) }
        else if args.contains(where: { $0.hasPrefix("--routes05-") }) { _selection = State(initialValue: .school) }
        else { _selection = State(initialValue: .family) }
    }

    private var screen: Routes05DebugScreen {
        if arguments.contains("--routes05-today") { return .today }
        if arguments.contains("--routes05-orbit") || arguments.contains("--routes05-chats") { return .orbit }
        if arguments.contains("--routes05-school") { return .school }
        if arguments.contains("--routes05-conversation") { return .conversation }
        if arguments.contains("--routes05-inbox") { return .inbox }
        if arguments.contains("--routes05-letter") { return .letter }
        if arguments.contains("--routes05-tasks") { return .tasks }
        if arguments.contains("--routes05-timetable") { return .timetable }
        if arguments.contains("--routes05-exams") { return .exams }
        if arguments.contains("--routes05-brain") || arguments.contains("--routes05-schoolbrain") { return .brain }
        if arguments.contains("--routes05-calendar") { return .calendar }
        if arguments.contains("--routes05-schoolcalendar") { return .schoolCalendar }
        if arguments.contains("--routes05-search") || arguments.contains("--routes05-schoolsearch") { return .search }
        if arguments.contains("--routes05-timeline") || arguments.contains("--routes05-schooltimeline") { return .timeline }
        if arguments.contains("--routes05-briefing") || arguments.contains("--routes05-schoolbriefing") { return .briefing }
        if arguments.contains("--routes05-notes") || arguments.contains("--routes05-schoolnotes") { return .notes }
        if arguments.contains("--routes05-history") || arguments.contains("--routes05-schoolhistory") { return .history }
        if arguments.contains("--routes05-contacts") { return .contacts }
        if arguments.contains("--routes05-memory") { return .memory }
        if arguments.contains("--routes05-voice") { return .voice }
        if arguments.contains("--routes05-familychat") { return .familyChat }
        if arguments.contains("--routes05-settings") { return .settings }
        if arguments.contains("--routes05-integrations") { return .integrations }
        if arguments.contains("--routes05-memorydetail") { return .memoryDetail }
        if arguments.contains("--routes05-contactdetail") { return .contactDetail }
        if arguments.contains("--routes05-actionconfirm") { return .actionConfirm }
        if arguments.contains("--routes05-admin") { return .admin }
        if arguments.contains("--routes05-profile") { return .profile }
        if arguments.contains("--routes05-notifications") { return .notifications }
        if arguments.contains("--routes05-memoryimports") { return .memoryImports }
        if arguments.contains("--routes05-unknown") { return .unknown }
        return .family
    }

    var body: some View {
        NovaShellView(selection: $selection, debugFixture: screen)
        .preferredColorScheme(arguments.contains("--routes05-dark") ? .dark : .light)
    }
}
#endif
