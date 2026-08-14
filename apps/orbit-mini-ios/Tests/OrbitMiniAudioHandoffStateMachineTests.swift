import Foundation

@main
enum OrbitMiniAudioHandoffStateMachineTests {
    static func main() {
        immediateTypedSiriPath()
        delayedApplicationActivationStartsExactlyOneProbe()
        lifecycleTimeoutStartsZeroProbes()
        delayedActivationIsNotADeadlineFailure()
        lifecycleSignalWinsTimeoutRace()
        lifecycleTimeoutWinsSignalRace()
        cancellationWhileWaitingForActiveIsTerminal()
        validPreviousAppReturnPreservesCapturedSession()
        invalidPreviousAppReturnCannotAbortMiniStartup()
        observedVoiceSiriInterruptionPath()
        inactiveLifecyclePrecedesAudioInterruptionWait()
        missedInterruptionUsesBoundedProbeRecovery()
        postActivationADMFailureUsesBoundedRetry()
        engineWithoutPCMRemainsAnAudioRetry()
        transientAttemptsAreBounded()
        permanentFailureDoesNotRetry()
        probeClaimIsIdempotent()
        interruptionDuringProbeMustReleaseBeforeSession()
        completeInterruptionDuringProbeDoesNotDuplicateProbe()
        missedInterruptionEndCanBeProvenByCapture()
        cancellationIsTerminal()
        print("OrbitMiniAudioHandoffStateMachineTests: PASS")
    }

    private static func delayedApplicationActivationStartsExactlyOneProbe() {
        var machine = OrbitMiniAudioHandoffStateMachine()
        machine.handle(.requested(appIsActive: false, interruptionActive: false))
        expect(machine.phase == .waitingForForeground, "inactive Siri launch must wait")
        expect(machine.beginProbe() == nil, "inactive lifecycle must never start ADM")

        // Elapsed wall time is owned by the async coordinator; the pure state
        // sees only the eventual UIKit signal, whether it took ms or seconds.
        machine.handle(.appBecameActive)
        expect(machine.beginProbe() == 1, "actual activation should open one probe")
        expect(machine.beginProbe() == nil, "activation cannot duplicate a probe")
        machine.handle(.probeSucceeded)
        expect(machine.phase == .readyForSession, "PCM proof should continue once active")
    }

    private static func lifecycleTimeoutStartsZeroProbes() {
        var machine = OrbitMiniAudioHandoffStateMachine()
        machine.handle(.requested(appIsActive: false, interruptionActive: false))
        machine.handle(.lifecycleWaitExpired)
        expect(machine.phase == .lifecycleTimedOut, "inactive deadline must have a distinct terminal state")
        expect(machine.probeAttempts == 0, "lifecycle timeout must consume zero ADM attempts")
        expect(machine.beginProbe() == nil, "lifecycle timeout cannot open ADM")
    }

    private static func delayedActivationIsNotADeadlineFailure() {
        var machine = OrbitMiniAudioHandoffStateMachine()
        machine.handle(.requested(appIsActive: false, interruptionActive: false))
        machine.handle(.audioReadinessChanged)
        machine.handle(.boundedWaitExpired)
        expect(machine.phase == .waitingForForeground, "audio events/timeouts cannot forge lifecycle activation")
        expect(machine.probeAttempts == 0, "waiting several seconds must not burn retries")
        machine.handle(.appBecameActive)
        expect(machine.beginProbe() == 1, "late real activation remains usable")
    }

    private static func lifecycleSignalWinsTimeoutRace() {
        var machine = OrbitMiniAudioHandoffStateMachine()
        machine.handle(.requested(appIsActive: false, interruptionActive: false))
        machine.handle(.appBecameActive)
        machine.handle(.lifecycleWaitExpired)
        expect(machine.phase == .readyToProbe, "late timeout cannot override an activation signal")
        expect(machine.beginProbe() == 1, "signal/timeout race may open only one probe")
    }

    private static func lifecycleTimeoutWinsSignalRace() {
        var machine = OrbitMiniAudioHandoffStateMachine()
        machine.handle(.requested(appIsActive: false, interruptionActive: false))
        machine.handle(.lifecycleWaitExpired)
        machine.handle(.appBecameActive)
        expect(machine.phase == .lifecycleTimedOut, "activation after terminal deadline must not revive start")
        expect(machine.probeAttempts == 0, "timeout/signal race cannot start ADM")
    }

    private static func cancellationWhileWaitingForActiveIsTerminal() {
        var machine = OrbitMiniAudioHandoffStateMachine()
        machine.handle(.requested(appIsActive: false, interruptionActive: false))
        machine.handle(.cancel)
        machine.handle(.appBecameActive)
        expect(machine.phase == .cancelled, "late lifecycle signal cannot revive cancellation")
        expect(machine.beginProbe() == nil, "cancelled lifecycle wait cannot start ADM")
    }

    private static func validPreviousAppReturnPreservesCapturedSession() {
        var machine = OrbitMiniAudioHandoffStateMachine()
        machine.handle(.requested(appIsActive: true, interruptionActive: false))
        expect(machine.beginProbe() == 1, "valid return path starts capture while Mini is active")
        // The enclosing Shortcut opens the previous app after Mini's intent
        // returns. Once a probe already owns capture, foreground resignation
        // must not invalidate the proven background continuation path.
        machine.handle(.appBecameInactive)
        machine.handle(.probeSucceeded)
        expect(machine.phase == .readyForSession, "valid previous-app return must preserve captured audio")
    }

    private static func invalidPreviousAppReturnCannotAbortMiniStartup() {
        var machine = OrbitMiniAudioHandoffStateMachine()
        machine.handle(.requested(appIsActive: false, interruptionActive: false))
        // A failed downstream Open App action has no callback into Mini and
        // therefore cannot be a fatal state-machine event. Mini keeps waiting
        // for UIKit's eventual real activation.
        expect(machine.phase == .waitingForForeground, "external Open App failure must not abort pending start")
        machine.handle(.appBecameActive)
        expect(machine.beginProbe() == 1, "eventual activation should recover after downstream Shortcut failure")
        machine.handle(.probeSucceeded)
        expect(machine.phase == .readyForSession, "invalid/nil previous app must not poison voice startup")
    }

    private static func immediateTypedSiriPath() {
        var machine = OrbitMiniAudioHandoffStateMachine()
        machine.handle(.requested(appIsActive: true, interruptionActive: false))
        expect(machine.beginProbe() == 1, "typed Siri should probe immediately")
        machine.handle(.probeSucceeded)
        expect(machine.phase == .readyForSession, "typed Siri should proceed after capture proof")
    }

    private static func observedVoiceSiriInterruptionPath() {
        var machine = OrbitMiniAudioHandoffStateMachine()
        machine.handle(.requested(appIsActive: true, interruptionActive: true))
        expect(machine.phase == .waitingForAudioRelease, "active interruption must block probe")
        expect(machine.beginProbe() == nil, "interrupted path cannot claim probe")
        machine.handle(.interruptionEnded)
        expect(machine.beginProbe() == 1, "interruption end should open exactly one probe")
        machine.handle(.probeSucceeded)
        expect(machine.phase == .readyForSession, "released microphone should start session")
    }

    private static func inactiveLifecyclePrecedesAudioInterruptionWait() {
        var machine = OrbitMiniAudioHandoffStateMachine()
        machine.handle(.requested(appIsActive: false, interruptionActive: true))
        expect(machine.phase == .waitingForForeground, "inactive lifecycle must be resolved before audio ownership")
        machine.handle(.appBecameActive)
        expect(machine.phase == .waitingForAudioRelease, "active app must still respect an observed interruption")
        expect(machine.beginProbe() == nil, "interruption cannot be bypassed after lifecycle activation")
    }

    private static func missedInterruptionUsesBoundedProbeRecovery() {
        var machine = OrbitMiniAudioHandoffStateMachine()
        machine.handle(.requested(appIsActive: true, interruptionActive: false))
        expect(machine.beginProbe() == 1, "missed begin notification allows an authoritative probe")
        machine.handle(.probeFailed(transient: true))
        expect(machine.phase == .waitingForRetry(attempt: 1), "transient ADM failure waits")
        machine.handle(.audioReadinessChanged)
        expect(machine.beginProbe() == 2, "route/readiness signal opens the retry")
        machine.handle(.probeSucceeded)
        expect(machine.phase == .readyForSession, "successful retry should continue")
    }

    private static func postActivationADMFailureUsesBoundedRetry() {
        var machine = OrbitMiniAudioHandoffStateMachine(maximumProbeAttempts: 2)
        machine.handle(.requested(appIsActive: false, interruptionActive: false))
        machine.handle(.appBecameActive)
        expect(machine.beginProbe() == 1, "first ADM attempt must happen after activation")
        machine.handle(.probeFailed(transient: true)) // e.g. LiveKit ADM -3001
        expect(machine.phase == .waitingForRetry(attempt: 1), "post-active -3001 remains retryable")
        machine.handle(.boundedWaitExpired)
        expect(machine.beginProbe() == 2, "bounded audio retry should open a second attempt")
    }

    private static func engineWithoutPCMRemainsAnAudioRetry() {
        var machine = OrbitMiniAudioHandoffStateMachine(maximumProbeAttempts: 2)
        machine.handle(.requested(appIsActive: true, interruptionActive: false))
        expect(machine.beginProbe() == 1, "active path should claim probe")
        machine.handle(.probeFailed(transient: true)) // engineRunning=true, pcmFrame=false
        expect(machine.phase == .waitingForRetry(attempt: 1), "missing PCM is distinct from lifecycle waiting")
        expect(machine.appIsActive, "missing PCM must not erase proven lifecycle state")
    }

    private static func transientAttemptsAreBounded() {
        var machine = OrbitMiniAudioHandoffStateMachine(maximumProbeAttempts: 3)
        machine.handle(.requested(appIsActive: true, interruptionActive: false))
        for expectedAttempt in 1 ... 3 {
            expect(machine.beginProbe() == expectedAttempt, "unexpected probe number")
            machine.handle(.probeFailed(transient: true))
            if expectedAttempt < 3 {
                machine.handle(.boundedWaitExpired)
            }
        }
        expect(machine.phase == .failed, "retry exhaustion must be terminal")
        expect(machine.beginProbe() == nil, "failed state cannot probe again")
    }

    private static func permanentFailureDoesNotRetry() {
        var machine = OrbitMiniAudioHandoffStateMachine()
        machine.handle(.requested(appIsActive: true, interruptionActive: false))
        _ = machine.beginProbe()
        machine.handle(.probeFailed(transient: false))
        expect(machine.phase == .failed, "permanent failure must not retry")
    }

    private static func probeClaimIsIdempotent() {
        var machine = OrbitMiniAudioHandoffStateMachine()
        machine.handle(.requested(appIsActive: true, interruptionActive: false))
        expect(machine.beginProbe() == 1, "first probe claim should succeed")
        expect(machine.beginProbe() == nil, "second concurrent probe claim must fail")
    }

    private static func interruptionDuringProbeMustReleaseBeforeSession() {
        var machine = OrbitMiniAudioHandoffStateMachine()
        machine.handle(.requested(appIsActive: true, interruptionActive: false))
        _ = machine.beginProbe()
        machine.handle(.interruptionBegan)
        machine.handle(.probeSucceeded)
        expect(machine.phase == .waitingForAudioRelease, "capture cannot commit during interruption")
        machine.handle(.interruptionEnded)
        expect(machine.beginProbe() == 2, "release requires a fresh authoritative probe")
    }

    private static func completeInterruptionDuringProbeDoesNotDuplicateProbe() {
        var machine = OrbitMiniAudioHandoffStateMachine()
        machine.handle(.requested(appIsActive: true, interruptionActive: false))
        _ = machine.beginProbe()
        machine.handle(.interruptionBegan)
        machine.handle(.interruptionEnded)
        expect(machine.phase == .probing(attempt: 1), "notifications must not steal an in-flight probe")
        machine.handle(.probeSucceeded)
        expect(machine.phase == .readyForSession, "released successful probe should commit")
        expect(machine.beginProbe() == nil, "committed handoff must not start a duplicate probe")
    }

    private static func missedInterruptionEndCanBeProvenByCapture() {
        var machine = OrbitMiniAudioHandoffStateMachine()
        machine.handle(.requested(appIsActive: true, interruptionActive: true))
        machine.handle(.boundedWaitExpired)
        expect(machine.beginProbe() == 1, "bounded fallback should open an authoritative probe")
        machine.handle(.probeSucceeded)
        expect(machine.phase == .readyForSession, "PCM proof must recover a missed end notification")
    }

    private static func cancellationIsTerminal() {
        var machine = OrbitMiniAudioHandoffStateMachine()
        machine.handle(.requested(appIsActive: true, interruptionActive: false))
        _ = machine.beginProbe()
        machine.handle(.cancel)
        expect(machine.phase == .cancelled, "cancel must terminate an in-flight handoff")
        expect(machine.beginProbe() == nil, "cancelled handoff cannot create another engine")
        machine.handle(.probeSucceeded)
        expect(machine.phase == .cancelled, "late probe completion cannot revive cancellation")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
