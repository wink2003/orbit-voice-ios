import Foundation

@main
enum SchoolBrainMarkdownTests {
    static func main() {
        let weekly = "Цього тижня:\n* **Проєктний тиждень:** 12–16 жовтня.\n* **Презентація:** 15 жовтня."
        let weeklyBlocks = SchoolBrainMarkdown.blocks(from: weekly)
        expect(weeklyBlocks.count == 3, "intro paragraph and two bullets are separate blocks")
        expect(
            SchoolBrainMarkdown.plainText(weeklyBlocks) == "Цього тижня:\n• Проєктний тиждень: 12–16 жовтня.\n• Презентація: 15 жовтня.",
            "bullet markers are rendered without raw asterisks"
        )
        expect(hasIntent(weeklyBlocks[1], .stronglyEmphasized), "bold item heading is emphasized")

        let bold = SchoolBrainMarkdown.blocks(from: "Це **важливо** сьогодні")
        expect(SchoolBrainMarkdown.plainText(bold) == "Це важливо сьогодні", "bold markers are removed")
        expect(hasIntent(bold[0], .stronglyEmphasized), "bold text keeps strong emphasis")

        let italic = SchoolBrainMarkdown.blocks(from: "Це *курсив* тут")
        expect(SchoolBrainMarkdown.plainText(italic) == "Це курсив тут", "italic markers are removed")
        expect(hasIntent(italic[0], .emphasized), "italic text keeps emphasis")

        let bullets = SchoolBrainMarkdown.blocks(from: "- Перший\n  - Вкладений\n+ Третій")
        expect(isBullet(bullets[0], level: 0), "top-level dash bullet has level 0")
        expect(isBullet(bullets[1], level: 1), "indented bullet has nested level")
        expect(isBullet(bullets[2], level: 0), "plus bullet is a list item")

        let numbered = SchoolBrainMarkdown.blocks(from: "1. Перший крок\n2. Другий крок\n10) Десятий")
        expect(numbered.count == 3, "numbered items stay separate")
        expect(isNumbered(numbered[0], marker: "1."), "numbered item keeps its number")
        expect(isNumbered(numbered[2], marker: "10)"), "parenthesis numbering keeps its marker")
        expect(SchoolBrainMarkdown.plainText(numbered) == "1. Перший крок\n2. Другий крок\n10) Десятий", "numbers are not replaced by bullets")

        let paragraphs = SchoolBrainMarkdown.blocks(from: "Перший абзац.\n\nДругий абзац.")
        expect(paragraphs.count == 2, "blank line separates paragraphs")

        let multiline = SchoolBrainMarkdown.blocks(from: "Рядок один\nРядок два")
        expect(SchoolBrainMarkdown.plainText(multiline) == "Рядок один\nРядок два", "intentional line breaks are preserved")

        let ukrainian = "Привіт, Олександре! Їжачок їсть ґрунт — і це «добре»."
        expect(SchoolBrainMarkdown.plainText(SchoolBrainMarkdown.blocks(from: ukrainian)) == ukrainian, "Ukrainian Unicode text is preserved exactly")

        let plain = "Гаразд, готово."
        expect(SchoolBrainMarkdown.plainText(SchoolBrainMarkdown.blocks(from: plain)) == plain, "plain text without Markdown is unchanged")

        let malformed = "**незакрите і `код\n* список без тексту\n```\nнезакритий блок"
        let malformedBlocks = SchoolBrainMarkdown.blocks(from: malformed)
        let malformedPlain = SchoolBrainMarkdown.plainText(malformedBlocks)
        expect(malformedPlain.contains("незакрите"), "malformed emphasis falls back to readable text")
        expect(malformedPlain.contains("незакритий блок"), "unclosed code fence keeps its content")

        let heading = SchoolBrainMarkdown.blocks(from: "## Важливо\nТекст")
        expect(isHeading(heading[0], "Важливо"), "ATX heading becomes a heading block")

        let quote = SchoolBrainMarkdown.blocks(from: "> Надійний факт")
        expect(SchoolBrainMarkdown.plainText(quote) == "Надійний факт", "quote marker is removed")

        let code = SchoolBrainMarkdown.blocks(from: "```swift\nlet build = 1.0\n```")
        expect(code.count == 1, "fenced code is a single block")
        if case let .code(value) = code[0] {
            expect(value == "let build = 1.0", "fenced code keeps its content verbatim")
        } else {
            fatalError("FAIL: fenced code block kind")
        }

        let longAnswer = (1...40).map { "Пункт \($0): текст, який має переноситися на кілька рядків у вузькій бульбашці без обрізання." }.joined(separator: "\n\n")
        let longBlocks = SchoolBrainMarkdown.blocks(from: longAnswer)
        expect(longBlocks.count == 40, "long answer keeps every line")
        expect(SchoolBrainMarkdown.plainText(longBlocks).contains("Пункт 40:"), "long answer is not truncated")

        let copied = "Кінець відповіді: **готово**."
        let copiedPlain = SchoolBrainMarkdown.plainText(SchoolBrainMarkdown.blocks(from: copied))
        expect(copiedPlain == "Кінець відповіді: готово.", "selectable text matches the readable answer")

        let rawTokens = SchoolBrainMarkdown.plainText(SchoolBrainMarkdown.blocks(from: weekly + "\n\n## Підсумок\n> *Увага*"))
        expect(!rawTokens.contains("**") && !rawTokens.contains("* "), "valid supported syntax leaves no raw asterisks")

        let web = SchoolBrainMarkdown.blocks(from: "[Розклад](https://school.example/a)")
        expect(hasLink(web[0]), "https links remain tappable")
        let unsafe = SchoolBrainMarkdown.blocks(from: "[Клік](javascript:alert(1))")
        expect(!hasLink(unsafe[0]), "non-web links are not made tappable")
        expect(SchoolBrainMarkdown.plainText(unsafe) == "Клік", "unsafe link keeps its readable label")

        print("SchoolBrainMarkdownTests: PASS")
    }

    private static func text(of block: SchoolBrainMarkdown.Block) -> AttributedString? {
        switch block {
        case let .paragraph(value), let .heading(value), let .bullet(_, value), let .numbered(_, _, value):
            return value
        case .code:
            return nil
        }
    }

    private static func hasIntent(_ block: SchoolBrainMarkdown.Block, _ intent: InlinePresentationIntent) -> Bool {
        guard let value = text(of: block) else { return false }
        return value.runs.contains { $0.inlinePresentationIntent?.contains(intent) == true }
    }

    private static func hasLink(_ block: SchoolBrainMarkdown.Block) -> Bool {
        guard let value = text(of: block) else { return false }
        return value.runs.contains { $0.link != nil }
    }

    private static func isBullet(_ block: SchoolBrainMarkdown.Block, level: Int) -> Bool {
        if case let .bullet(actual, _) = block { return actual == level }
        return false
    }

    private static func isNumbered(_ block: SchoolBrainMarkdown.Block, marker: String) -> Bool {
        if case let .numbered(_, actual, _) = block { return actual == marker }
        return false
    }

    private static func isHeading(_ block: SchoolBrainMarkdown.Block, _ title: String) -> Bool {
        if case let .heading(value) = block { return String(value.characters) == title }
        return false
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("FAIL: \(message)") }
    }
}
