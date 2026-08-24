import Combine
import Foundation
import LiveKit
import UIKit

struct OrbitTokenSource: EndpointTokenSource {
    let url = URL(string: "https://voice.orbit.opik.net/api/token")!

    var headers: [String: String] {
        guard let token = KeychainStore.readDeviceToken() else { return [:] }
        return ["Authorization": "Bearer \(token)"]
    }
}

@MainActor
final class OrbitAuthentication: ObservableObject {
    enum FamilyProfilesLoadState: Equatable {
        case idle
        case loading
        case loaded
        case empty
        case unavailable
    }

    @Published private(set) var isPaired = KeychainStore.readDeviceToken() != nil
    @Published private(set) var displayName = UserDefaults.standard.string(forKey: "orbit.displayName")
    @Published private(set) var personId = UserDefaults.standard.string(forKey: "orbit.personId")
    @Published private(set) var familyProfiles: [FamilyProfile] = []
    @Published private(set) var familyProfilesLoadState: FamilyProfilesLoadState = .idle

    struct PairingResponse: Decodable {
        struct Profile: Decodable {
            let displayName: String
            let personId: String?
        }
        let deviceToken: String
        let profile: Profile
    }

    struct FamilyProfile: Decodable, Identifiable, Hashable {
        let personId: String
        let displayName: String
        let isMinor: Bool

        var id: String { personId }
    }

    struct APIError: Decodable {
        let error: String
    }

    var selectedFamilyProfile: FamilyProfile? {
        guard let personId else { return nil }
        return familyProfiles.first(where: { $0.personId == personId })
    }

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
        UserDefaults.standard.set(result.profile.personId, forKey: "orbit.personId")
        displayName = result.profile.displayName
        personId = result.profile.personId
        isPaired = true
        await loadFamilyProfiles()
    }

    func loadFamilyProfiles() async {
        guard let token = KeychainStore.readDeviceToken() else {
            familyProfiles = []
            familyProfilesLoadState = .idle
            return
        }
        familyProfilesLoadState = .loading
        var request = URLRequest(url: URL(string: "https://voice.orbit.opik.net/api/family/profiles")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
                familyProfiles = []
                familyProfilesLoadState = .unavailable
                return
            }
            familyProfiles = try JSONDecoder().decode([FamilyProfile].self, from: data)
            guard !familyProfiles.isEmpty else {
                familyProfilesLoadState = .empty
                return
            }

            let availablePersonIDs = familyProfiles.map(\.personId)
            guard let resolvedPersonID = OrbitFamilyProfileSelectionPolicy.resolvedPersonID(
                persistedPersonID: personId,
                availablePersonIDs: availablePersonIDs
            ), let resolvedProfile = familyProfiles.first(where: { $0.personId == resolvedPersonID }) else {
                familyProfilesLoadState = .empty
                return
            }

            if resolvedPersonID == personId {
                // A persisted ID is authoritative only while it is still a
                // valid profile in the current family response.
                persist(resolvedProfile)
                familyProfilesLoadState = .loaded
                return
            }

            // The API's family-profile order is the existing deterministic
            // family model. Never synthesize an assistant/product profile.
            try await selectProfile(resolvedProfile)
            familyProfilesLoadState = .loaded
        } catch {
            familyProfiles = []
            familyProfilesLoadState = .unavailable
        }
    }

    func selectProfile(_ profile: FamilyProfile) async throws {
        guard let token = KeychainStore.readDeviceToken() else { throw PairingFailure.message("Спершу активуйте цей iPhone.") }
        guard familyProfiles.contains(profile) else { throw PairingFailure.message("Виберіть профіль із цього списку.") }
        var request = URLRequest(url: URL(string: "https://voice.orbit.opik.net/api/devices/active-profile")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["personId": profile.personId])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(APIError.self, from: data).error) ?? "Не вдалося змінити користувача."
            throw PairingFailure.message(message)
        }
        persist(profile)
        familyProfilesLoadState = .loaded
    }

    private func persist(_ profile: FamilyProfile) {
        UserDefaults.standard.set(profile.displayName, forKey: "orbit.displayName")
        UserDefaults.standard.set(profile.personId, forKey: "orbit.personId")
        displayName = profile.displayName
        personId = profile.personId
    }

    func forgetDevice() {
        KeychainStore.removeDeviceToken()
        UserDefaults.standard.removeObject(forKey: "orbit.displayName")
        UserDefaults.standard.removeObject(forKey: "orbit.personId")
        displayName = nil
        personId = nil
        familyProfiles = []
        familyProfilesLoadState = .idle
        isPaired = false
    }
}

enum PairingFailure: LocalizedError {
    case message(String)

    var errorDescription: String? {
        guard case let .message(message) = self else { return nil }
        return message
    }
}
