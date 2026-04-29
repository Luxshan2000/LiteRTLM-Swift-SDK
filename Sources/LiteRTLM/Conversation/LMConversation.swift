import Foundation
import CLiteRTLM
import os.log

private let logger = Logger(subsystem: "com.litertlm", category: "conversation")

/// A multi-turn conversation with automatic history, multimodal support, and tool calling.
///
/// ```swift
/// let conversation = try await engine.createConversation()
/// let response = try await conversation.send("Hello!")
/// let vision = try await conversation.send("What's in this image?", images: [photoData])
/// conversation.close()
/// ```
public final class LMConversation: @unchecked Sendable {

    private let engine: LMEngine
    private var cConversation: OpaquePointer?
    private let config: ConversationConfiguration
    private let queue = DispatchQueue(label: "com.litertlm.conversation", qos: .userInitiated)

    // Gemma 4's chat template has no `system` turn; the C runtime drops
    // `system_message_json`. We fold the configured system prompt into the
    // first user turn instead, then clear it so multi-turn sends aren't
    // polluted.
    private var pendingSystemPrompt: String?

    public private(set) var history: [Message] = []

    init(engine: LMEngine, cConversation: OpaquePointer, configuration: ConversationConfiguration) {
        self.engine = engine
        self.cConversation = cConversation
        self.config = configuration
        self.pendingSystemPrompt = configuration.systemPrompt
    }

    deinit { close() }

    public var isActive: Bool { cConversation != nil }

    /// Close the conversation and release resources.
    public func close() {
        if let conversation = cConversation {
            litert_lm_conversation_delete(conversation)
            cConversation = nil
        }
        history.removeAll()
    }

    /// Cancel an in-progress generation.
    public func cancel() {
        guard let conversation = cConversation else { return }
        litert_lm_conversation_cancel_process(conversation)
    }

    // MARK: - Send Message

    /// Send a text message.
    public func send(_ text: String) async throws -> String {
        try await send(text, images: [], audio: [])
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

        let effectiveText = consumePendingSystemPrompt(prefixing: text)
        let messageJSON = try buildMessageJSON(text: effectiveText, images: images, audio: audio)

        var contentParts: [Content] = [.text(text)]
        for img in images { contentParts.append(.image(img)) }
        for aud in audio { contentParts.append(.audio(aud, format: audioFormat)) }
        history.append(Message(role: .user, content: contentParts))

        // Get the raw JSON response from the C API before any text extraction.
        // Tool call detection must happen on raw JSON where quotes are properly
        // escaped; parseResponseJSON un-escapes them which can break nested JSON.
        let rawResponse: String = try await withCheckedThrowingContinuation { continuation in
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

                continuation.resume(returning: String(cString: cStr))
            }
        }

        // Check for tool calls on the raw response (properly escaped JSON).
        logger.info("📥 RAW response (\(rawResponse.count) chars): \(rawResponse.prefix(1000))")

        if let toolCall = parseToolCall(rawResponse) {
            logger.info("✅ Tool call detected: \(toolCall.name) args=\(toolCall.arguments)")
            history.append(.model(rawResponse))
            return try await handleToolCall(toolCall, conversation: conversation)
        }

        logger.warning("❌ parseToolCall returned nil")

        // No tool call — extract human-readable text for display.
        let response = Self.parseResponseJSON(rawResponse)
        logger.info("📤 Parsed response: \(response.prefix(500))")

        if response.contains("tool_calls") || response.contains("function_call") {
            logger.error("⚠️ Response contains tool_calls but parsing failed! Raw: \(rawResponse)")
        }

        history.append(.model(response))
        return response
    }

    /// Send a message and stream the response token by token.
    public func sendStream(
        _ text: String,
        images: [Data] = [],
        audio: [Data] = [],
        audioFormat: AudioFormat = .wav
    ) throws -> TokenStream {
        guard let conversation = cConversation else {
            throw LiteRTLMError.noActiveConversation
        }

        let effectiveText = consumePendingSystemPrompt(prefixing: text)
        let messageJSON = try buildMessageJSON(text: effectiveText, images: images, audio: audio)

        var contentParts: [Content] = [.text(text)]
        for img in images { contentParts.append(.image(img)) }
        for aud in audio { contentParts.append(.audio(aud, format: audioFormat)) }
        history.append(Message(role: .user, content: contentParts))

        let q = self.queue

        let stream = AsyncThrowingStream<String, Error> { continuation in
            q.async {
                final class StreamCtx {
                    let cont: AsyncThrowingStream<String, Error>.Continuation
                    var lastText = ""
                    init(_ c: AsyncThrowingStream<String, Error>.Continuation) { self.cont = c }
                }
                let ctx = StreamCtx(continuation)
                let ctxPtr = Unmanaged.passRetained(ctx).toOpaque()

                let result = litert_lm_conversation_send_message_stream(
                    conversation, messageJSON, nil,
                    { callbackData, chunk, isFinal, errorMsg in
                        guard let callbackData else { return }
                        let ctx = Unmanaged<StreamCtx>.fromOpaque(callbackData)
                        let state = ctx.takeUnretainedValue()

                        if let errorMsg {
                            state.cont.finish(
                                throwing: LiteRTLMError.streamingError(message: String(cString: errorMsg)))
                            ctx.release()
                            return
                        }

                        if let chunk {
                            let raw = String(cString: chunk)
                            if !raw.isEmpty {
                                // Each chunk is the full JSON response snapshot.
                                // Parse it to extract just the text content.
                                let currentText = LMConversation.parseResponseJSON(raw)

                                // Yield only the delta (new characters since last callback)
                                if currentText.count > state.lastText.count,
                                   currentText.hasPrefix(state.lastText) {
                                    let delta = String(currentText.dropFirst(state.lastText.count))
                                    state.cont.yield(delta)
                                } else if currentText != state.lastText {
                                    // Text changed in a non-append way — yield full replacement
                                    state.cont.yield(currentText)
                                }
                                state.lastText = currentText
                            }
                        }

                        if isFinal {
                            state.cont.finish()
                            ctx.release()
                        }
                    },
                    ctxPtr
                )

                if result != 0 {
                    Unmanaged<StreamCtx>.fromOpaque(ctxPtr)
                        .takeRetainedValue()
                        .cont
                        .finish(throwing: LiteRTLMError.streamingError(
                            message: "Stream initiation failed with code \(result)"))
                }
            }
        }

        return TokenStream(stream)
    }

    // MARK: - Tool Handling

    private struct ToolCall {
        let name: String
        let arguments: [String: Any]
    }

    private func parseToolCall(_ response: String) -> ToolCall? {
        // Attempt 1: Parse raw response as JSON directly.
        if let tc = Self.tryParseToolCall(response) {
            return tc
        }

        // Attempt 2: The model may have emitted Gemma control tokens (e.g. <|"|>)
        // inside argument values. These contain literal quotes that break JSON
        // parsing. Strip them from the raw string and retry.
        let cleaned = Self.stripControlTokens(response)
        if cleaned != response, let tc = Self.tryParseToolCall(cleaned) {
            return tc
        }

        return nil
    }

    /// Try to extract a tool call from a JSON string, checking both top-level
    /// and nested text/content wrappers from the C API.
    private static func tryParseToolCall(_ str: String) -> ToolCall? {
        guard let data = str.data(using: .utf8) else {
            logger.error("🔴 tryParse: failed to convert string to data")
            return nil
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            logger.error("🔴 tryParse: JSONSerialization failed. First 300 chars: \(str.prefix(300))")
            return nil
        }

        logger.info("🔵 tryParse: top-level keys = \(Array(json.keys))")

        // Check top-level for tool_calls / function_call
        if let tc = extractToolCall(from: json) {
            logger.info("🟢 Found tool call at top level")
            return tc
        }

        // Check inside text/content wrapper fields (C API may wrap the response)
        for key in ["text", "content"] {
            if let inner = json[key] as? String {
                logger.info("🔵 Found wrapper key '\(key)', inner length=\(inner.count)")
                // Strip control tokens before re-parsing — the unescaped quotes
                // from tokens like <|"|> would otherwise break JSON parsing.
                let innerCleaned = stripControlTokens(inner)
                logger.info("🔵 After stripControlTokens: \(innerCleaned.prefix(300))")
                if let innerData = innerCleaned.data(using: .utf8),
                   let innerJson = try? JSONSerialization.jsonObject(with: innerData) as? [String: Any] {
                    logger.info("🔵 Inner JSON keys = \(Array(innerJson.keys))")
                    if let tc = extractToolCall(from: innerJson) {
                        logger.info("🟢 Found tool call in wrapper '\(key)'")
                        return tc
                    }
                } else {
                    logger.error("🔴 Inner JSON parse failed after cleaning. First 300: \(innerCleaned.prefix(300))")
                }
            }
        }

        // Content as array: [{"type":"text","text":"..."}]
        if let content = json["content"] as? [[String: Any]] {
            logger.info("🔵 Found content array with \(content.count) parts")
            for (i, part) in content.enumerated() {
                if let inner = part["text"] as? String {
                    logger.info("🔵 Content[\(i)] text length=\(inner.count)")
                    let innerCleaned = stripControlTokens(inner)
                    if let innerData = innerCleaned.data(using: .utf8),
                       let innerJson = try? JSONSerialization.jsonObject(with: innerData) as? [String: Any],
                       let tc = extractToolCall(from: innerJson) {
                        logger.info("🟢 Found tool call in content[\(i)]")
                        return tc
                    }
                }
            }
        }

        logger.warning("🟡 tryParse: no tool call found in any location")
        return nil
    }

    /// Extract a tool call from a parsed JSON dictionary.
    private static func extractToolCall(from json: [String: Any]) -> ToolCall? {
        // Format 1: {"function_call": {"name": "...", "arguments": {...}}}
        if let funcCall = json["function_call"] as? [String: Any],
           let name = funcCall["name"] as? String {
            return ToolCall(name: name, arguments: extractArguments(funcCall["arguments"]))
        }

        // Format 2: {"tool_calls": [{"type":"function","function":{"name":"...","arguments":{...}}}]}
        if let toolCalls = json["tool_calls"] as? [[String: Any]],
           let first = toolCalls.first,
           let function = first["function"] as? [String: Any],
           let name = function["name"] as? String {
            return ToolCall(name: name, arguments: extractArguments(function["arguments"]))
        }

        return nil
    }

    /// Extract arguments from either a dict or a JSON-encoded string, cleaning control tokens.
    private static func extractArguments(_ value: Any?) -> [String: Any] {
        var dict: [String: Any]?
        if let d = value as? [String: Any] {
            dict = d
        } else if let str = value as? String,
                  let data = str.data(using: .utf8),
                  let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            dict = d
        }
        guard let dict else { return [:] }

        // Clean Gemma control tokens from string values
        var cleaned: [String: Any] = [:]
        for (key, value) in dict {
            if let str = value as? String {
                cleaned[key] = Self.stripControlTokens(str)
            } else {
                cleaned[key] = value
            }
        }
        return cleaned
    }

    /// Strip Gemma model control tokens that leak into tool call arguments.
    private static func stripControlTokens(_ text: String) -> String {
        var result = text
        // Strip <|...|> tokens (Gemma 4 turn/control markers)
        while let start = result.range(of: "<|"),
              let end = result.range(of: "|>", range: start.upperBound..<result.endIndex) {
            result.removeSubrange(start.lowerBound..<end.upperBound)
        }
        // Strip legacy markers
        result = result.replacingOccurrences(of: "<start_of_turn>", with: "")
        result = result.replacingOccurrences(of: "<end_of_turn>", with: "")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func handleToolCall(_ toolCall: ToolCall, conversation: OpaquePointer) async throws -> String {
        guard config.toolExecutionMode == .automatic else {
            let dict: [String: Any] = ["function_call": ["name": toolCall.name, "arguments": toolCall.arguments]]
            let data = try JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted)
            return String(data: data, encoding: .utf8) ?? "{}"
        }

        guard let tool = config.tools.first(where: { $0.name == toolCall.name }) else {
            return "Error: Unknown tool '\(toolCall.name)'"
        }

        let result = try await tool.execute(toolCall.arguments)
        let resultJSON = try JSONSerialization.data(withJSONObject: result, options: [])
        let resultStr = String(data: resultJSON, encoding: .utf8) ?? "{}"

        // Send tool result as JSON — matches the format expected by
        // litert_lm_conversation_send_message (message_json parameter).
        let toolResponse: [String: Any] = [
            "role": "tool",
            "content": [["type": "text", "text": resultStr]],
        ]
        let toolData = try JSONSerialization.data(withJSONObject: toolResponse)
        guard let toolMessage = String(data: toolData, encoding: .utf8) else {
            throw LiteRTLMError.internalError("Failed to encode tool result as JSON")
        }

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
                continuation.resume(returning: Self.parseResponseJSON(String(cString: cStr)))
            }
        }
    }

    // MARK: - Message Building

    private func consumePendingSystemPrompt(prefixing text: String) -> String {
        guard let prompt = pendingSystemPrompt else { return text }
        pendingSystemPrompt = nil
        return "\(prompt)\n\n---\n\n\(text)"
    }

    private func buildMessageJSON(text: String, images: [Data], audio: [Data]) throws -> String {
        let tmpDir = FileManager.default.temporaryDirectory
        var parts: [[String: Any]] = []

        for (i, imageData) in images.enumerated() {
            let prepared = try ImageUtilities.prepareForVision(imageData, maxDimension: config.maxImageDimension)
            let path = tmpDir.appendingPathComponent("litertlm_img_\(i).jpg")
            try prepared.write(to: path)
            parts.append(["type": "image", "path": path.path])
        }
        for (i, audioData) in audio.enumerated() {
            let path = tmpDir.appendingPathComponent("litertlm_audio_\(i).wav")
            try audioData.write(to: path)
            parts.append(["type": "audio", "path": path.path])
        }
        parts.append(["type": "text", "text": text])

        let json: [String: Any] = ["role": "user", "content": parts]
        let data = try JSONSerialization.data(withJSONObject: json, options: [])
        return String(data: data, encoding: .utf8) ?? text
    }

    // MARK: - Response Parsing

    static func parseResponseJSON(_ raw: String) -> String {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return raw
        }
        // Direct text field
        if let text = json["text"] as? String { return text }
        // {"role":"assistant","content":[{"type":"text","text":"..."}]}
        if let content = json["content"] as? [[String: Any]] {
            let texts = content.compactMap { $0["text"] as? String }
            if !texts.isEmpty { return texts.joined(separator: "\n") }
        }
        // Content as plain string
        if let content = json["content"] as? String { return content }
        // {"parts":[{"text":"..."}]}
        if let parts = json["parts"] as? [[String: Any]],
           let firstText = parts.first?["text"] as? String { return firstText }
        return raw
    }

    // MARK: - Benchmark

    public func benchmarkInfo() -> BenchmarkInfo? {
        guard let conversation = cConversation else { return nil }
        guard let info = litert_lm_conversation_get_benchmark_info(conversation) else { return nil }
        defer { litert_lm_benchmark_info_delete(info) }
        return BenchmarkInfo.from(cInfo: info)
    }
}

// MARK: - Engine Extension

extension LMEngine {

    /// Create a new multi-turn conversation.
    public func createConversation(
        configuration: ConversationConfiguration = ConversationConfiguration()
    ) async throws -> LMConversation {
        let engine = try requireReady()

        guard let sessionCfg = litert_lm_session_config_create() else {
            throw LiteRTLMError.conversationCreationFailed
        }
        defer { litert_lm_session_config_delete(sessionCfg) }

        litert_lm_session_config_set_max_output_tokens(sessionCfg, configuration.maxOutputTokens)

        var samplerParams = configuration.sampler.toCParams()
        litert_lm_session_config_set_sampler_params(sessionCfg, &samplerParams)

        // Build tools JSON if any
        let toolsJSON: String? = configuration.tools.isEmpty ? nil : {
            let schemas = configuration.tools.map { $0.toJSONSchema() }
            if let data = try? JSONSerialization.data(withJSONObject: schemas),
               let str = String(data: data, encoding: .utf8) {
                return str
            }
            return nil
        }()

        // We deliberately pass nil for system_message_json: the Gemma 4 chat
        // template has no system role, and the C runtime drops this field.
        // LMConversation folds configuration.systemPrompt into the first user
        // turn instead — see LMConversation.pendingSystemPrompt.
        guard let convConfig = litert_lm_conversation_config_create(
            engine,
            sessionCfg,
            nil,            // system_message_json
            toolsJSON,      // tools_json
            nil,            // messages_json
            !configuration.tools.isEmpty  // enable_constrained_decoding
        ) else {
            throw LiteRTLMError.conversationCreationFailed
        }

        guard let cConversation = litert_lm_conversation_create(engine, convConfig) else {
            litert_lm_conversation_config_delete(convConfig)
            throw LiteRTLMError.conversationCreationFailed
        }

        litert_lm_conversation_config_delete(convConfig)
        return LMConversation(engine: self, cConversation: cConversation, configuration: configuration)
    }
}
