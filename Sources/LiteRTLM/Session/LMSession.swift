import Foundation
import CLiteRTLM

/// A generation session with KV-cache persistence for multi-turn text generation.
///
/// Sessions maintain context across turns, making follow-up responses faster
/// (~1-2s vs ~20s for cold start).
///
/// ```swift
/// let engine = LMEngine(configuration: config)
/// try await engine.load()
///
/// let session = try await engine.createSession()
/// let stream = session.generateStream("What is Swift?")
/// for try await token in stream {
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

    deinit {
        close()
    }

    /// Whether this session is still active.
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
                guard let textInput = litert_lm_input_data_create_text(formatted) else {
                    continuation.resume(throwing: LiteRTLMError.invalidInput(
                        detail: "Failed to create text input"))
                    return
                }
                defer { litert_lm_input_data_delete(textInput) }

                guard let responses = litert_lm_session_generate_content(
                    session, textInput, 1
                ) else {
                    continuation.resume(throwing: LiteRTLMError.emptyResponse)
                    return
                }
                defer { litert_lm_responses_delete(responses) }

                let count = litert_lm_responses_get_num_candidates(responses)
                guard count > 0,
                      let cStr = litert_lm_responses_get_response_text_at(responses, 0) else {
                    continuation.resume(throwing: LiteRTLMError.emptyResponse)
                    return
                }
                continuation.resume(returning: String(cString: cStr))
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
            guard let session = session else {
                continuation.finish(throwing: LiteRTLMError.noActiveSession)
                return
            }

            q.async {
                guard let textInput = litert_lm_input_data_create_text(formatted) else {
                    continuation.finish(throwing: LiteRTLMError.invalidInput(
                        detail: "Failed to create text input"))
                    return
                }
                defer { litert_lm_input_data_delete(textInput) }

                // Context for the C callback
                final class StreamContext {
                    let continuation: AsyncThrowingStream<String, Error>.Continuation
                    init(_ c: AsyncThrowingStream<String, Error>.Continuation) {
                        self.continuation = c
                    }
                }
                let ctx = StreamContext(continuation)
                let ctxPtr = Unmanaged.passRetained(ctx).toOpaque()

                let result = litert_lm_session_generate_content_stream(
                    session,
                    textInput,
                    1,
                    { callbackData, token, isDone, error in
                        guard let callbackData else { return }
                        let ctx = Unmanaged<StreamContext>.fromOpaque(callbackData)

                        if let error {
                            let msg = String(cString: error)
                            ctx.takeUnretainedValue().continuation.finish(
                                throwing: LiteRTLMError.streamingError(message: msg))
                            ctx.release()
                            return
                        }

                        if let token {
                            let str = String(cString: token)
                            if !str.isEmpty {
                                ctx.takeUnretainedValue().continuation.yield(str)
                            }
                        }

                        if isDone {
                            ctx.takeUnretainedValue().continuation.finish()
                            ctx.release()
                        }
                    },
                    ctxPtr
                )

                if result != 0 {
                    let ctx = Unmanaged<StreamContext>.fromOpaque(ctxPtr)
                    ctx.takeUnretainedValue().continuation.finish(
                        throwing: LiteRTLMError.streamingError(
                            message: "Stream initiation failed with code \(result)"))
                    ctx.release()
                }
            }
        }

        return TokenStream(stream)
    }

    // MARK: - Benchmark

    /// Retrieve benchmark metrics (requires `benchmarkEnabled` in engine config).
    public func benchmarkInfo() -> BenchmarkInfo? {
        guard let session = cSession else { return nil }
        guard let info = litert_lm_session_get_benchmark_info(session) else {
            return nil
        }
        defer { litert_lm_benchmark_info_delete(info) }

        let initTime = litert_lm_benchmark_info_get_total_init_time_in_second(info)
        let ttft = litert_lm_benchmark_info_get_time_to_first_token(info)
        let numPrefill = litert_lm_benchmark_info_get_num_prefill_turns(info)
        let numDecode = litert_lm_benchmark_info_get_num_decode_turns(info)

        var prefillTurns: [BenchmarkInfo.TurnMetric] = []
        for i in 0..<numPrefill {
            prefillTurns.append(.init(
                tokensPerSecond: litert_lm_benchmark_info_get_prefill_tokens_per_sec_at(info, i),
                tokenCount: Int(litert_lm_benchmark_info_get_prefill_token_count_at(info, i))
            ))
        }

        var decodeTurns: [BenchmarkInfo.TurnMetric] = []
        for i in 0..<numDecode {
            decodeTurns.append(.init(
                tokensPerSecond: litert_lm_benchmark_info_get_decode_tokens_per_sec_at(info, i),
                tokenCount: Int(litert_lm_benchmark_info_get_decode_token_count_at(info, i))
            ))
        }

        return BenchmarkInfo(
            initTime: initTime,
            timeToFirstToken: ttft,
            prefillTurns: prefillTurns,
            decodeTurns: decodeTurns
        )
    }
}

// MARK: - Engine Extension for Session Creation

extension LMEngine {

    /// Create a new generation session.
    public func createSession(
        configuration: SessionConfiguration = SessionConfiguration()
    ) async throws -> LMSession {
        let engine = try requireReady()

        guard let sessionCfg = litert_lm_session_config_create() else {
            throw LiteRTLMError.sessionCreationFailed
        }

        litert_lm_session_config_set_max_output_tokens(
            sessionCfg, configuration.maxOutputTokens)

        // Set sampler
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

        guard let cSession = litert_lm_engine_create_session(engine, sessionCfg) else {
            litert_lm_session_config_delete(sessionCfg)
            throw LiteRTLMError.sessionCreationFailed
        }

        litert_lm_session_config_delete(sessionCfg)
        return LMSession(engine: self, cSession: cSession, configuration: configuration)
    }
}
