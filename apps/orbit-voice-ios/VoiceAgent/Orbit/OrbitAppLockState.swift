enum OrbitAppLockState: Equatable {
    case disabled
    case unlocked
    case locked

    mutating func enable() { self = .unlocked }
    mutating func disable() { self = .disabled }
    mutating func lockForBackground() {
        if self != .disabled { self = .locked }
    }
    mutating func unlockSucceeded() {
        if self != .disabled { self = .unlocked }
    }
}
