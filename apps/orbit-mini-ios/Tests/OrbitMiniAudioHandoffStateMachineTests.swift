import Foundation

@main
enum OrbitMiniAudioHandoffStateMachineTests {
    static func main() {
        inAppDirectPathDoesNotNeedHandoffMutation()
        delayedApplicationActivationStartsOneSession()
        lifecycleTimeoutStartsZeroSessions()
        delayedActivationDoesNotBurnAudioAttempts()
        lifecycleSignalAndTimeoutRaceIsTerminal()
        cancellationWhileWaitingForActiveIsTerminal()
        observedInterruptionBlocksSessionUntilRelease()
        missedInterruptionEndHasBoundedPostActiveFallback()
        validPreviousAppReturnDoesNotUndoEstablishedSession()
        invalidPreviousAppReturnCannotAbortPendingStartup()
        retryClaimsExactlyOneSessionStartAtATime()
        transientSessionFailureRetriesOnlyAfterCleanupBoundary()
        transientSessionRetriesAreBounded()
        permanentSessionFailureIsTerminal()
        cancellationDuringSessionStartIsTerminal()
        shortcutReturnBlocksUntilSessionAndPCM()
        shortcutReturnFailureNeverReleasesPreviousApp()
        shortcutReturnCancellationNeverReleasesPreviousApp()
        duplicateShortcutStartDoesNotCreateAnotherReadinessToken()
        readyShortcutReturnSurvivesBackgroundTransition()
        print("OrbitMiniAudioHandoffStateMachineTests: PASS")
    }

    private static func inAppDirectPathDoesNotNeedHandoffMutation() {
        // The button keeps its pre-existing Session.start path. The handoff
        // policy is intentionally not initialized for this source.
        var retry = OrbitMiniSessionStartRetryStateMachine()
        retry.begin()
        expect(retry.claimAttempt() == 1, "direct Session.start can claim one attempt")
    }

    private static func delayedApplicationActivationStartsOneSession() {
        var handoff = OrbitMiniAudioHandoffStateMachine()
        handoff.handle(.requested(appIsActive: false, interruptionActive: false))
        expect(handoff.phase == .waitingForForeground, "inactive Shortcut launch must wait")
        handoff.handle(.appBecameActive)
        expect(handoff.phase == .readyForSession, "real activation opens the normal Session path")
    }

    private static func lifecycleTimeoutStartsZeroSessions() {
        var handoff = OrbitMiniAudioHandoffStateMachine()
        handoff.handle(.requested(appIsActive: false, interruptionActive: false))
        handoff.handle(.lifecycleWaitExpired)
        expect(handoff.phase == .lifecycleTimedOut, "inactive deadline needs a distinct failure")
        var retry = OrbitMiniSessionStartRetryStateMachine()
        expect(retry.claimAttempt() == nil, "lifecycle timeout must start zero Sessions")
    }

    private static func delayedActivationDoesNotBurnAudioAttempts() {
        var handoff = OrbitMiniAudioHandoffStateMachine()
        handoff.handle(.requested(appIsActive: false, interruptionActive: false))
        handoff.handle(.audioReleaseWaitExpired)
        expect(handoff.phase == .waitingForForeground, "audio timeout cannot forge activation")
        handoff.handle(.appBecameActive)
        expect(handoff.phase == .readyForSession, "late activation remains valid")
    }

    private static func lifecycleSignalAndTimeoutRaceIsTerminal() {
        var signalFirst = OrbitMiniAudioHandoffStateMachine()
        signalFirst.handle(.requested(appIsActive: false, interruptionActive: false))
        signalFirst.handle(.appBecameActive)
        signalFirst.handle(.lifecycleWaitExpired)
        expect(signalFirst.phase == .readyForSession, "late timeout cannot revoke activation")

        var timeoutFirst = OrbitMiniAudioHandoffStateMachine()
        timeoutFirst.handle(.requested(appIsActive: false, interruptionActive: false))
        timeoutFirst.handle(.lifecycleWaitExpired)
        timeoutFirst.handle(.appBecameActive)
        expect(timeoutFirst.phase == .lifecycleTimedOut, "late signal cannot revive timed out startup")
    }

    private static func cancellationWhileWaitingForActiveIsTerminal() {
        var handoff = OrbitMiniAudioHandoffStateMachine()
        handoff.handle(.requested(appIsActive: false, interruptionActive: false))
        handoff.handle(.cancel)
        handoff.handle(.appBecameActive)
        expect(handoff.phase == .cancelled, "late activation cannot revive cancellation")
    }

    private static func observedInterruptionBlocksSessionUntilRelease() {
        var handoff = OrbitMiniAudioHandoffStateMachine()
        handoff.handle(.requested(appIsActive: true, interruptionActive: true))
        expect(handoff.phase == .waitingForAudioRelease, "observed interruption blocks Session.start")
        handoff.handle(.interruptionEnded)
        expect(handoff.phase == .readyForSession, "release opens Session.start")
    }

    private static func missedInterruptionEndHasBoundedPostActiveFallback() {
        var handoff = OrbitMiniAudioHandoffStateMachine()
        handoff.handle(.requested(appIsActive: true, interruptionActive: true))
        handoff.handle(.audioReleaseWaitExpired)
        expect(handoff.phase == .readyForSession, "only post-active audio fallback may proceed")
    }

    private static func validPreviousAppReturnDoesNotUndoEstablishedSession() {
        var handoff = OrbitMiniAudioHandoffStateMachine()
        handoff.handle(.requested(appIsActive: true, interruptionActive: false))
        expect(handoff.phase == .readyForSession, "active Mini can start Session before valid return")
        // A later background transition belongs to the already-running session,
        // not the startup gate.
        handoff.handle(.appBecameInactive)
        expect(handoff.phase == .readyForSession, "terminal ready state preserves background continuation")
    }

    private static func invalidPreviousAppReturnCannotAbortPendingStartup() {
        var handoff = OrbitMiniAudioHandoffStateMachine()
        handoff.handle(.requested(appIsActive: false, interruptionActive: false))
        // External Open App has no callback into Mini. It is deliberately not
        // a failure event; Mini waits for UIKit's actual activation.
        handoff.handle(.appBecameActive)
        expect(handoff.phase == .readyForSession, "external Shortcut failure cannot poison startup")
    }

    private static func retryClaimsExactlyOneSessionStartAtATime() {
        var retry = OrbitMiniSessionStartRetryStateMachine()
        retry.begin()
        expect(retry.claimAttempt() == 1, "first Session.start claim succeeds")
        expect(retry.claimAttempt() == nil, "parallel Session.start claim is rejected")
    }

    private static func transientSessionFailureRetriesOnlyAfterCleanupBoundary() {
        var retry = OrbitMiniSessionStartRetryStateMachine(maximumAttempts: 3)
        retry.begin()
        _ = retry.claimAttempt()
        retry.failed(transient: true)
        expect(retry.phase == .waitingForRetry(attempt: 1), "transient failure waits for cleanup/backoff")
        expect(retry.claimAttempt() == nil, "retry cannot start before cleanup boundary")
        retry.retryDelayElapsed()
        expect(retry.claimAttempt() == 2, "one later Session retry may start")
    }

    private static func permanentSessionFailureIsTerminal() {
        var retry = OrbitMiniSessionStartRetryStateMachine()
        retry.begin()
        _ = retry.claimAttempt()
        retry.failed(transient: false)
        expect(retry.phase == .failed, "permanent failure cannot loop")
        expect(retry.claimAttempt() == nil, "failed state cannot execute another Session.start")
    }

    private static func transientSessionRetriesAreBounded() {
        var retry = OrbitMiniSessionStartRetryStateMachine(maximumAttempts: 2)
        retry.begin()
        expect(retry.claimAttempt() == 1, "first bounded attempt starts")
        retry.failed(transient: true)
        retry.retryDelayElapsed()
        expect(retry.claimAttempt() == 2, "one bounded retry starts")
        retry.failed(transient: true)
        expect(retry.phase == .failed, "last transient failure is terminal")
        expect(retry.claimAttempt() == nil, "retry limit cannot start a third Session")
    }

    private static func cancellationDuringSessionStartIsTerminal() {
        var retry = OrbitMiniSessionStartRetryStateMachine()
        retry.begin()
        _ = retry.claimAttempt()
        retry.cancel()
        retry.succeeded()
        expect(retry.phase == .cancelled, "late Session completion cannot revive cancellation")
    }

    private static func shortcutReturnBlocksUntilSessionAndPCM() {
        var readiness = OrbitMiniShortcutReturnReadinessStateMachine()
        expect(readiness.begin(id: "one"), "first Shortcut start creates one readiness token")
        expect(!readiness.isReady, "Open PreviousApp must wait before voice starts")
        readiness.roomConnected(id: "one")
        expect(!readiness.isReady, "Room connection alone is not capture proof")
        readiness.receivedFirstPCM(id: "one")
        expect(!readiness.isReady, "capture alone must not race Live Activity setup")
        readiness.presentationEstablished(id: "one")
        expect(readiness.isReady, "connected Session plus PCM and presentation releases previous-app return")
    }

    private static func shortcutReturnFailureNeverReleasesPreviousApp() {
        var readiness = OrbitMiniShortcutReturnReadinessStateMachine()
        _ = readiness.begin(id: "one")
        readiness.fail(id: "one")
        expect(!readiness.isReady, "failed voice startup must not return to PreviousApp")
        expect(readiness.phase == .failed(id: "one"), "failed start is terminal")
    }

    private static func shortcutReturnCancellationNeverReleasesPreviousApp() {
        var readiness = OrbitMiniShortcutReturnReadinessStateMachine()
        _ = readiness.begin(id: "one")
        readiness.cancel(id: "one")
        readiness.receivedFirstPCM(id: "one")
        readiness.roomConnected(id: "one")
        readiness.presentationEstablished(id: "one")
        expect(!readiness.isReady, "late audio cannot revive cancelled startup")
        expect(readiness.phase == .cancelled(id: "one"), "cancelled start remains terminal")
    }

    private static func duplicateShortcutStartDoesNotCreateAnotherReadinessToken() {
        var readiness = OrbitMiniShortcutReturnReadinessStateMachine()
        expect(readiness.begin(id: "one"), "first start is accepted")
        expect(!readiness.begin(id: "two"), "duplicate start cannot replace a pending token")
        expect(readiness.activeStartID == "one", "original readiness token remains authoritative")
    }

    private static func readyShortcutReturnSurvivesBackgroundTransition() {
        var readiness = OrbitMiniShortcutReturnReadinessStateMachine()
        _ = readiness.begin(id: "one")
        readiness.receivedFirstPCM(id: "one")
        readiness.roomConnected(id: "one")
        readiness.presentationEstablished(id: "one")
        // The return action is external. Once ready, moving Mini background
        // must not undo the established voice/background session.
        expect(readiness.isReady, "valid PreviousApp return preserves readiness")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
