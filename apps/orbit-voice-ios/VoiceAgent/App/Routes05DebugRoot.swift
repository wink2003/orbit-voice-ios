import SwiftUI

#if DEBUG
struct Routes05DebugRoot: View {
    private let arguments = ProcessInfo.processInfo.arguments
    @State private var selection: OrbitMainTab

    init() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--routes05-today") { _selection = State(initialValue: .home) }
        else if args.contains("--routes05-orbit") || args.contains("--routes05-conversation") { _selection = State(initialValue: .orbit) }
        else if args.contains("--routes05-school") || args.contains("--routes05-inbox") || args.contains("--routes05-letter") || args.contains("--routes05-tasks") || args.contains("--routes05-timetable") || args.contains("--routes05-exams") || args.contains("--routes05-brain") || args.contains("--routes05-calendar") || args.contains("--routes05-search") || args.contains("--routes05-timeline") || args.contains("--routes05-briefing") || args.contains("--routes05-notes") || args.contains("--routes05-history") { _selection = State(initialValue: .school) }
        else { _selection = State(initialValue: .family) }
    }

    private var screen: Routes05DebugScreen {
        if arguments.contains("--routes05-today") { return .today }
        if arguments.contains("--routes05-orbit") { return .orbit }
        if arguments.contains("--routes05-school") { return .school }
        if arguments.contains("--routes05-conversation") { return .conversation }
        if arguments.contains("--routes05-inbox") { return .inbox }
        if arguments.contains("--routes05-letter") { return .letter }
        if arguments.contains("--routes05-tasks") { return .tasks }
        if arguments.contains("--routes05-timetable") { return .timetable }
        if arguments.contains("--routes05-exams") { return .exams }
        if arguments.contains("--routes05-brain") { return .brain }
        if arguments.contains("--routes05-calendar") { return .calendar }
        if arguments.contains("--routes05-search") { return .search }
        if arguments.contains("--routes05-timeline") { return .timeline }
        if arguments.contains("--routes05-briefing") { return .briefing }
        if arguments.contains("--routes05-notes") { return .notes }
        if arguments.contains("--routes05-history") { return .history }
        return .family
    }

    var body: some View {
        NovaShellView(selection: $selection, debugFixture: screen)
        .preferredColorScheme(arguments.contains("--routes05-dark") ? .dark : .light)
    }
}
#endif
