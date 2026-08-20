import Foundation

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
