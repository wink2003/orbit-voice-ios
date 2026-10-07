import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

var state: OrbitAppLockState = .disabled
check(state == .disabled, "default state")
state.lockForBackground()
check(state == .disabled, "disabled state must not lock")
state.enable()
check(state == .unlocked, "enable")
state.lockForBackground()
check(state == .locked, "background lock")
state.unlockSucceeded()
check(state == .unlocked, "unlock")
state.disable()
check(state == .disabled, "disable")
state.unlockSucceeded()
check(state == .disabled, "disabled state must not unlock")
print("OrbitAppLockStateTests: PASS")
