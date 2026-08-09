#if os(iOS)
import AVFoundation
import CallKit
import LiveKit

@MainActor
final class OrbitCallManager: NSObject {
    private let session: Session
    private let callController = CXCallController()
    private let provider: CXProvider

    private var activeCallUUID: UUID?
    private var connectionTask: Task<Void, Never>?
    private var isEndingLocally = false

    init(session: Session) {
        self.session = session

        let configuration = CXProviderConfiguration()
        configuration.supportedHandleTypes = [.generic]
        configuration.maximumCallsPerCallGroup = 1
        configuration.maximumCallGroups = 1
        configuration.supportsVideo = false
        provider = CXProvider(configuration: configuration)

        super.init()

        provider.setDelegate(self, queue: .main)
        session.room.add(delegate: self)

        AudioManager.shared.audioSession.isAutomaticConfigurationEnabled = false
        try? AudioManager.shared.setEngineAvailability(.none)
    }

    func startCall() async throws {
        guard KeychainStore.readDeviceToken() != nil else {
            throw OrbitCallError.notPaired
        }
        guard activeCallUUID == nil else { return }

        let callUUID = UUID()
        activeCallUUID = callUUID
        isEndingLocally = false

        let handle = CXHandle(type: .generic, value: "Orbit")
        let action = CXStartCallAction(call: callUUID, handle: handle)
        action.isVideo = false

        do {
            try await callController.request(CXTransaction(action: action))
        } catch {
            activeCallUUID = nil
            throw error
        }
    }

    func endCall() async {
        guard let callUUID = activeCallUUID else {
            await session.end()
            session.restoreMessageHistory([])
            return
        }

        isEndingLocally = true
        do {
            try await callController.request(CXTransaction(action: CXEndCallAction(call: callUUID)))
        } catch {
            isEndingLocally = false
            await session.end()
            session.restoreMessageHistory([])
            provider.reportCall(with: callUUID, endedAt: Date(), reason: .failed)
            activeCallUUID = nil
        }
    }

    private func connect(callUUID: UUID) async {
        await session.start()

        guard activeCallUUID == callUUID else { return }
        guard session.isConnected else {
            provider.reportCall(with: callUUID, endedAt: Date(), reason: .failed)
            activeCallUUID = nil
            return
        }

        provider.reportOutgoingCall(with: callUUID, connectedAt: Date())
    }

    private func finishRemoteCallIfNeeded() {
        guard !isEndingLocally, let callUUID = activeCallUUID else { return }
        connectionTask?.cancel()
        connectionTask = nil
        provider.reportCall(with: callUUID, endedAt: Date(), reason: .remoteEnded)
        activeCallUUID = nil
        session.restoreMessageHistory([])
    }
}

extension OrbitCallManager: @preconcurrency CXProviderDelegate {
    nonisolated func providerDidReset(_: CXProvider) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            connectionTask?.cancel()
            connectionTask = nil
            activeCallUUID = nil
            isEndingLocally = false
            await session.end()
            session.restoreMessageHistory([])
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        Task { @MainActor [weak self] in
            guard let self else {
                action.fail()
                return
            }

            provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: Date())

            // Fulfilling the CallKit action activates AVAudioSession. LiveKit's
            // engine remains disabled until provider(_:didActivate:) below.
            action.fulfill()

            connectionTask?.cancel()
            connectionTask = Task { @MainActor [weak self] in
                await self?.connect(callUUID: action.callUUID)
            }
        }
    }

    nonisolated func provider(_: CXProvider, perform action: CXEndCallAction) {
        Task { @MainActor [weak self] in
            guard let self else {
                action.fulfill()
                return
            }

            connectionTask?.cancel()
            connectionTask = nil
            await session.end()
            session.restoreMessageHistory([])
            activeCallUUID = nil
            isEndingLocally = false
            action.fulfill()
        }
    }

    nonisolated func provider(_: CXProvider, perform action: CXSetMutedCallAction) {
        Task { @MainActor [weak self] in
            guard let self else {
                action.fail()
                return
            }

            do {
                try await session.room.localParticipant.setMicrophone(enabled: !action.isMuted)
                action.fulfill()
            } catch {
                action.fail()
            }
        }
    }

    nonisolated func provider(_: CXProvider, didActivate audioSession: AVAudioSession) {
        do {
            try audioSession.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.defaultToSpeaker, .allowBluetoothHFP]
            )
            try AudioManager.shared.setEngineAvailability(.default)
        } catch {
            // A failed audio activation is surfaced by the LiveKit session.
        }
    }

    nonisolated func provider(_: CXProvider, didDeactivate _: AVAudioSession) {
        try? AudioManager.shared.setEngineAvailability(.none)
    }
}

extension OrbitCallManager: @preconcurrency RoomDelegate {
    nonisolated func room(
        _: Room,
        didUpdateConnectionState connectionState: ConnectionState,
        from oldConnectionState: ConnectionState
    ) {
        guard connectionState == .disconnected, oldConnectionState != .disconnected else { return }
        Task { @MainActor [weak self] in
            self?.finishRemoteCallIfNeeded()
        }
    }
}

private enum OrbitCallError: LocalizedError {
    case notPaired

    var errorDescription: String? {
        switch self {
        case .notPaired:
            "Open Orbit once and pair this iPhone first."
        }
    }
}
#else
import LiveKit

@MainActor
final class OrbitCallManager {
    private let session: Session

    init(session: Session) {
        self.session = session
    }

    func startCall() async throws {
        await session.start()
    }

    func endCall() async {
        await session.end()
        session.restoreMessageHistory([])
    }
}
#endif
