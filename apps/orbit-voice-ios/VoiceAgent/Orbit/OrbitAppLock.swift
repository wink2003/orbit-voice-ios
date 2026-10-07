import Combine
import Foundation
import LocalAuthentication

@MainActor
final class OrbitAppLock: ObservableObject {
    private static let enabledKey = "orbit.main.appLock.enabled"

    @Published private(set) var state: OrbitAppLockState
    @Published private(set) var isAuthenticating = false
    @Published private(set) var lastError: String?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        state = defaults.bool(forKey: Self.enabledKey) ? .locked : .disabled
    }

    var isEnabled: Bool { state != .disabled }
    var isLocked: Bool { state == .locked }

    var availabilityDescription: String {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return "Код-пароль пристрою недоступний"
        }
        switch context.biometryType {
        case .faceID: return "Face ID або код-пароль"
        case .touchID: return "Touch ID або код-пароль"
        default: return "Код-пароль пристрою"
        }
    }

    func enable() async -> Bool {
        guard !isEnabled else { return true }
        guard await authenticate(reason: "Увімкніть захист Main Orbit") else { return false }
        state.enable()
        defaults.set(true, forKey: Self.enabledKey)
        lastError = nil
        return true
    }

    func disable() {
        state.disable()
        defaults.set(false, forKey: Self.enabledKey)
        lastError = nil
    }

    func lockForBackground(isVoiceActive: Bool) {
        // Never interrupt or obscure an active voice session. The next idle
        // background transition will lock the UI normally.
        guard !isVoiceActive else { return }
        state.lockForBackground()
    }

    func unlock() async -> Bool {
        guard isEnabled else { return true }
        guard await authenticate(reason: "Розблокуйте Main Orbit") else { return false }
        state.unlockSucceeded()
        lastError = nil
        return true
    }

    private func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "Ввести код-пароль"
        var availabilityError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &availabilityError) else {
            lastError = "Налаштуйте Face ID, Touch ID або код-пароль пристрою."
            return false
        }

        isAuthenticating = true
        let success = await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }
        isAuthenticating = false
        if !success { lastError = "Розблокування не виконано. Спробуйте ще раз." }
        return success
    }
}
