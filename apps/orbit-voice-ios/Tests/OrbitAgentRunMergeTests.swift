import Foundation

struct TestMessage: Identifiable, Equatable { let id: String }

@main
struct OrbitAgentRunMergeTests {
    static func main() {
        let placeholder = "agent-run-1"

        var a = [TestMessage(id: "u1"), TestMessage(id: placeholder)]
        precondition(OrbitAgentRunMerge.applyTerminal(&a, placeholderID: placeholder, durable: TestMessage(id: "m2")) == .replacedPlaceholder, "replace")
        precondition(a.map(\.id) == ["u1", "m2"], "replace result")
        precondition(OrbitAgentRunMerge.applyTerminal(&a, placeholderID: placeholder, durable: TestMessage(id: "m2")) == .noChange, "duplicate terminal callback")
        precondition(a.map(\.id) == ["u1", "m2"], "duplicate terminal callback keeps one final message")

        var b = [TestMessage(id: "u1"), TestMessage(id: placeholder), TestMessage(id: "m2")]
        precondition(OrbitAgentRunMerge.applyTerminal(&b, placeholderID: placeholder, durable: TestMessage(id: "m2")) == .removedPlaceholder, "final already delivered by refresh")
        precondition(b.map(\.id) == ["u1", "m2"], "final appears once after refresh race")

        var c = [TestMessage(id: "u1"), TestMessage(id: placeholder)]
        precondition(OrbitAgentRunMerge.applyTerminal(&c, placeholderID: placeholder, durable: nil) == .needsRefresh, "abandoned run needs refresh")
        precondition(c.map(\.id) == ["u1"], "placeholder removed when no final message")

        var d = [TestMessage(id: "u1")]
        precondition(OrbitAgentRunMerge.applyTerminal(&d, placeholderID: placeholder, durable: TestMessage(id: "m2")) == .appended, "append when placeholder gone")
        precondition(d.map(\.id) == ["u1", "m2"], "append result")

        var e = [TestMessage(id: "u1"), TestMessage(id: placeholder)]
        OrbitAgentRunMerge.removePlaceholder(&e, placeholderID: placeholder)
        precondition(e.map(\.id) == ["u1"], "timeout removes placeholder")
        OrbitAgentRunMerge.removePlaceholder(&e, placeholderID: placeholder)
        precondition(e.map(\.id) == ["u1"], "removal is idempotent")

        print("agent run merge tests: PASS")
    }
}
