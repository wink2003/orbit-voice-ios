import Foundation

@main
struct OrbitAccountSessionStateTests {
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("OrbitAccountSessionStateTests: \(message)") }
    }

    static func main() {
        expect(OrbitAccountSessionState(hasDeviceToken: false, hasSessionToken: false) == .unpaired, "unpaired state")
        expect(OrbitAccountSessionState(hasDeviceToken: true, hasSessionToken: false) == .legacyOnly, "legacy-only state")
        expect(OrbitAccountSessionState(hasDeviceToken: true, hasSessionToken: true) == .accountSession, "session takes precedence")
        expect(OrbitAccountSessionState(hasDeviceToken: false, hasSessionToken: true) == .accountSession, "session state")
        expect(OrbitAccountSessionState(hasDeviceToken: true, hasSessionToken: false) == .legacyOnly, "logout falls back to device token")
        print("OrbitAccountSessionStateTests: PASS")
    }
}
