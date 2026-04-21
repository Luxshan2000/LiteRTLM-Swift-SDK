import Foundation
import CLiteRTLM

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

    public private(set) var history: [Message] = []

    init(engine: LMEngine, cConversation: OpaquePointer, configuration: ConversationConfiguration) {
        self.engine = engine
        self.cConversation = cConversation
        self.config = configuration
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

        let messageJSON = try buildMessageJSON(text: text, images: images, audio: audio)

        var contentParts: [Content] = [.text(text)]
        for img in images { contentParts.append(.image(img)) }
        for aud in audio { contentParts.append(.audio(aud, format: audioFormat)) }
        history.append(Message(role: .user, content: contentParts))

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
                continuation.resume(returning: Self.parseResponseJSON(raw))
            }
        }

        history.append(.model(response))

        if let toolCall = parseToolCall(response) {
            return try await handleToolCall(toolCall, conversation: conversation)
        }

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

        let messageJSON = (try? buildMessageJSON(text: text, images: images, audio: audio)) ?? text

        var contentParts: [Content] = [.text(text)]
        for img in images { contentParts.append(.image(img)) }
        for aud in audio { contentParts.append(.audio(aud, format: audioFormat)) }
        history.append(Message(role: .user, content: contentParts))

        let q = self.queue

        let stream = AsyncThrowingStream<String, Error> { continuation in
            q.async {
                final class StreamCtx {
                    let cont: AsyncThrowingStream<String, Error>.Continuation
                    var accumulated = ""
                    init(_ c: AsyncThrowingStream<String, Error>.Continuation) { self.cont = c }
                }
                let ctx = StreamCtx(continuation)
                let ctxPtr = Unmanaged.passRetained(ctx).toOpaque()

                let result = litert_lm_conversation_send_message_stream(
                    conversation, messageJSON, nil,
                    { callbackData, chunk, isFinal, errorMsg in
                        guard let callbackData else { return }
                        let ctx = Unmanaged<StreamCtx>.fromOpaque(callbackData)

                        if let errorMsg {
                            ctx.takeUnretainedValue().cont.finish(
                                throwing: LiteRTLMError.streamingError(message: String(cString: errorMsg)))
                            ctx.release()
                            return
                        }

                        if let chunk {
                            let str = String(cString: chunk)
                            if !str.isEmpty {
                                ctx.takeUnretainedValue().accumulated += str
                                ctx.takeUnretainedValue().cont.yield(str)
                            }
                        }

                        if isFinal {
                            ctx.takeUnretainedValue().cont.finish()
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
        guard let data = response.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let funcCall = json["function_call"] as? [String: Any],
              let name = funcCall["name"] as? String else {
            return nil
        }
        return ToolCall(name: name, arguments: funcCall["arguments"] as? [String: Any] ?? [:])
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
                continuation.resume(returning: Self.parseResponseJSON(String(cString: cStr)))
            }
        }
    }

    // MARK: - Message Building

    private func buildMessageJSON(text: String, images: [Data], audio: [Data]) throws -> String {
        if images.isEmpty && audio.isEmpty { return text }

        var parts: [[String: Any]] = []
        for imageData in images {
            let prepared = try ImageUtilities.prepareForVision(imageData, maxDimension: config.maxImageDimension)
            parts.append(["type": "image", "data": prepared.base64EncodedString()])
        }
        for audioData in audio {
            parts.append(["type": "audio", "data": audioData.base64EncodedString()])
        }
        parts.append(["type": "text", "text": text])

        let json: [String: Any] = ["contents": parts]
        let data = try JSONSerialization.data(withJSONObject: json, options: [])
        return String(data: data, encoding: .utf8) ?? text
    }

    // MARK: - Response Parsing

    static func parseResponseJSON(_ raw: String) -> String {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return raw
        }
        if let text = json["text"] as? String { return text }
        if let content = json["content"] as? String { return content }
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
