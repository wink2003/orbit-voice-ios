import Foundation

// The UIKit foreground gate is integration-tested on device. These pure tests
// protect only bounded, serialized Session retries; Mini has no scene-return
// or audio-handoff state machine.
@main
enum OrbitMiniSessionRetryTests {
    static func main() {
        var retry = OrbitMiniSessionStartRetryStateMachine(maximumAttempts: 2)
        retry.begin()
        expect(retry.claimAttempt() == 1, "first Session.start claim succeeds")
        expect(retry.claimAttempt() == nil, "parallel Session.start is rejected")
        retry.failed(transient: true)
        expect(retry.phase == .waitingForRetry(attempt: 1), "cleanup boundary precedes retry")
        retry.retryDelayElapsed()
        expect(retry.claimAttempt() == 2, "one bounded retry starts")
        retry.failed(transient: true)
        expect(retry.phase == .failed, "retry limit is terminal")
        retry.cancel()
        expect(retry.phase == .cancelled, "cancellation is terminal")
        print("OrbitMiniSessionRetryTests: PASS")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
