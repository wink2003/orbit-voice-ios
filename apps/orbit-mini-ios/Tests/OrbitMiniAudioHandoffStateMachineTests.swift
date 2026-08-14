import Foundation

@main
enum OrbitMiniAudioHandoffStateMachineTests {
    static func main() {
        immediateTypedSiriPath()
        observedVoiceSiriInterruptionPath()
        missedInterruptionUsesBoundedProbeRecovery()
        transientAttemptsAreBounded()
        permanentFailureDoesNotRetry()
        probeClaimIsIdempotent()
        interruptionDuringProbeMustReleaseBeforeSession()
        completeInterruptionDuringProbeDoesNotDuplicateProbe()
        missedInterruptionEndCanBeProvenByCapture()
        cancellationIsTerminal()
        print("OrbitMiniAudioHandoffStateMachineTests: PASS")
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
