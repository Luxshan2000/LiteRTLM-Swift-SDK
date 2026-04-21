import Foundation
import CLiteRTLM

/// A multi-turn conversation with automatic history management and multimodal support.
///
/// Conversations maintain context via KV-cache and support text, vision, audio,
/// and tool calling.
///
/// ```swift
/// let conversation = try await engine.createConversation()
/// let response = try await conversation.send("Hello!")
/// let visionResponse = try await conversation.send(
///     "What's in this image?",
///     images: [photoData]
/// )
/// conversation.close()
/// ```
public final class LMConversation: @unchecked Sendable {

    private let engine: LMEngine
    private var cConversation: OpaquePointer?
    private let config: ConversationConfiguration
    private let queue = DispatchQueue(
        label: "com.litertlm.conversation", qos: .userInitiated)

    /// Conversation history for reference.
    public private(set) var history: [Message] = []

    init(
        engine: LMEngine,
        cConversation: OpaquePointer,
        configuration: ConversationConfiguration
    ) {
        self.engine = engine
        self.cConversation = cConversation
        self.config = configuration
    }

    deinit {
        close()
    }

    /// Whether this conversation is still active.
    public var isActive: Bool { cConversation != nil }

    /// Close the conversation and release resources.
    public func close() {
        if let conversation = cConversation {
            litert_lm_conversation_delete(conversation)
            cConversation = nil
        }
        history.removeAll()
    }

    // MARK: - Send Message

    /// Send a text message in the conversation.
    public func send(_ text: String) async throws -> String {
        return try await send(text, images: [], audio: [], audioFormat: .wav)
    }

    /// Send a multimodal message with optional images and audio.
    public func send(
        _ text: String,
        images: [Data] = [],
        audio: [Data] = [],
        audioFormat: AudioFormat = .wav
    ) async throws -> String {
        guard let conversation = cConversation else {
            throw LiteRTLMError.noActiveConversation
        }

        // Build the multimodal message JSON
        let messageJSON = try buildMessageJSON(
            text: text,
            images: images,
            audio: audio,
            audioFormat: audioFormat
        )

        // Record in history
        var contentParts: [Content] = [.text(text)]
        for img in images { contentParts.append(.image(img)) }
        for aud in audio { contentParts.append(.audio(aud, format: audioFormat)) }
        history.append(Message(role: .user, content: contentParts))

        // Send to C API
        let response: String = try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard let jsonResponse = litert_lm_conversation_send_message(
                    conversation, messageJSON, nil
                ) else {
                    continuation.resume(throwing: LiteRTLMError.emptyResponse)
                    return
                }
                defer { litert_lm_json_response_delete(jsonResponse) }

                guard let cStr = litert_lm_json_response_get_string(jsonResponse) else {
                    continuation.resume(throwing: LiteRTLMError.emptyResponse)
                    return
                }

                let raw = String(cString: cStr)
                let parsed = Self.parseResponseJSON(raw)
                continuation.resume(returning: parsed)
            }
        }

        // Record model response
        history.append(.model(response))

        // Handle tool calls if present
        if let toolCall = parseToolCall(response) {
            return try await handleToolCall(toolCall, conversation: conversation)
        }

        return response
    }

    // MARK: - Tool Handling

    private struct ToolCall {
        let name: String
        let arguments: [String: Any]
    }

    private func parseToolCall(_ response: String) -> ToolCall? {
        // Look for function call patterns in the response
        // The model outputs JSON like: {"function_call": {"name": "...", "arguments": {...}}}
        guard let data = response.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let funcCall = json["function_call"] as? [String: Any],
              let name = funcCall["name"] as? String else {
            return nil
        }
        let args = funcCall["arguments"] as? [String: Any] ?? [:]
        return ToolCall(name: name, arguments: args)
    }

    private func handleToolCall(
        _ toolCall: ToolCall,
        conversation: OpaquePointer
    ) async throws -> String {
        guard config.toolExecutionMode == .automatic else {
            // In manual mode, return the raw tool call for the caller to handle
            return try serializeToolCall(toolCall)
        }

        guard let tool = config.tools.first(where: { $0.name == toolCall.name }) else {
            return "Error: Unknown tool '\(toolCall.name)'"
        }

        let result = try await tool.execute(toolCall.arguments)
        let resultJSON = try JSONSerialization.data(
            withJSONObject: result, options: [])
        let resultStr = String(data: resultJSON, encoding: .utf8) ?? "{}"

        // Feed tool result back to the model
        let toolMessage = "<start_of_turn>tool\n\(resultStr)<end_of_turn>\n<start_of_turn>model\n"

        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard let jsonResponse = litert_lm_conversation_send_message(
                    conversation, toolMessage, nil
                ) else {
                    continuation.resume(throwing: LiteRTLMError.emptyResponse)
                    return
                }
                defer { litert_lm_json_response_delete(jsonResponse) }

                guard let cStr = litert_lm_json_response_get_string(jsonResponse) else {
                    continuation.resume(throwing: LiteRTLMError.emptyResponse)
                    return
                }

                let raw = String(cString: cStr)
                let parsed = Self.parseResponseJSON(raw)
                continuation.resume(returning: parsed)
            }
        }
    }

    private func serializeToolCall(_ toolCall: ToolCall) throws -> String {
        let dict: [String: Any] = [
            "function_call": [
                "name": toolCall.name,
                "arguments": toolCall.arguments,
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    // MARK: - Message Building

    private func buildMessageJSON(
        text: String,
        images: [Data],
        audio: [Data],
        audioFormat: AudioFormat
    ) throws -> String {
        // For text-only, send plain text
        if images.isEmpty && audio.isEmpty {
            return text
        }

        // For multimodal, build a JSON content array
        var parts: [[String: Any]] = []

        // Process images
        for imageData in images {
            let prepared = try ImageUtilities.prepareForVision(
                imageData, maxDimension: config.maxImageDimension)
            let base64 = prepared.base64EncodedString()
            parts.append([
                "type": "image",
                "data": base64,
            ])
        }

        // Process audio
        for audioData in audio {
            let base64 = audioData.base64EncodedString()
            parts.append([
                "type": "audio",
                "data": base64,
                "format": audioFormat.rawValue,
            ])
        }

        // Add text
        parts.append([
            "type": "text",
            "text": text,
        ])

        let json: [String: Any] = ["contents": parts]
        let data = try JSONSerialization.data(withJSONObject: json, options: [])
        return String(data: data, encoding: .utf8) ?? text
    }

    // MARK: - Response Parsing

    /// Extract text from the conversation API's JSON response.
    static func parseResponseJSON(_ raw: String) -> String {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return raw
        }

        // Try common response formats
        if let text = json["text"] as? String { return text }
        if let content = json["content"] as? String { return content }
        if let parts = json["parts"] as? [[String: Any]],
           let firstText = parts.first?["text"] as? String {
            return firstText
        }

        return raw
    }
}

// MARK: - Engine Extension for Conversation Creation

extension LMEngine {

    /// Create a new multi-turn conversation.
    public func createConversation(
        configuration: ConversationConfiguration = ConversationConfiguration()
    ) async throws -> LMConversation {
        let engine = try requireReady()

        // Create session config for the conversation
        guard let sessionCfg = litert_lm_session_config_create() else {
            throw LiteRTLMError.conversationCreationFailed
        }
        defer { litert_lm_session_config_delete(sessionCfg) }

        litert_lm_session_config_set_max_output_tokens(
            sessionCfg, configuration.maxOutputTokens)

        if let samplerParams = litert_lm_sampler_params_create() {
            litert_lm_sampler_params_set_temperature(
                samplerParams, configuration.sampler.temperature)
            litert_lm_sampler_params_set_top_k(
                samplerParams, configuration.sampler.topK)
            litert_lm_sampler_params_set_top_p(
                samplerParams, configuration.sampler.topP)
            litert_lm_session_config_set_sampler_params(sessionCfg, samplerParams)
            litert_lm_sampler_params_delete(samplerParams)
        }

        guard let convConfig = litert_lm_conversation_config_create(
            engine, sessionCfg, nil, nil, nil, false
        ) else {
            throw LiteRTLMError.conversationCreationFailed
        }

        guard let cConversation = litert_lm_conversation_create(engine, convConfig) else {
            litert_lm_conversation_config_delete(convConfig)
            throw LiteRTLMError.conversationCreationFailed
        }

        litert_lm_conversation_config_delete(convConfig)
        return LMConversation(
            engine: self,
            cConversation: cConversation,
            configuration: configuration
        )
    }
}
