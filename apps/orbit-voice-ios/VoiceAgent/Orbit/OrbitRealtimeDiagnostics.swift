import AVFoundation
import Foundation
import LiveKit
import Network

// Compact diagnostics for the explicit Wi-Fi/cellular comparison only. No
// PCM, transcript, room name, participant identity, or ICE address is read.
final class OrbitRealtimeDiagnostics: NSObject, @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "net.opik.orbit.realtime-path")
    private let lock = NSLock()
    private var network = "unknown"
    private var reconnectCount = 0
    private var interruptionCount = 0
    private var lastSampleAt: [String: TimeInterval] = [:]
    private var directions: [ObjectIdentifier: String] = [:]
    private var attachedTracks = Set<ObjectIdentifier>()
    private var interruptionObserver: NSObjectProtocol?

    override init() {
        super.init()
        monitor.pathUpdateHandler = { [weak self] path in
            self?.lock.lock()
            self?.network = path.usesInterfaceType(.wifi) ? "wifi" : path.usesInterfaceType(.cellular) ? "cellular" : "other"
            self?.lock.unlock()
        }
        monitor.start(queue: monitorQueue)
        interruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(), queue: nil) { [weak self] _ in self?.recordInterruption() }
    }

    deinit {
        monitor.cancel()
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
    }

    private func snapshot() -> (String, Int, Int) { lock.lock(); defer { lock.unlock() }; return (network, reconnectCount, interruptionCount) }
    private func audioRoute() -> String {
        switch AVAudioSession.sharedInstance().currentRoute.outputs.first?.portType {
        case .builtInSpeaker: return "speaker"
        case .builtInReceiver: return "receiver"
        case .headphones, .headsetMic: return "headphones"
        case .bluetoothA2DP, .bluetoothHFP: return "bluetooth"
        case .none: return "unknown"
        default: return "other"
        }
    }
    private func recordInterruption() {
        lock.lock(); interruptionCount += 1; let values = (network, reconnectCount, interruptionCount); lock.unlock()
        emit(["event": "interruption", "network": values.0, "reconnectCount": values.1, "interruptionCount": values.2, "audioRoute": audioRoute()])
    }
    private func emit(_ payload: [String: Any]) {
        guard let token = KeychainStore.readDeviceToken(), let data = try? JSONSerialization.data(withJSONObject: payload), let url = URL(string: "https://voice.orbit.opik.net/api/realtime/diagnostics") else { return }
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.timeoutInterval = 3
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = data
        Task { _ = try? await URLSession.shared.data(for: request) }
    }
    private func attach(_ track: Track, direction: String) {
        let identifier = ObjectIdentifier(track)
        lock.lock(); let isNew = attachedTracks.insert(identifier).inserted; directions[identifier] = direction; lock.unlock()
        guard isNew else { return }
        track.add(delegate: self)
        Task { await track.set(reportStatistics: true) }
    }
    private func shouldEmit(direction: String) -> Bool {
        lock.lock(); defer { lock.unlock() }; let now = Date().timeIntervalSince1970
        guard now - (lastSampleAt[direction] ?? 0) >= 5 else { return false }; lastSampleAt[direction] = now; return true
    }
}

extension OrbitRealtimeDiagnostics: RoomDelegate {
    func room(_: Room, didUpdateConnectionState state: ConnectionState, from _: ConnectionState) {
        lock.lock(); if state == .reconnecting { reconnectCount += 1 }; let values = (network, reconnectCount, interruptionCount); lock.unlock()
        emit(["event": "connection", "network": values.0, "state": String(describing: state), "reconnectCount": values.1, "interruptionCount": values.2, "audioRoute": audioRoute()])
    }
    func room(_: Room, participant _: LocalParticipant, didPublishTrack publication: LocalTrackPublication) { if let track = publication.track as? LocalAudioTrack { attach(track, direction: "uplink") } }
    func room(_: Room, participant _: RemoteParticipant, didSubscribeTrack publication: RemoteTrackPublication) { if let track = publication.track as? RemoteAudioTrack { attach(track, direction: "downlink") } }
    func room(_: Room, participant _: Participant, didUpdateConnectionQuality quality: ConnectionQuality) {
        let values = snapshot()
        emit(["event": "quality", "network": values.0, "quality": String(describing: quality), "reconnectCount": values.1, "interruptionCount": values.2, "audioRoute": audioRoute()])
    }
}

extension OrbitRealtimeDiagnostics: TrackDelegate {
    func track(_ track: Track, didUpdateStatistics statistics: TrackStatistics, simulcastStatistics _: [VideoCodec: TrackStatistics]) {
        let identifier = ObjectIdentifier(track); lock.lock(); let direction = directions[identifier]; lock.unlock()
        guard let direction, shouldEmit(direction: direction) else { return }
        let values = snapshot(); let local = statistics.localIceCandidate; let remote = statistics.remoteIceCandidate
        let pair = statistics.iceCandidatePair.first(where: { $0.nominated == true }) ?? statistics.iceCandidatePair.first
        var payload: [String: Any] = ["event": "audio_stats", "network": values.0, "direction": direction, "localCandidateType": local?.candidateType.map { String(describing: $0) } ?? "", "remoteCandidateType": remote?.candidateType.map { String(describing: $0) } ?? "", "transportProtocol": local?.protocol ?? remote?.protocol ?? "", "rttMs": (pair?.currentRoundTripTime ?? 0) * 1000, "reconnectCount": values.1, "interruptionCount": values.2, "audioRoute": audioRoute()]
        if direction == "uplink", let sent = statistics.outboundRtpStream.first {
            let remoteInbound = statistics.remoteInboundRtpStream.first
            payload["packets"] = sent.packetsSent ?? 0; payload["bitrateBps"] = sent.bps; payload["packetsLost"] = remoteInbound?.packetsLost ?? 0; payload["lossFraction"] = remoteInbound?.fractionLost ?? 0; payload["jitterMs"] = (remoteInbound?.jitter ?? 0) * 1000; payload["rttMs"] = (remoteInbound?.roundTripTime ?? pair?.currentRoundTripTime ?? 0) * 1000
        } else if let received = statistics.inboundRtpStream.first {
            let remoteOutbound = statistics.remoteOutboundRtpStream.first
            payload["packets"] = received.packetsReceived ?? 0; payload["bitrateBps"] = received.bps; payload["packetsLost"] = received.packetsLost ?? 0; payload["jitterMs"] = (received.jitter ?? 0) * 1000; payload["concealedSamples"] = received.concealedSamples ?? 0; payload["concealmentEvents"] = received.concealmentEvents ?? 0; payload["rttMs"] = (remoteOutbound?.roundTripTime ?? pair?.currentRoundTripTime ?? 0) * 1000
        }
        emit(payload)
    }
}
