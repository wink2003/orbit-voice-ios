import SwiftUI

#if DEBUG
struct Routes05DebugRoot: View {
    private let arguments = ProcessInfo.processInfo.arguments

    var body: some View {
        Group {
            if arguments.contains("--routes05-today") {
                OrbitTodayView(open: { _ in }, displayName: "Олена", fixture: Routes05DebugFixtures.today)
            } else if arguments.contains("--routes05-orbit") {
                OrbitChatsView(fixture: Routes05DebugFixtures.chats)
            } else if arguments.contains("--routes05-school") {
                SchoolHubView(fixture: Routes05DebugFixtures.school)
            } else {
                MainOrbit3FamilyView(fixture: Routes05DebugFixtures.family)
            }
        }
        .preferredColorScheme(arguments.contains("--routes05-dark") ? .dark : .light)
    }
}
#endif
