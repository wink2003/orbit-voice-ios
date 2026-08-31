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

enum ServerOverviewDetailSection: String, Identifiable {
    case host, docker, disk, cpu, memory
    var id: String { rawValue }
    var title: String { switch self { case .host: "Сервер"; case .docker: "Docker"; case .disk: "Диск"; case .cpu: "CPU"; case .memory: "Оперативна памʼять" } }
    var icon: String { switch self { case .host: "server.rack"; case .docker: "shippingbox.fill"; case .disk: "internaldrive.fill"; case .cpu: "cpu"; case .memory: "memorychip.fill" } }
}

struct ServerOverviewDetail: Decodable {
    struct Load: Decodable { let one: Double; let five: Double; let fifteen: Double }
    struct Host: Decodable { let hostname: String; let os: String; let kernel: String?; let architecture: String; let uptimeSeconds: Double }
    struct Frequency: Decodable { let available: Bool; let currentMhz: Double?; let maxMhz: Double? }
    struct CPU: Decodable { let model: String?; let architecture: String?; let logicalCpus: Int; let utilizationPercent: Double?; let loadAverage: Load; let frequency: Frequency }
    struct Disk: Decodable { let mount: String; let filesystem: String?; let totalBytes: Double; let usedBytes: Double; let availableBytes: Double; let usedPercent: Double }
    struct Memory: Decodable { let totalBytes: Double; let usedBytes: Double; let availableBytes: Double; let usedPercent: Double; let swapTotalBytes: Double; let swapFreeBytes: Double; let swapUsedBytes: Double }
    struct Port: Decodable { let container: String?; let host: String?; let hostIp: String? }
    struct Mount: Decodable { let name: String?; let type: String?; let destination: String? }
    struct Container: Decodable, Identifiable { let id: String; let name: String; let status: String; let health: String?; let project: String?; let image: String?; let imageId: String?; let imageDisplayName: String?; let imageSizeBytes: Double?; let imageSizeMetric: String?; let imageShared: Bool?; let service: String?; let startedAt: String?; let restartPolicy: String?; let cpuPercent: Double?; let memoryUsedBytes: Double?; let memoryHostPercent: Double?; let memoryMetric: String?; let memoryLimitBytes: Double?; let writableLayerBytes: Double?; let diskMetric: String?; let ports: [Port]; let networks: [String]; let mounts: [Mount] }
    struct DockerStorageSemantics: Decodable { let writableLayer: String; let namedVolumes: String; let bindMounts: String; let images: String }
    struct DockerStorage: Decodable { let writableLayerTotalBytes: Double; let containers: [Container]; let semantics: DockerStorageSemantics }
    struct StorageItem: Decodable, Identifiable { let id: String; let domain: String; let type: String; let label: String; let bytes: Double?; let reclaimableBytes: Double?; let attribution: String; let reclaimability: String; let measurement: String; let additive: Bool; let rollup: Bool?; let mountType: String?; let metric: String?; let note: String?; let pathLabel: String? }
    struct StorageService: Decodable, Identifiable { let service: String; let items: [StorageItem]; var id: String { service } }
    struct Storage: Decodable { let measuredAt: Double; let collectionMs: Double?; let refreshIntervalSeconds: Double?; let stale: Bool; let global: [StorageItem]; let services: [StorageService] }
    let generatedAt: Date; let collectionMs: Double?; let server: Host?; let cpu: CPU?; let memory: Memory?; let disks: [Disk]?; let containers: [Container]?; let dockerStorage: DockerStorage?; let storage: Storage?
}

@MainActor final class ServerOverviewDetailStore: ObservableObject {
    let section: ServerOverviewDetailSection
    @Published private(set) var detail: ServerOverviewDetail?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    private var task: Task<Void, Never>?
    init(section: ServerOverviewDetailSection) { self.section = section }
    func load(force: Bool = false) {
        guard !isLoading, force || detail == nil else { return }
        isLoading = true; error = nil
        task = Task { defer { isLoading = false }; await request() }
    }
    private func request() async {
        guard let token = KeychainStore.readDeviceToken(), let url = URL(string: "https://voice.orbit.opik.net/api/server/overview/\(section.rawValue)") else { error = "Не вдалося підключитися до Orbit."; return }
        var request = URLRequest(url: url); request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do { let (data, response) = try await URLSession.shared.data(for: request); guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }; let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; detail = try decoder.decode(ServerOverviewDetail.self, from: data) } catch { self.error = "Не вдалося завантажити деталі." }
    }
}

struct CacheCleanupProposal: Decodable, Identifiable {
    let actionId: String
    let status: String
    let operation: String
    let expiresAt: Date
    let cacheBytes: Double?
    let reclaimableBytes: Double
    var id: String { actionId }
}

struct CacheCleanupResult: Decodable {
    let actionId: String
    let status: String
    let before: State?
    let after: State?
    let cacheFreedBytes: Double?
    let rootFreedBytes: Double?
    let containersHealthy: Bool?
    let error: String?
    struct State: Decodable { let cacheBytes: Double?; let reclaimableBytes: Double?; let rootUsedBytes: Double?; let rootAvailableBytes: Double?; let runningContainers: Int? }
}

@MainActor final class CacheCleanupStore: ObservableObject {
    @Published private(set) var proposal: CacheCleanupProposal?
    @Published private(set) var result: CacheCleanupResult?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    func propose() async {
        guard !isLoading else { return }
        isLoading = true; error = nil; result = nil
        defer { isLoading = false }
        do { proposal = try await request(path: "cache-cleanup/proposals", method: "POST", decode: CacheCleanupProposal.self) }
        catch { self.error = "Не вдалося підготувати очищення кешу." }
    }
    func confirm() async {
        guard let proposal, !isLoading else { return }
        isLoading = true; error = nil
        defer { isLoading = false }
        do { result = try await request(path: "cache-cleanup/proposals/\(proposal.actionId)/confirm", method: "POST", decode: CacheCleanupResult.self) }
        catch { self.error = "Не вдалося очистити кеш." }
    }
    func cancel() async {
        guard let proposal else { return }
        _ = try? await request(path: "cache-cleanup/proposals/\(proposal.actionId)/cancel", method: "POST", decode: CancelResponse.self)
        self.proposal = nil
    }
    func clearProposal() { proposal = nil }
    private struct CancelResponse: Decodable { let actionId: String; let status: String }
    private func request<T: Decodable>(path: String, method: String, decode: T.Type) async throws -> T {
        guard let token = KeychainStore.readDeviceToken(), let url = URL(string: "https://voice.orbit.opik.net/api/server/overview/\(path)") else { throw URLError(.badURL) }
        var request = URLRequest(url: url); request.httpMethod = method; request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else { throw URLError(.badServerResponse) }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }
}
