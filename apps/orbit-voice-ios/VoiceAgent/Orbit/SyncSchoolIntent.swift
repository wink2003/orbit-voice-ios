import AppIntents

struct SyncSchoolIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Sync School"
    nonisolated static let description = IntentDescription("Sends an authenticated school-sync trigger to Orbit.")
    nonisolated static let openAppWhenRun = false

    func perform() async throws -> some IntentResult {
        try await MainProductAPI.triggerSchoolSync()
        return .result()
    }
}
