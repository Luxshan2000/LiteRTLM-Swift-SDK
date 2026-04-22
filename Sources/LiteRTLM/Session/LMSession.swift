import Foundation
import CLiteRTLM

/// A generation session with KV-cache persistence for multi-turn text generation.
///
/// ```swift
/// let session = try await engine.createSession()
/// for try await token in session.generateStream("What is Swift?") {
///     print(token, terminator: "")
/// }
/// session.close()
/// ```
public final class LMSession: @unchecked Sendable {

    private let engine: LMEngine
    private var cSession: OpaquePointer?
    private let sessionConfig: SessionConfiguration
    private let queue = DispatchQueue(label: "com.litertlm.session", qos: .userInitiated)

    init(engine: LMEngine, cSession: OpaquePointer, configuration: SessionConfiguration) {
        self.engine = engine
        self.cSession = cSession
        self.sessionConfig = configuration
    }

    deinit { close() }

    public var isActive: Bool { cSession != nil }

    /// Close the session and release KV-cache memory.
    public func close() {
        if let session = cSession {
            litert_lm_session_delete(session)
            cSession = nil
        }
    }

    // MARK: - Text Generation

    /// Generate a complete response (blocking).
    public func generate(_ prompt: String, template: PromptTemplate = .gemma) async throws -> String {
        guard let session = cSession else { throw LiteRTLMError.noActiveSession }

        let formatted = template.formatSingle(prompt)

        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let result = formatted.withCString { cStr -> String? in
                    var input = InputData(
                        type: kInputText,
                        data: UnsafeRawPointer(cStr),
                        size: strlen(cStr)
                    )
                    guard let responses = litert_lm_session_generate_content(
                        session, &input, 1
                    ) else { return nil }
                    defer { litert_lm_responses_delete(responses) }

                    let count = litert_lm_responses_get_num_candidates(responses)
                    guard count > 0,
                          let text = litert_lm_responses_get_response_text_at(responses, 0) else {
                        return nil
                    }
                    return String(cString: text)
                }

                if let result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: LiteRTLMError.emptyResponse)
                }
            }
        }
    }

    /// Generate a response as a token stream.
    public func generateStream(
        _ prompt: String,
        template: PromptTemplate = .gemma
    ) -> TokenStream {
        let formatted = template.formatSingle(prompt)
        let session = self.cSession
        let q = self.queue

        let stream = AsyncThrowingStream<String, Error> { continuation in
            guard let session else {
                continuation.finish(throwing: LiteRTLMError.noActiveSession)
                return
            }

            q.async {
                final class StreamContext {
                    let continuation: AsyncThrowingStream<String, Error>.Continuation
                    init(_ c: AsyncThrowingStream<String, Error>.Continuation) {
                        self.continuation = c
                    }
                }
                let ctx = StreamContext(continuation)
                let ctxPtr = Unmanaged.passRetained(ctx).toOpaque()

                let cStr = (formatted as NSString).utf8String!
                var input = InputData(
                    type: kInputText,
                    data: UnsafeRawPointer(cStr),
                    size: strlen(cStr)
                )

                let result = litert_lm_session_generate_content_stream(
                    session,
                    &input,
                    1,
                    { callbackData, chunk, isFinal, errorMsg in
                        guard let callbackData else { return }
                        let ctx = Unmanaged<StreamContext>.fromOpaque(callbackData)

                        if let errorMsg {
                            let msg = String(cString: errorMsg)
                            ctx.takeUnretainedValue().continuation.finish(
                                throwing: LiteRTLMError.streamingError(message: msg))
                            ctx.release()
                            return
                        }

                        if let chunk {
                            let str = String(cString: chunk)
                            if !str.isEmpty {
                                ctx.takeUnretainedValue().continuation.yield(str)
                            }
                        }

                        if isFinal {
                            ctx.takeUnretainedValue().continuation.finish()
                            ctx.release()
                        }
                    },
                    ctxPtr
                )

                if result != 0 {
                    Unmanaged<StreamContext>.fromOpaque(ctxPtr)
                        .takeRetainedValue()
                        .continuation
                        .finish(throwing: LiteRTLMError.streamingError(
                            message: "Stream initiation failed with code \(result)"))
                }
            }
        }

        return TokenStream(stream)
    }

    // MARK: - Multimodal Generation

    /// Generate from multimodal inputs (text + images + audio).
    public func generate(
        text: String,
        images: [Data] = [],
        audio: [Data] = [],
        template: PromptTemplate = .gemma
    ) async throws -> String {
        guard let session = cSession else { throw LiteRTLMError.noActiveSession }

        let formatted = template.formatSingle(text)

        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                var inputs: [InputData] = []
                var pinnedData: [Data] = [] // Keep data alive

                // Add images
                for imageData in images {
                    let prepared = (try? ImageUtilities.prepareForVision(imageData, maxDimension: 1024)) ?? imageData
                    pinnedData.append(prepared)
                    prepared.withUnsafeBytes { ptr in
                        inputs.append(InputData(type: kInputImage, data: ptr.baseAddress, size: ptr.count))
                    }
                    inputs.append(InputData(type: kInputImageEnd, data: nil, size: 0))
                }

                // Add audio
                for audioData in audio {
                    pinnedData.append(audioData)
                    audioData.withUnsafeBytes { ptr in
                        inputs.append(InputData(type: kInputAudio, data: ptr.baseAddress, size: ptr.count))
                    }
                    inputs.append(InputData(type: kInputAudioEnd, data: nil, size: 0))
                }

                // Add text
                formatted.withCString { cStr in
                    inputs.append(InputData(type: kInputText, data: UnsafeRawPointer(cStr), size: strlen(cStr)))

                    guard let responses = litert_lm_session_generate_content(
                        session, &inputs, inputs.count
                    ) else {
                        continuation.resume(throwing: LiteRTLMError.emptyResponse)
                        return
                    }
                    defer { litert_lm_responses_delete(responses) }

                    let count = litert_lm_responses_get_num_candidates(responses)
                    guard count > 0,
                          let text = litert_lm_responses_get_response_text_at(responses, 0) else {
                        continuation.resume(throwing: LiteRTLMError.emptyResponse)
                        return
                    }
                    continuation.resume(returning: String(cString: text))
                }
            }
        }
    }

    // MARK: - Benchmark

    /// Retrieve benchmark metrics (requires `benchmarkEnabled` in engine config).
    public func benchmarkInfo() -> BenchmarkInfo? {
        guard let session = cSession else { return nil }
        guard let info = litert_lm_session_get_benchmark_info(session) else { return nil }
        defer { litert_lm_benchmark_info_delete(info) }
        return BenchmarkInfo.from(cInfo: info)
    }
}

// MARK: - Engine Extension

extension LMEngine {

    /// Create a new generation session.
    public func createSession(
        configuration: SessionConfiguration = SessionConfiguration()
    ) async throws -> LMSession {
        let engine = try requireReady()

        // Try with explicit config first, fall back to NULL (C API defaults)
        let sessionCfg = litert_lm_session_config_create()

        if let sessionCfg {
            litert_lm_session_config_set_max_output_tokens(sessionCfg, configuration.maxOutputTokens)

            var samplerParams = configuration.sampler.toCParams()
            litert_lm_session_config_set_sampler_params(sessionCfg, &samplerParams)
        }

        let cSession = litert_lm_engine_create_session(engine, sessionCfg)

        if cSession == nil, sessionCfg != nil {
            // Sampler may not be supported — retry with NULL config (C API defaults)
            litert_lm_session_config_delete(sessionCfg)

            guard let fallback = litert_lm_engine_create_session(engine, nil) else {
                throw LiteRTLMError.sessionCreationFailed
            }
            return LMSession(engine: self, cSession: fallback, configuration: configuration)
        }

        if let sessionCfg { litert_lm_session_config_delete(sessionCfg) }

        guard let cSession else {
            throw LiteRTLMError.sessionCreationFailed
        }

        return LMSession(engine: self, cSession: cSession, configuration: configuration)
    }
}
