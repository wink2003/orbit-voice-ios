import Foundation

enum OrbitAgentRunMerge {
    enum Outcome: Equatable {
        case replacedPlaceholder
        case removedPlaceholder
        case appended
        case noChange
        case needsRefresh
    }

    static func removePlaceholder<M: Identifiable>(_ messages: inout [M], placeholderID: String) where M.ID == String {
        messages.removeAll { $0.id == placeholderID }
    }

    /// Server chat state stays authoritative: the durable final message is shown at most once.
    static func applyTerminal<M: Identifiable>(_ messages: inout [M], placeholderID: String, durable finalMessage: M?) -> Outcome where M.ID == String {
        guard let finalMessage else {
            removePlaceholder(&messages, placeholderID: placeholderID)
            return .needsRefresh
        }
        let hasFinal = messages.contains { $0.id == finalMessage.id }
        if let index = messages.firstIndex(where: { $0.id == placeholderID }) {
            if hasFinal {
                messages.remove(at: index)
                return .removedPlaceholder
            }
            messages[index] = finalMessage
            return .replacedPlaceholder
        }
        if hasFinal { return .noChange }
        messages.append(finalMessage)
        return .appended
    }
}
