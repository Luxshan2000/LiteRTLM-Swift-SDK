import Foundation

/// Prompt formatting utilities for supported model families.
public enum PromptTemplate: Sendable {

    /// Gemma 4 turn markers (`<|turn>` / `<turn|>`).
    case gemma

    /// Legacy Gemma 2/3 turn markers (`<start_of_turn>` / `<end_of_turn>`).
    case gemmaLegacy

    /// Raw passthrough — no formatting applied.
    case raw

    /// Format a single user prompt for one-shot generation.
    public func formatSingle(_ prompt: String) -> String {
        switch self {
        case .gemma:
            return "<|turn>user\n\(prompt)\n<turn|>\n<|turn>model\n"
        case .gemmaLegacy:
            return "<start_of_turn>user\n\(prompt)<end_of_turn>\n<start_of_turn>model\n"
        case .raw:
            return prompt
        }
    }

    /// Format a conversation history into a single prompt string.
    public func formatConversation(_ messages: [Message]) -> String {
        switch self {
        case .gemma:
            var result = ""
            for message in messages {
                let roleName: String
                switch message.role {
                case .user: roleName = "user"
                case .model: roleName = "model"
                case .system: roleName = "system"
                case .tool: roleName = "user"
                }
                let text = message.content.compactMap { part -> String? in
                    if case .text(let t) = part { return t }
                    return nil
                }.joined(separator: "\n")
                result += "<|turn>\(roleName)\n\(text)\n<turn|>\n"
            }
            result += "<|turn>model\n"
            return result
        case .gemmaLegacy:
            var result = ""
            for message in messages {
                let roleName: String
                switch message.role {
                case .user: roleName = "user"
                case .model: roleName = "model"
                case .system: roleName = "user"
                case .tool: roleName = "user"
                }
                let text = message.content.compactMap { part -> String? in
                    if case .text(let t) = part { return t }
                    return nil
                }.joined(separator: "\n")
                result += "<start_of_turn>\(roleName)\n\(text)<end_of_turn>\n"
            }
            result += "<start_of_turn>model\n"
            return result
        case .raw:
            return messages.compactMap { msg in
                msg.content.compactMap { part -> String? in
                    if case .text(let t) = part { return t }
                    return nil
                }.joined(separator: "\n")
            }.joined(separator: "\n")
        }
    }
}
