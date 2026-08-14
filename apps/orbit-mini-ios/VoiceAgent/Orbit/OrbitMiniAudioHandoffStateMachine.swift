import Foundation

/// Pure, deterministic gate for handing an App Intent to the normal LiveKit
/// Session startup. It deliberately owns no AudioDeviceModule operations:
/// LiveKit's Session/PreConnectAudioBuffer is the single owner of capture.
struct OrbitMiniAudioHandoffStateMachine: Equatable {
    enum Phase: Equatable {
        case idle
        case waitingForForeground
        case waitingForAudioRelease
        case readyForSession
        case lifecycleTimedOut
        case cancelled
    }

    enum Event: Equatable {
        case requested(appIsActive: Bool, interruptionActive: Bool)
        case appBecameActive
        case appBecameInactive
        case lifecycleWaitExpired
        case interruptionBegan
        case interruptionEnded
        case audioReleaseWaitExpired
        case cancel
    }

    private(set) var phase: Phase = .idle
    private(set) var appIsActive = false
    private(set) var interruptionActive = false

    mutating func handle(_ event: Event) {
        guard phase != .lifecycleTimedOut,
              phase != .cancelled,
              phase != .readyForSession
        else { return }

        switch event {
        case let .requested(appIsActive, interruptionActive):
            guard phase == .idle else { return }
            self.appIsActive = appIsActive
            self.interruptionActive = interruptionActive
            reconcileReadiness()

        case .appBecameActive:
            appIsActive = true
            reconcileReadiness()

        case .appBecameInactive:
            appIsActive = false
            reconcileReadiness()

        case .lifecycleWaitExpired:
            guard phase == .waitingForForeground else { return }
            phase = .lifecycleTimedOut

        case .interruptionBegan:
            interruptionActive = true
            reconcileReadiness()

        case .interruptionEnded:
            interruptionActive = false
            reconcileReadiness()

        case .audioReleaseWaitExpired:
            // An interruption-ended notification can precede observer setup.
            // This fallback is allowed only after the independent lifecycle
            // gate is satisfied; it never fabricates foreground-active state.
            guard phase == .waitingForAudioRelease else { return }
            interruptionActive = false
            reconcileReadiness()

        case .cancel:
            phase = .cancelled
        }
    }

    private mutating func reconcileReadiness() {
        if !appIsActive {
            phase = .waitingForForeground
        } else if interruptionActive {
            phase = .waitingForAudioRelease
        } else {
            phase = .readyForSession
        }
    }
}

/// Separates idempotent, bounded full Session retries from lifecycle gating.
/// Each claimed attempt must either become terminal or be fully cleaned up
/// before a later claim can occur.
struct OrbitMiniSessionStartRetryStateMachine: Equatable {
    enum Phase: Equatable {
        case idle
        case ready
        case starting(attempt: Int)
        case waitingForRetry(attempt: Int)
        case succeeded
        case failed
        case cancelled
    }

    let maximumAttempts: Int
    private(set) var phase: Phase = .idle
    private(set) var attempts = 0

    init(maximumAttempts: Int = 3) {
        precondition(maximumAttempts > 0)
        self.maximumAttempts = maximumAttempts
    }

    mutating func begin() {
        guard phase == .idle else { return }
        phase = .ready
    }

    mutating func claimAttempt() -> Int? {
        guard phase == .ready, attempts < maximumAttempts else { return nil }
        attempts += 1
        phase = .starting(attempt: attempts)
        return attempts
    }

    mutating func succeeded() {
        guard case .starting = phase else { return }
        phase = .succeeded
    }

    mutating func failed(transient: Bool) {
        guard case .starting = phase else { return }
        if transient, attempts < maximumAttempts {
            phase = .waitingForRetry(attempt: attempts)
        } else {
            phase = .failed
        }
    }

    mutating func retryDelayElapsed() {
        guard case .waitingForRetry = phase else { return }
        phase = .ready
    }

    mutating func cancel() {
        phase = .cancelled
    }
}
