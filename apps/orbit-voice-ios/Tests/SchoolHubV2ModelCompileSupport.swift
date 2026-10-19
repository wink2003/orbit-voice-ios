import Foundation

// The focused Linux/macOS swiftc model test does not link the app's
// authentication stack. These no-op declarations keep MainProductAPI's
// request implementation type-checkable without importing LiveKit/UIKit.
enum KeychainStore {
    static func readMainBearerToken() -> String? { nil }
    static func readSessionToken() -> String? { nil }
}

enum OrbitAuthentication {
    static func refreshStoredSession() async -> Bool { false }
}
