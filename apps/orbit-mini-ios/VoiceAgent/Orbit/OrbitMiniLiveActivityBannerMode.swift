import Foundation

enum OrbitMiniLiveActivityBannerMode: String, CaseIterable, Identifiable {
    case onlyOrbit
    case everySpeakerChange
    case off

    static let storageKey = "mini.liveActivityBannerMode"

    static var current: OrbitMiniLiveActivityBannerMode {
        OrbitMiniLiveActivityBannerMode(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .onlyOrbit
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .onlyOrbit: "Лише коли говорить Orbit"
        case .everySpeakerChange: "При кожній зміні співрозмовника"
        case .off: "Вимкнено"
        }
    }
}
