import Foundation

enum OrbitChatMarkdownFormatting {
    // AttributedString's Markdown parser treats a single newline as a soft
    // break. Gemini commonly uses those newlines between independently useful
    // text parts, so preserve them as visible breaks without changing the
    // stored/copyable source message.
    static func displaySource(_ content: String) -> String {
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        guard lines.count > 1 else { return normalized }

        var output = ""
        var inCodeFence = false
        for index in lines.indices {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isFence = trimmed.hasPrefix("```")
            output += line
            if index == lines.count - 1 { break }

            let next = lines[index + 1].trimmingCharacters(in: .whitespaces)
            let preserveMarkdownLine = inCodeFence || isFence || trimmed.isEmpty || next.isEmpty
                || isMarkdownListLine(trimmed) || isMarkdownListLine(next) || trimmed.hasPrefix(">") || next.hasPrefix(">")
            output += preserveMarkdownLine ? "\n" : "  \n"
            if isFence { inCodeFence.toggle() }
        }
        return output
    }

    // Full Markdown parsing on iOS may discard block whitespace. Keep inline
    // emphasis/link parsing, while making the already-authored block markers
    // displayable and retaining every meaningful line boundary.
    static func preservingWhitespaceSource(_ content: String) -> String {
        let source = displaySource(content)
        let lines = source.components(separatedBy: "\n")
        var output: [String] = []
        var inCodeFence = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                output.append(line)
                inCodeFence.toggle()
                continue
            }
            guard !inCodeFence else {
                output.append(line)
                continue
            }
            if let heading = line.range(of: "^(\\s*)#{1,6}\\s+(.*)$", options: .regularExpression) {
                let match = String(line[heading])
                let title = match.replacingOccurrences(of: "^\\s*#{1,6}\\s+", with: "", options: .regularExpression)
                output.append("**\(title)**")
            } else if let bullet = line.range(of: "^(\\s*)[*+-]\\s+(.*)$", options: .regularExpression) {
                let match = String(line[bullet])
                let item = match.replacingOccurrences(of: "^\\s*[*+-]\\s+", with: "", options: .regularExpression)
                output.append("• \(item)")
            } else if let ordered = line.range(of: "^(\\s*)[0-9]+\\.\\s+(.*)$", options: .regularExpression) {
                let match = String(line[ordered])
                let item = match.replacingOccurrences(of: "^\\s*[0-9]+\\.\\s+", with: "", options: .regularExpression)
                output.append("• \(item)")
            } else {
                output.append(line)
            }
        }
        return output.joined(separator: "\n")
    }

    private static func isMarkdownListLine(_ line: String) -> Bool {
        line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ")
            || line.range(of: "^[0-9]+\\.\\s", options: .regularExpression) != nil
    }
}
