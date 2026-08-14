import Foundation

/// Pure, deterministic policy for the Siri-to-Mini microphone handoff.
///
/// UIKit, AVAudioSession and LiveKit perform the effects; this type only owns
/// ordering and retry bounds so notifications and timeout fallbacks cannot
/// create two concurrent audio starts.
struct OrbitMiniAudioHandoffStateMachine: Equatable {
    enum Phase: Equatable {
        case idle
        case waitingForForeground
        case waitingForAudioRelease
        case readyToProbe
        case probing(attempt: Int)
        case waitingForRetry(attempt: Int)
        case readyForSession
        case failed
        case cancelled
    }

    enum Event: Equatable {
        case requested(appIsActive: Bool, interruptionActive: Bool)
        case appBecameActive
        case interruptionBegan
        case interruptionEnded
        case audioReadinessChanged
        case boundedWaitExpired
        case probeSucceeded
        case probeFailed(transient: Bool)
        case cancel
    }

    let maximumProbeAttempts: Int
    private(set) var phase: Phase = .idle
    private(set) var appIsActive = false
    private(set) var interruptionActive = false
    private(set) var probeAttempts = 0

    init(maximumProbeAttempts: Int = 4) {
        precondition(maximumProbeAttempts > 0)
        self.maximumProbeAttempts = maximumProbeAttempts
    }

    mutating func handle(_ event: Event) {
        guard phase != .failed, phase != .cancelled, phase != .readyForSession else { return }

        switch event {
        case let .requested(appIsActive, interruptionActive):
            guard phase == .idle else { return }
            self.appIsActive = appIsActive
            self.interruptionActive = interruptionActive
            reconcileReadiness()

        case .appBecameActive:
            appIsActive = true
            if case .probing = phase { return }
            reconcileReadiness()

        case .interruptionBegan:
            interruptionActive = true
            if case .probing = phase {
                // The in-flight probe owns its cleanup. Its result is then
                // reconciled against this interruption flag.
                return
            }
            phase = .waitingForAudioRelease

        case .interruptionEnded:
            interruptionActive = false
            if case .probing = phase { return }
            reconcileReadiness()

        case .audioReadinessChanged:
            if case .waitingForRetry = phase { reconcileReadiness() }

        case .boundedWaitExpired:
            // Foreground/interruption notifications can predate observer
            // installation. A bounded fallback may open a probe, whose actual
            // engine start + PCM frame remains the readiness authority.
            if case .waitingForForeground = phase { appIsActive = true }
            if case .waitingForAudioRelease = phase { interruptionActive = false }
            reconcileReadiness()

        case .probeSucceeded:
            guard case .probing = phase else { return }
            phase = interruptionActive ? .waitingForAudioRelease : .readyForSession

        case let .probeFailed(transient):
            guard case .probing = phase else { return }
            if transient, probeAttempts < maximumProbeAttempts {
                phase = interruptionActive ? .waitingForAudioRelease : .waitingForRetry(attempt: probeAttempts)
            } else {
                phase = .failed
            }

        case .cancel:
            phase = .cancelled
        }
    }

    /// Atomically claims the next probe. Calling this twice without a probe
    /// result cannot create a second engine.
    mutating func beginProbe() -> Int? {
        guard phase == .readyToProbe, probeAttempts < maximumProbeAttempts else { return nil }
        probeAttempts += 1
        phase = .probing(attempt: probeAttempts)
        return probeAttempts
    }

    private mutating func reconcileReadiness() {
        if interruptionActive {
            phase = .waitingForAudioRelease
        } else if !appIsActive {
            phase = .waitingForForeground
        } else {
            phase = .readyToProbe
        }
    }
}
