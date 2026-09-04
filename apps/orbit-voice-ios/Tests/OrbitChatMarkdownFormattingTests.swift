import Foundation

@main
enum OrbitChatMarkdownFormattingTests {
    static func main() {
        expect(
            OrbitChatMarkdownFormatting.displaySource("Компоненти Orbit\nСистема складається з компонентів.") == "Компоненти Orbit  \nСистема складається з компонентів.",
            "plain adjacent parts get a visible break"
        )
        expect(
            OrbitChatMarkdownFormatting.displaySource("- Main Orbit\n- Orbit Core") == "- Main Orbit\n- Orbit Core",
            "Markdown bullets remain separate"
        )
        let blocks = OrbitChatMarkdownFormatting.preservingWhitespaceSource("### Компоненти\n*   **Orbit Core:** сервіс\n*   **LiveKit:** голос")
        expect(blocks == "**Компоненти**\n• **Orbit Core:** сервіс\n• **LiveKit:** голос", "headings and bullets remain readable")
        expect(
            OrbitChatMarkdownFormatting.displaySource("**Компоненти Orbit**\nСистема складається з компонентів.").contains("**Компоненти Orbit**  \nСистема"),
            "bold headings remain separated"
        )
        expect(
            OrbitChatMarkdownFormatting.displaySource("Перший абзац.\n\nДругий абзац.") == "Перший абзац.\n\nДругий абзац.",
            "blank paragraphs remain unchanged"
        )
        expect(
            OrbitChatMarkdownFormatting.displaySource("> Надійний факт\n> Наступний факт") == "> Надійний факт\n> Наступний факт",
            "quotes remain separate"
        )
        expect(
            OrbitChatMarkdownFormatting.displaySource("```swift\nlet build = 1.0\n```") == "```swift\nlet build = 1.0\n```",
            "fenced code remains unchanged"
        )
        expect(
            OrbitChatMarkdownFormatting.preservingWhitespaceSource("```swift\nlet build = 1.0\n```") == "```swift\nlet build = 1.0\n```",
            "fenced code is not rewritten"
        )
        let labels = OrbitChatMarkdownFormatting.displaySource("**Версія:** 1.0\n**Build:** 19")
        expect(!labels.contains("1.0Build"), "label/value blocks do not concatenate")
        let identifiers = "orbit-core\nmain-server\npending_configuration\nnet.opik.orbit.mini\n1.1\n18.8 GB\nhttps://example.com/a"
        let formatted = OrbitChatMarkdownFormatting.displaySource(identifiers)
        for value in ["orbit-core", "main-server", "pending_configuration", "net.opik.orbit.mini", "1.1", "18.8 GB", "https://example.com/a"] {
            expect(formatted.contains(value), "identifier and value remain unchanged: \(value)")
        }
        expect(OrbitChatMarkdownFormatting.displaySource("Гаразд, готово.") == "Гаразд, готово.", "short answers stay compact")
        print("OrbitChatMarkdownFormattingTests: PASS")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("FAIL: \(message)") }
    }
}
