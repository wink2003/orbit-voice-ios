import LiveKit
import SwiftUI
import Foundation

struct AppView: View {
    @EnvironmentObject private var authentication: OrbitAuthentication
    @Namespace private var namespace
    @AppStorage("orbit.appearance") private var appearance = "system"
    @State private var selectedTab = OrbitNavigation.defaultTab

    var body: some View {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--orbit-nova-fixture") {
            authenticatedRoot
        } else {
            authenticatedRoot
        }
#else
        authenticatedRoot
#endif
    }

    private var authenticatedRoot: some View {
        Group {
            if authentication.identityResolved {
                tabs
            } else {
                ProgressView("Завантаження Orbit…")
            }
        }
        .task { await authentication.refreshIdentity() }
    }

    private var tabs: some View {
        NovaShellView(selection: $selectedTab)
            .environment(\.namespace, namespace)
            .preferredColorScheme(preferredColorScheme)
    }

    private var preferredColorScheme: ColorScheme? {
        switch appearance {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }
}
