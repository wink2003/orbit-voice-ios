#if os(iOS) && ORBIT_CALLKIT_ONLY
import AVFoundation
import CallKit
import Combine
import Foundation
import LiveKit

enum OrbitNativeCallState: Equatable {
    case idle
    case starting
    case connected
    case ending
    case failed(String)
}

/// Native CallKit client used only by the dedicated Orbit CallKit build.
///
/// This deliberately owns a plain LiveKit `Room`. The higher-level agent
/// `Session` starts pre-connect microphone capture, which races CallKit's
/// audio-session activation and must not be used for a system call.
@MainActor
final class OrbitNativeCallManager: NSObject, ObservableObject {
    static let shared = OrbitNativeCallManager()

    @Published private(set) var state: OrbitNativeCallState = .idle

    let room = Room()

    private let callController = CXCallController()
    private let provider: CXProvider
    private var activeCallUUID: UUID?
    private var connectionTask: Task<Void, Never>?
    private var isEndingLocally = false

    private override init() {
        let configuration = CXProviderConfiguration(localizedName: "Orbit")
        configuration.supportedHandleTypes = [.generic]
        configuration.maximumCallsPerCallGroup = 1
        configuration.maximumCallGroups = 1
        configuration.supportsVideo = false
        configuration.includesCallsInRecents = false
        provider = CXProvider(configuration: configuration)

        super.init()

        provider.setDelegate(self, queue: .main)
        room.add(delegate: self)

        AudioManager.shared.audioSession.isAutomaticConfigurationEnabled = false
        try? AudioManager.shared.setEngineAvailability(.none)
    }

    var hasActiveCall: Bool {
        activeCallUUID != nil
    }

    func startCall() async throws {
        guard KeychainStore.readDeviceToken() != nil else {
            throw OrbitNativeCallError.notPaired
        }
        guard activeCallUUID == nil else { return }

        AudioManager.shared.audioSession.isAutomaticConfigurationEnabled = false
        try AudioManager.shared.setEngineAvailability(.none)

        let callUUID = UUID()
        activeCallUUID = callUUID
        isEndingLocally = false
        state = .starting

        let handle = CXHandle(type: .generic, value: "Orbit")
        let action = CXStartCallAction(call: callUUID, handle: handle)
        action.isVideo = false

        do {
            try await callController.request(CXTransaction(action: action))
        } catch {
            activeCallUUID = nil
            state = .failed(error.localizedDescription)
            throw OrbitNativeCallError.callKitUnavailable(error.localizedDescription)
        }
    }

    func endCall() async {
        guard let callUUID = activeCallUUID else {
            await room.disconnect()
            state = .idle
            return
        }

        isEndingLocally = true
        state = .ending

        do {
            try await callController.request(
                CXTransaction(action: CXEndCallAction(call: callUUID))
            )
        } catch {
            await room.disconnect()
            provider.reportCall(with: callUUID, endedAt: Date(), reason: .failed)
            activeCallUUID = nil
            isEndingLocally = false
            state = .failed(error.localizedDescription)
        }
    }

    func dismissError() {
        if case .failed = state {
            state = .idle
        }
    }

    private func connect(action: CXStartCallAction) async {
        do {
            let credentials = try await OrbitTokenSource().fetch(TokenRequestOptions())
            try Task.checkCancellation()

            try await room.connect(
                url: credentials.serverURL.absoluteString,
                token: credentials.participantToken
            )
            try Task.checkCancellation()
            try await room.localParticipant.setMicrophone(enabled: true)
            try Task.checkCancellation()

            guard activeCallUUID == action.callUUID else {
                await room.disconnect()
                action.fail()
                return
            }

            provider.reportOutgoingCall(with: action.callUUID, connectedAt: Date())
            state = .connected
            action.fulfill()
        } catch is CancellationError {
            await room.disconnect()
            action.fail()
        } catch {
            await room.disconnect()
            action.fail()
            provider.reportCall(with: action.callUUID, endedAt: Date(), reason: .failed)
            activeCallUUID = nil
            state = .failed(error.localizedDescription)
        }
    }

    private func finishRemoteCallIfNeeded() {
        guard !isEndingLocally, let callUUID = activeCallUUID else { return }

        connectionTask?.cancel()
        connectionTask = nil
        provider.reportCall(with: callUUID, endedAt: Date(), reason: .remoteEnded)
        activeCallUUID = nil
        state = .idle
    }
}

extension OrbitNativeCallManager: CXProviderDelegate {
    func providerDidReset(_: CXProvider) {
        connectionTask?.cancel()
        connectionTask = nil
        activeCallUUID = nil
        isEndingLocally = false
        state = .idle

        Task { @MainActor [weak self] in
            await self?.room.disconnect()
        }
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        provider.reportOutgoingCall(with: action.callUUID, startedConnectingAt: Date())

        connectionTask?.cancel()
        connectionTask = Task { @MainActor [weak self] in
            guard let self else {
                action.fail()
                return
            }
            await connect(action: action)
        }
    }

    func provider(_: CXProvider, perform action: CXEndCallAction) {
        connectionTask?.cancel()
        connectionTask = nil
        isEndingLocally = true

        Task { @MainActor [weak self] in
            guard let self else {
                action.fulfill()
                return
            }

            await room.disconnect()
            action.fulfill()
            activeCallUUID = nil
            isEndingLocally = false
            state = .idle
        }
    }

    func provider(_: CXProvider, perform action: CXSetMutedCallAction) {
        Task { @MainActor [weak self] in
            guard let self else {
                action.fail()
                return
            }

            do {
                try await room.localParticipant.setMicrophone(enabled: !action.isMuted)
                action.fulfill()
            } catch {
                action.fail()
                state = .failed(error.localizedDescription)
            }
        }
    }

    func provider(_: CXProvider, didActivate audioSession: AVAudioSession) {
        do {
            try audioSession.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.defaultToSpeaker, .allowBluetoothHFP]
            )
            try AudioManager.shared.setEngineAvailability(.default)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func provider(_: CXProvider, didDeactivate _: AVAudioSession) {
        try? AudioManager.shared.setEngineAvailability(.none)
    }
}

extension OrbitNativeCallManager: RoomDelegate {
    nonisolated func room(
        _: Room,
        didUpdateConnectionState connectionState: ConnectionState,
        from oldConnectionState: ConnectionState
    ) {
        guard connectionState == .disconnected, oldConnectionState != .disconnected else {
            return
        }

        Task { @MainActor [weak self] in
            self?.finishRemoteCallIfNeeded()
        }
    }
}

private enum OrbitNativeCallError: LocalizedError {
    case notPaired
    case callKitUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .notPaired:
            "Open Orbit CallKit once and pair this iPhone first."
        case let .callKitUnavailable(details):
            "iPhone did not start the Orbit system call: \(details)"
        }
    }
}
#endif
