import SwiftUI

#if DEBUG
struct Routes05DebugRoot: View {
    private let arguments = ProcessInfo.processInfo.arguments
    @State private var selection: OrbitMainTab

    init() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--routes05-today") { _selection = State(initialValue: .home) }
        else if args.contains("--routes05-orbit") { _selection = State(initialValue: .orbit) }
        else if args.contains("--routes05-school") { _selection = State(initialValue: .school) }
        else { _selection = State(initialValue: .family) }
    }

    private var screen: Routes05DebugScreen {
        if arguments.contains("--routes05-today") { return .today }
        if arguments.contains("--routes05-orbit") { return .orbit }
        if arguments.contains("--routes05-school") { return .school }
        return .family
    }

    var body: some View {
        NovaShellView(selection: $selection, debugFixture: screen)
        .preferredColorScheme(arguments.contains("--routes05-dark") ? .dark : .light)
    }
}
#endif
