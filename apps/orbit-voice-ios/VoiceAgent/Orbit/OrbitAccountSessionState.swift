import Foundation

enum OrbitAccountSessionState: Equatable {
    case unpaired
    case legacyOnly
    case accountSession

    init(hasDeviceToken: Bool, hasSessionToken: Bool) {
        if hasSessionToken {
            self = .accountSession
        } else if hasDeviceToken {
            self = .legacyOnly
        } else {
            self = .unpaired
        }
    }
}
