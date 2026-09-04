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

    private static func isMarkdownListLine(_ line: String) -> Bool {
        line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ")
            || line.range(of: "^[0-9]+\\.\\s", options: .regularExpression) != nil
    }
}
