import Foundation
import LiveKit

/// A deliberately thin owner around the already-proven full Orbit `Session`.
/// Mini does not implement STT, VAD, TTS, or a second transport: LiveKit's
/// existing Orbit agent owns all of those behaviours.
@MainActor
final class OrbitMiniVoiceCoordinator: NSObject, ObservableObject {
    static let shared = OrbitMiniVoiceCoordinator()

    @Published private(set) var isStarting = false
    @Published private(set) var lastError: String?

    private let runtime = OrbitRuntime.shared
    private let liveActivity = OrbitMiniLiveActivityManager.shared
    private var ending = false

    private override init() {
        super.init()
        runtime.session.room.add(delegate: self)
    }

    var session: Session { runtime.session }

    func start() async {
        guard runtime.authentication.isPaired else {
            lastError = "Спершу активуйте цей iPhone."
            return
        }
        guard !runtime.session.isConnected, !isStarting else { return }
        isStarting = true
        lastError = nil
        await liveActivity.reconcileOrphans()
        await runtime.session.start()
        isStarting = false
        if runtime.session.isConnected {
            await liveActivity.begin(userName: runtime.authentication.displayName ?? "Orbit")
        } else {
            lastError = runtime.session.error?.localizedDescription ?? "Не вдалося підключити Orbit."
        }
    }

    func updateAgentState(_ description: String) async {
        guard runtime.session.isConnected else { return }
        let normalized = description.lowercased()
        let state: OrbitMiniVoiceState
        if normalized.contains("speak") { state = .speaking }
        else if normalized.contains("think") { state = .thinking }
        else { state = .listening }
        await liveActivity.transition(to: state, userName: runtime.authentication.displayName ?? "Orbit")
    }

    func stop(reason: String = "user") async {
        guard !ending else { return }
        ending = true
        await runtime.session.end()
        runtime.session.restoreMessageHistory([])
        await liveActivity.end()
        ending = false
    }

    func cleanOrphansAtLaunch() async {
        guard !runtime.session.isConnected else { return }
        await liveActivity.reconcileOrphans()
    }
}

extension OrbitMiniVoiceCoordinator: RoomDelegate {
    nonisolated func room(_ room: Room, didUpdateConnectionState connectionState: ConnectionState, from oldConnectionState: ConnectionState) {
        guard connectionState == .disconnected, oldConnectionState != .disconnected else { return }
        Task { @MainActor [weak self] in
            await self?.stop(reason: "transport-disconnected")
        }
    }
}
