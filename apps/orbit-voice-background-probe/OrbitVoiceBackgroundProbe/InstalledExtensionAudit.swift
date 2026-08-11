import Foundation

struct InstalledExtensionAudit {
    static let publishedHostBundleID = "net.opik.orbit.voice.backgroundprobe"
    static let publishedWidgetBundleID = "net.opik.orbit.voice.backgroundprobe.widget"

    struct Snapshot {
        let report: String
    }

    static func capture() -> Snapshot {
        let fileManager = FileManager.default
        let host = Bundle.main
        var lines: [String] = []

        lines.append("INSTALLED HOST")
        lines.append("bundleIdentifier: \(host.bundleIdentifier ?? "none")")
        lines.append("version: \(host.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "none")")
        lines.append("build: \(host.object(forInfoDictionaryKey: "CFBundleVersion") ?? "none")")
        lines.append("bundleURL: \(host.bundleURL.path)")
        lines.append("builtInPlugInsURL: \(host.builtInPlugInsURL?.path ?? "none")")
        lines.append("matches published host ID: \(host.bundleIdentifier == publishedHostBundleID ? "yes" : "no")")

        guard let pluginsURL = host.builtInPlugInsURL else {
            lines.append("")
            lines.append("INSTALLED EXTENSIONS")
            lines.append("No built-in PlugIns directory was reported by Bundle.main.")
            return Snapshot(report: lines.joined(separator: "\n"))
        }

        do {
            let urls = try fileManager.contentsOfDirectory(
                at: pluginsURL,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )
            .filter { $0.pathExtension.lowercased() == "appex" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

            lines.append("")
            lines.append("INSTALLED EXTENSIONS (\(urls.count))")
            if urls.isEmpty {
                lines.append("No .appex bundles found in the installed app package.")
            }

            for url in urls {
                lines.append("")
                lines.append("[\(url.lastPathComponent)]")
                lines.append("path: \(url.path)")
                lines.append("file exists: \(fileManager.fileExists(atPath: url.path) ? "yes" : "no")")

                guard let extensionBundle = Bundle(url: url) else {
                    lines.append("bundle can be opened: no")
                    continue
                }

                let info = extensionBundle.infoDictionary ?? [:]
                let extensionID = extensionBundle.bundleIdentifier
                let executable = stringValue(info["CFBundleExecutable"])
                let executableURL = executable.map { url.appendingPathComponent($0) }
                let provisionURL = url.appendingPathComponent("embedded.mobileprovision")
                let codeSignatureURL = url.appendingPathComponent("_CodeSignature")

                lines.append("bundle can be opened: yes")
                lines.append("CFBundleIdentifier: \(extensionID ?? "none")")
                lines.append("CFBundleDisplayName: \(stringValue(info["CFBundleDisplayName"]) ?? "none")")
                lines.append("CFBundleName: \(stringValue(info["CFBundleName"]) ?? "none")")
                lines.append("CFBundleExecutable: \(executable ?? "none")")
                lines.append("CFBundleShortVersionString: \(stringValue(info["CFBundleShortVersionString"]) ?? "none")")
                lines.append("CFBundleVersion: \(stringValue(info["CFBundleVersion"]) ?? "none")")

                let extensionDictionary = info["NSExtension"] as? [String: Any]
                lines.append("NSExtensionPointIdentifier: \(stringValue(extensionDictionary?["NSExtensionPointIdentifier"]) ?? "none")")
                lines.append("NSExtension: \(prettyJSON(extensionDictionary) ?? String(describing: extensionDictionary ?? [:]))")
                lines.append("executable file exists: \(executableURL.map { fileManager.fileExists(atPath: $0.path) } == true ? "yes" : "no")")
                lines.append("embedded.mobileprovision exists: \(fileManager.fileExists(atPath: provisionURL.path) ? "yes" : "no")")
                if let attributes = try? fileManager.attributesOfItem(atPath: provisionURL.path),
                   let size = attributes[.size] {
                    lines.append("embedded.mobileprovision size: \(size) bytes")
                }
                lines.append("_CodeSignature exists: \(fileManager.fileExists(atPath: codeSignatureURL.path) ? "yes" : "no")")
                lines.append("matches published widget ID: \(extensionID == publishedWidgetBundleID ? "yes" : "no")")
                let relationship = host.bundleIdentifier.flatMap { hostID in extensionID?.hasPrefix(hostID + ".") } ?? false
                lines.append("extension ID has installed host prefix: \(relationship ? "yes" : "no")")
                if let hostID = host.bundleIdentifier, let extensionID {
                    lines.append("installed ID relationship: \(hostID) -> \(extensionID)")
                }
            }
        } catch {
            lines.append("")
            lines.append("INSTALLED EXTENSIONS")
            lines.append("Could not enumerate PlugIns: \(fullError(error))")
        }

        return Snapshot(report: lines.joined(separator: "\n"))
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let value else { return nil }
        return String(describing: value)
    }

    private static func prettyJSON(_ dictionary: [String: Any]?) -> String? {
        guard let dictionary,
              JSONSerialization.isValidJSONObject(dictionary),
              let data = try? JSONSerialization.data(withJSONObject: dictionary, options: [.prettyPrinted, .sortedKeys]),
              let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }

    private static func fullError(_ error: Error) -> String {
        let nsError = error as NSError
        return "domain=\(nsError.domain); code=\(nsError.code); description=\(nsError.localizedDescription); userInfo=\(nsError.userInfo)"
    }
}
