import Foundation

@main
struct OrbitTimezoneHintTests {
    static func main() {
        precondition(OrbitTimezoneHint.currentIdentifier() == TimeZone.current.identifier, "timezone hint must use the current device IANA identifier")
        precondition(!OrbitTimezoneHint.currentIdentifier().isEmpty, "timezone hint must not be empty on a supported device")
        print("OrbitTimezoneHintTests passed")
    }
}
