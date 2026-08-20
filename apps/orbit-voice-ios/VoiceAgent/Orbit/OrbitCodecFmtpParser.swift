import Foundation

struct OrbitCodecFmtpParser {
    private static let allowedKeys: [String: String] = [
        "useinbandfec": "useinbandfec",
        "usedtx": "usedtx",
        "minptime": "minptime",
        "maxaveragebitrate": "maxaveragebitrate",
        "stereo": "stereo",
        "sprop-stereo": "spropStereo",
        "cbr": "cbr",
    ]

    /// Parses only approved scalar codec parameters. Raw fmtp/SDP never
    /// leaves this process. A malformed token invalidates the whole result.
    static func parse(_ line: String?) -> [String: String]? {
        guard let line, !line.isEmpty else { return nil }
        var result: [String: String] = [:]
        for rawToken in line.split(separator: ";", omittingEmptySubsequences: false) {
            let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty,
                  let separator = token.firstIndex(of: "=") else { return nil }
            let key = token[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = token[token.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value.count <= 32,
                  value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || ".-_".contains($0)) }) else { return nil }
            if let safeKey = allowedKeys[key] { result[safeKey] = value }
        }
        return result.isEmpty ? nil : result
    }
}
