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

/// Tracks whether an AppIntent-started session is safe to leave Mini's
/// foreground scene. It intentionally has no audio or UIKit operations:
/// Room connection, local PCM, and presentation must all be real before any
/// external presentation transition is requested.
struct OrbitMiniShortcutReturnReadinessStateMachine: Equatable {
    enum Phase: Equatable {
        case idle
        case starting(id: String)
        case ready(id: String)
        case failed(id: String)
        case cancelled(id: String)
    }

    private(set) var phase: Phase = .idle
    private var roomConnected = false
    private var firstPCMReceived = false
    private var presentationEstablished = false

    var activeStartID: String? {
        switch phase {
        case let .starting(id), let .ready(id), let .failed(id), let .cancelled(id): id
        case .idle: nil
        }
    }

    var isReady: Bool {
        if case .ready = phase { return true }
        return false
    }

    mutating func begin(id: String) -> Bool {
        guard phase == .idle || isTerminal else { return false }
        phase = .starting(id: id)
        roomConnected = false
        firstPCMReceived = false
        presentationEstablished = false
        return true
    }

    mutating func roomConnected(id: String) {
        guard case let .starting(activeID) = phase, activeID == id else { return }
        roomConnected = true
        promoteIfReady(id: id)
    }

    mutating func receivedFirstPCM(id: String) {
        guard case let .starting(activeID) = phase, activeID == id else { return }
        firstPCMReceived = true
        promoteIfReady(id: id)
    }

    mutating func presentationEstablished(id: String) {
        guard case let .starting(activeID) = phase, activeID == id else { return }
        presentationEstablished = true
        promoteIfReady(id: id)
    }

    mutating func fail(id: String) {
        guard case let .starting(activeID) = phase, activeID == id else { return }
        phase = .failed(id: id)
    }

    mutating func cancel(id: String) {
        guard case let .starting(activeID) = phase, activeID == id else { return }
        phase = .cancelled(id: id)
    }

    private var isTerminal: Bool {
        switch phase {
        case .ready, .failed, .cancelled: true
        case .idle, .starting: false
        }
    }

    private mutating func promoteIfReady(id: String) {
        guard roomConnected, firstPCMReceived, presentationEstablished else { return }
        phase = .ready(id: id)
    }
}

/// Claims one public UIKit scene-dismissal request after a hands-free
/// AppIntent has reached the readiness contract above. A claim is one-shot:
/// duplicate Room/PCM/presentation events cannot dismiss the scene twice.
struct OrbitMiniSceneReturnStateMachine: Equatable {
    enum Phase: Equatable {
        case idle
        case armed(id: String)
        case requested(id: String)
        case cancelled(id: String)
    }

    private(set) var phase: Phase = .idle

    mutating func arm(id: String) -> Bool {
        guard phase == .idle || isTerminal else { return false }
        phase = .armed(id: id)
        return true
    }

    mutating func claimIfReady(id: String, readiness: OrbitMiniShortcutReturnReadinessStateMachine) -> Bool {
        guard case let .armed(activeID) = phase, activeID == id,
              readiness.isReady,
              readiness.activeStartID == id
        else { return false }
        phase = .requested(id: id)
        return true
    }

    mutating func cancel(id: String) {
        guard case let .armed(activeID) = phase, activeID == id else { return }
        phase = .cancelled(id: id)
    }

    private var isTerminal: Bool {
        switch phase {
        case .requested, .cancelled: true
        case .idle, .armed: false
        }
    }
}
