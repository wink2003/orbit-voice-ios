import Combine
import Foundation
import LiveKit
import UIKit

struct OrbitTokenSource: EndpointTokenSource {
    let url = URL(string: "https://voice.orbit.opik.net/api/token")!

    var headers: [String: String] {
        guard let token = KeychainStore.readMainBearerToken() else { return [:] }
        return ["Authorization": "Bearer \(token)"]
    }
}

@MainActor
final class OrbitAuthentication: ObservableObject {
    @Published private(set) var isPaired = KeychainStore.readMainBearerToken() != nil
    @Published private(set) var displayName = UserDefaults.standard.string(forKey: "orbit.displayName")
    @Published private(set) var personId: String?
    @Published private(set) var identityResolved = false
    @Published private(set) var principalPersonId: String?
    @Published private(set) var impersonating = false
    @Published private(set) var impersonationTargetName: String?
    var canViewServerOverview: Bool { identityResolved && personId == "oleksandr" }

    struct PairingResponse: Decodable {
        struct Profile: Decodable {
            let displayName: String
            let personId: String
        }
        let deviceToken: String
        let profile: Profile
    }

    struct APIError: Decodable {
        let error: String
    }

    struct SessionProfile: Decodable {
        let display_name: String
        let person_id: String
        let principal_person_id: String?
        let impersonating: Bool?
        let impersonation_expires_at: Int64?
        private enum CodingKeys: String, CodingKey { case display_name, person_id, principal_person_id, impersonating, impersonation_expires_at }
    }
    struct SessionResponse: Decodable { let profile: SessionProfile; let token: String? }
    struct ImpersonationTarget: Decodable, Identifiable { let personId: String; let displayName: String; let isMinor: Bool; var id: String { personId } }
    struct ImpersonationTargetsResponse: Decodable { let targets: [ImpersonationTarget] }

    func pair(code: String) async throws {
        let normalized = code.filter(\.isNumber)
        guard normalized.count == 6 else {
            throw PairingFailure.message("Введіть шестизначний код.")
        }
        var request = URLRequest(url: URL(string: "https://voice.orbit.opik.net/api/devices/pair")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "pairingCode": normalized,
            "deviceName": UIDevice.current.name,
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PairingFailure.message("Сервер не відповів.")
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(APIError.self, from: data).error)
                ?? "Не вдалося активувати цей iPhone."
            throw PairingFailure.message(message)
        }
        let result = try JSONDecoder().decode(PairingResponse.self, from: data)
        try KeychainStore.saveDeviceToken(result.deviceToken)
        UserDefaults.standard.set(result.profile.displayName, forKey: "orbit.displayName")
        displayName = result.profile.displayName
        personId = result.profile.personId
        identityResolved = true
        isPaired = true
    }

    func login(login: String, password: String) async throws {
        var request = URLRequest(url: URL(string: "https://voice.orbit.opik.net/api/auth/login")!)
        request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["login": login, "password": password, "clientKind": "native", "deviceLabel": UIDevice.current.name])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PairingFailure.message("Сервер не відповів.") }
        guard (200..<300).contains(http.statusCode), let result = try? JSONDecoder().decode(SessionResponse.self, from: data), let token = result.token else {
            throw PairingFailure.message((try? JSONDecoder().decode(APIError.self, from: data).error) ?? "Не вдалося увійти в Orbit.")
        }
        try KeychainStore.saveSessionToken(token)
        apply(result.profile)
    }

    func refreshIdentity() async {
        guard isPaired else { identityResolved = true; return }
        if let token = KeychainStore.readSessionToken() {
            if await restoreSession(token: token) { identityResolved = true; return }
            if await refreshSession(token: token) { identityResolved = true; return }
            KeychainStore.removeSessionToken()
            isPaired = KeychainStore.readDeviceToken() != nil
        }
        guard let token = KeychainStore.readDeviceToken(), let url = URL(string: "https://voice.orbit.opik.net/api/me") else { identityResolved = true; return }
        struct Response: Decodable { struct Profile: Decodable { let displayName: String?; let personId: String }; let profile: Profile }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        defer { identityResolved = true }
        guard let (data, response) = try? await URLSession.shared.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200,
              let value = try? JSONDecoder().decode(Response.self, from: data) else { return }
        personId = value.profile.personId; principalPersonId = value.profile.personId
    }

    private func restoreSession(token: String) async -> Bool {
        var request = URLRequest(url: URL(string: "https://voice.orbit.opik.net/api/auth/session")!); request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200, let result = try? JSONDecoder().decode(SessionResponse.self, from: data) else { return false }
        apply(result.profile); return true
    }

    private func refreshSession(token: String) async -> Bool {
        var request = URLRequest(url: URL(string: "https://voice.orbit.opik.net/api/auth/refresh")!); request.httpMethod = "POST"; request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200, let result = try? JSONDecoder().decode(SessionResponse.self, from: data), let next = result.token else { return false }
        try? KeychainStore.saveSessionToken(next); apply(result.profile); return true
    }

    private func apply(_ profile: SessionProfile) {
        displayName = profile.display_name; personId = profile.person_id; principalPersonId = profile.principal_person_id ?? profile.person_id
        impersonating = profile.impersonating ?? false; impersonationTargetName = impersonating ? profile.display_name : nil; identityResolved = true; isPaired = true
        UserDefaults.standard.set(profile.display_name, forKey: "orbit.displayName")
    }

    func logout() async {
        if let token = KeychainStore.readSessionToken() {
            var request = URLRequest(url: URL(string: "https://voice.orbit.opik.net/api/auth/logout")!); request.httpMethod = "POST"; request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            _ = try? await URLSession.shared.data(for: request)
        }
        KeychainStore.removeSessionToken(); isPaired = KeychainStore.readDeviceToken() != nil; await refreshIdentity()
    }

    func impersonationTargets() async throws -> [ImpersonationTarget] {
        guard let token = KeychainStore.readSessionToken() else { return [] }
        var request = URLRequest(url: URL(string: "https://voice.orbit.opik.net/api/auth/impersonation/targets")!); request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request); guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw PairingFailure.message("Тестове перемикання недоступне.") }
        return try JSONDecoder().decode(ImpersonationTargetsResponse.self, from: data).targets
    }

    func beginImpersonation(targetPersonId: String, password: String) async throws { try await postImpersonation(path: "/api/auth/impersonation/start", body: ["targetPersonId": targetPersonId, "password": password, "ttlMs": 900000]); await refreshIdentity() }
    func endImpersonation() async throws { _ = try await postImpersonation(path: "/api/auth/impersonation/end", body: [:]); await refreshIdentity() }

    private func postImpersonation(path: String, body: [String: Any]) async throws -> Data {
        guard let token = KeychainStore.readSessionToken() else { throw PairingFailure.message("Потрібен захищений вхід.") }
        var request = URLRequest(url: URL(string: "https://voice.orbit.opik.net\(path)")!); request.httpMethod = "POST"; request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request); guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw PairingFailure.message("Тестове перемикання відхилено.") }; return data
    }

    func forgetDevice() {
        KeychainStore.removeSessionToken()
        KeychainStore.removeDeviceToken()
        UserDefaults.standard.removeObject(forKey: "orbit.displayName")
        displayName = nil
        personId = nil
        identityResolved = false
        isPaired = false
        principalPersonId = nil; impersonating = false; impersonationTargetName = nil
    }
}

enum PairingFailure: LocalizedError {
    case message(String)

    var errorDescription: String? {
        guard case let .message(message) = self else { return nil }
        return message
    }
}
