import Foundation

/// How tool calls from the model are handled.
public enum ToolExecutionMode: Sendable {
    /// SDK automatically calls the tool and feeds the result back to the model.
    case automatic
    /// The caller handles tool execution manually.
    case manual
}

/// Configuration for a multi-turn conversation.
///
/// ```swift
/// let config = ConversationConfiguration()
///     .maxOutputTokens(1024)
///     .sampler(.creative)
///     .tools([weatherTool, searchTool])
///     .toolExecution(.automatic)
/// ```
public struct ConversationConfiguration: Sendable {

    /// Maximum tokens per response.
    public private(set) var maxOutputTokens: Int32 = 1024

    /// Sampling parameters.
    public private(set) var sampler: SamplerConfiguration = .balanced

    /// Registered tools the model can call.
    public private(set) var tools: [Tool] = []

    /// How tool calls are executed.
    public private(set) var toolExecutionMode: ToolExecutionMode = .automatic

    /// Maximum image dimension for vision inputs.
    public private(set) var maxImageDimension: Int = 1024

    /// Optional system prompt sent at conversation creation.
    public private(set) var systemPrompt: String?

    public init() {}

    public func maxOutputTokens(_ count: Int32) -> ConversationConfiguration {
        var copy = self
        copy.maxOutputTokens = count
        return copy
    }

    public func sampler(_ sampler: SamplerConfiguration) -> ConversationConfiguration {
        var copy = self
        copy.sampler = sampler
        return copy
    }

    public func tools(_ tools: [Tool]) -> ConversationConfiguration {
        var copy = self
        copy.tools = tools
        return copy
    }

    public func toolExecution(_ mode: ToolExecutionMode) -> ConversationConfiguration {
        var copy = self
        copy.toolExecutionMode = mode
        return copy
    }

    public func maxImageDimension(_ dimension: Int) -> ConversationConfiguration {
        var copy = self
        copy.maxImageDimension = dimension
        return copy
    }

    public func systemPrompt(_ prompt: String?) -> ConversationConfiguration {
        var copy = self
        copy.systemPrompt = prompt
        return copy
    }
}
