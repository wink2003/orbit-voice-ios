import Foundation

enum OrbitMiniEndPhrases {
    private static let storageKey = "mini.endPhrases"
    static let defaults = ["кінець", "завершити", "закінчити", "стоп", "досить", "до побачення"]

    static var phrases: [String] {
        let stored = UserDefaults.standard.stringArray(forKey: storageKey) ?? defaults
        return canonicalize(stored)
    }

    static func save(_ newPhrases: [String]) {
        UserDefaults.standard.set(canonicalize(newPhrases), forKey: storageKey)
    }

    static func restoreDefaults() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    static func matches(_ transcript: String) -> Bool {
        let normalizedTranscript = normalize(transcript)
        guard !normalizedTranscript.isEmpty else { return false }
        return phrases.contains { normalize($0) == normalizedTranscript }
    }

    static func normalize(_ phrase: String) -> String {
        phrase
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: .punctuationCharacters)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(with: Locale(identifier: "uk_UA"))
    }

    private static func canonicalize(_ candidates: [String]) -> [String] {
        var seen = Set<String>()
        return candidates.compactMap { candidate in
            let normalized = normalize(candidate)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { return nil }
            return candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
