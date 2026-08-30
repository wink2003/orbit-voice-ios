import Combine
import Foundation

struct ServerOverview: Decodable {
    struct Server: Decodable { let hostname: String; let os: String; let architecture: String; let uptimeSeconds: Double }
    struct Containers: Decodable { let total: Int; let running: Int; let stopped: Int; let unhealthy: Int; let composeProjects: Int }
    struct Disk: Decodable { let mount: String; let totalBytes: Double; let usedBytes: Double; let availableBytes: Double; let usedPercent: Double }
    struct CPU: Decodable { struct Load: Decodable { let one: Double; let five: Double; let fifteen: Double }; let model: String?; let logicalCpus: Int; let utilizationPercent: Double?; let loadAverage: Load }
    struct Memory: Decodable { let totalBytes: Double; let usedBytes: Double; let availableBytes: Double; let usedPercent: Double; let swapTotalBytes: Double; let swapUsedBytes: Double }
    let generatedAt: Date; let server: Server; let containers: Containers; let disks: [Disk]; let cpu: CPU; let memory: Memory
}

@MainActor final class ServerOverviewStore: ObservableObject {
    @Published private(set) var overview: ServerOverview?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    private var lastLoaded: Date?
    private var task: Task<Void, Never>?
    func loadIfNeeded(force: Bool = false) {
        guard !isLoading, force || lastLoaded.map({ Date().timeIntervalSince($0) > 45 }) ?? true else { return }
        isLoading = true; error = nil
        task = Task { defer { isLoading = false }; await request() }
    }
    private func request() async {
        guard let token = KeychainStore.readDeviceToken(), let url = URL(string: "https://voice.orbit.opik.net/api/server/overview") else { error = "Не вдалося підключитися до Orbit."; return }
        var request = URLRequest(url: url); request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do { let (data, response) = try await URLSession.shared.data(for: request); guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }; let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; overview = try decoder.decode(ServerOverview.self, from: data); lastLoaded = Date() } catch { self.error = "Не вдалося оновити огляд сервера." }
    }
}
