import Foundation

enum SchoolBrainMarkdown {
    enum Block: Equatable {
        case paragraph(AttributedString)
        case heading(AttributedString)
        case bullet(level: Int, AttributedString)
        case numbered(level: Int, marker: String, AttributedString)
        case code(String)
    }

    static func blocks(from content: String) -> [Block] {
        var blocks: [Block] = []
        var pending: Pending?
        var codeLines: [String]?

        func flush() {
            switch pending {
            case let .paragraph(lines)?:
                blocks.append(.paragraph(inline(lines.joined(separator: "\n"))))
            case let .item(level, marker, lines)?:
                let text = inline(lines.joined(separator: "\n"))
                if let marker {
                    blocks.append(.numbered(level: level, marker: marker, text))
                } else {
                    blocks.append(.bullet(level: level, text))
                }
            case nil:
                break
            }
            pending = nil
        }

        for rawLine in content.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if let lines = codeLines {
                    blocks.append(.code(lines.joined(separator: "\n")))
                    codeLines = nil
                } else {
                    flush()
                    codeLines = []
                }
                continue
            }
            if codeLines != nil {
                codeLines?.append(rawLine)
                continue
            }
            if trimmed.isEmpty {
                flush()
                continue
            }
            if let title = headingText(trimmed) {
                flush()
                blocks.append(.heading(inline(title)))
                continue
            }
            let indent = rawLine.prefix(while: { $0 == " " || $0 == "\t" }).count
            if let text = bulletText(trimmed) {
                flush()
                pending = .item(level: indent / 2, marker: nil, lines: [text])
                continue
            }
            if let ordered = orderedItem(trimmed) {
                flush()
                pending = .item(level: indent / 2, marker: ordered.marker, lines: [ordered.text])
                continue
            }
            let text = quoteText(trimmed)
            switch pending {
            case let .paragraph(lines)?:
                pending = .paragraph(lines + [text])
            case let .item(level, marker, lines)?:
                pending = .item(level: level, marker: marker, lines: lines + [text])
            case nil:
                pending = .paragraph([text])
            }
        }
        flush()
        if let lines = codeLines {
            blocks.append(.code(lines.joined(separator: "\n")))
        }
        return blocks
    }

    static func plainText(_ blocks: [Block]) -> String {
        blocks.map { block -> String in
            switch block {
            case let .paragraph(text), let .heading(text):
                return String(text.characters)
            case let .bullet(_, text):
                return "• " + String(text.characters)
            case let .numbered(_, marker, text):
                return marker + " " + String(text.characters)
            case let .code(code):
                return code
            }
        }.joined(separator: "\n")
    }

    static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard var parsed = try? AttributedString(markdown: text, options: options) else {
            return AttributedString(text)
        }
        let unsafeLinks = parsed.runs.compactMap { run -> Range<AttributedString.Index>? in
            guard let url = run.link else { return nil }
            return ["http", "https"].contains(url.scheme?.lowercased() ?? "") ? nil : run.range
        }
        for range in unsafeLinks {
            parsed[range].link = nil
        }
        return parsed
    }

    private enum Pending {
        case paragraph([String])
        case item(level: Int, marker: String?, lines: [String])
    }

    private static func headingText(_ line: String) -> String? {
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes) else { return nil }
        let rest = line.dropFirst(hashes)
        guard rest.first == " " else { return nil }
        return rest.trimmingCharacters(in: .whitespaces)
    }

    private static func bulletText(_ line: String) -> String? {
        guard let marker = line.first, ["-", "*", "+", "•"].contains(marker) else { return nil }
        let rest = line.dropFirst()
        guard rest.first == " " else { return nil }
        return rest.trimmingCharacters(in: .whitespaces)
    }

    private static func orderedItem(_ line: String) -> (marker: String, text: String)? {
        let digits = line.prefix(while: { $0.isASCII && $0.isNumber })
        guard !digits.isEmpty, digits.count <= 9 else { return nil }
        let rest = line.dropFirst(digits.count)
        guard let punctuation = rest.first, punctuation == "." || punctuation == ")" else { return nil }
        let afterPunctuation = rest.dropFirst()
        guard afterPunctuation.first == " " else { return nil }
        return ("\(digits)\(punctuation)", afterPunctuation.trimmingCharacters(in: .whitespaces))
    }

    private static func quoteText(_ line: String) -> String {
        guard line.hasPrefix(">") else { return line }
        return String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
    }
}
