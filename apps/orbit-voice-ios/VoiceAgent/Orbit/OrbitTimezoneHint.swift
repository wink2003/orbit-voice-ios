import Foundation

enum OrbitTimezoneHint {
    static func currentIdentifier() -> String {
        TimeZone.current.identifier
    }
}
