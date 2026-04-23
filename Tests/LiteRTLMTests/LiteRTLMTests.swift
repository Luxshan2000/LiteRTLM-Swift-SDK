import XCTest
@testable import LiteRTLM

final class LiteRTLMTests: XCTestCase {

    func testEngineConfigurationBuilder() {
        let url = URL(fileURLWithPath: "/tmp/model.litertlm")
        let config = EngineConfiguration(modelPath: url)
            .backend(.gpu)
            .visionBackend(.gpu)
            .audioBackend(.cpu)
            .maxTokens(4096)
            .benchmarkEnabled(true)
            .logLevel(.warning)

        XCTAssertEqual(config.primaryBackend, .gpu)
        XCTAssertEqual(config.visionBackend, .gpu)
        XCTAssertEqual(config.audioBackend, .cpu)
        XCTAssertEqual(config.maxTokens, 4096)
        XCTAssertTrue(config.isBenchmarkEnabled)
        XCTAssertEqual(config.logLevel, .warning)
    }

    func testSessionConfigurationBuilder() {
        let config = SessionConfiguration()
            .maxOutputTokens(1024)
            .sampler(.creative)

        XCTAssertEqual(config.maxOutputTokens, 1024)
        XCTAssertEqual(config.sampler.temperature, 1.0)
    }

    func testSamplerPresets() {
        XCTAssertEqual(SamplerConfiguration.greedy.temperature, 0.0)
        XCTAssertEqual(SamplerConfiguration.balanced.temperature, 0.7)
        XCTAssertEqual(SamplerConfiguration.creative.temperature, 1.0)
    }

    func testSamplerToCParams() {
        let sampler = SamplerConfiguration(temperature: 0.5, topK: 20, topP: 0.9, seed: 42, samplerType: .topP)
        let cParams = sampler.toCParams()
        XCTAssertEqual(cParams.temperature, 0.5)
        XCTAssertEqual(cParams.top_k, 20)
        XCTAssertEqual(cParams.top_p, 0.9)
        XCTAssertEqual(cParams.seed, 42)
    }

    func testConversationConfigurationBuilder() {
        let tool = Tool(
            name: "test",
            description: "A test tool",
            parameters: [.init(name: "arg", type: .string, required: true)]
        ) { _ in [:] }

        let config = ConversationConfiguration()
            .maxOutputTokens(2048)
            .tools([tool])
            .toolExecution(.manual)

        XCTAssertEqual(config.maxOutputTokens, 2048)
        XCTAssertEqual(config.tools.count, 1)
        XCTAssertEqual(config.tools.first?.name, "test")
        if case .manual = config.toolExecutionMode {} else {
            XCTFail("Expected manual tool execution mode")
        }
    }

    func testPromptTemplateGemma() {
        let formatted = PromptTemplate.gemma.formatSingle("Hello")
        XCTAssertTrue(formatted.contains("<|turn>user"))
        XCTAssertTrue(formatted.contains("Hello"))
        XCTAssertTrue(formatted.contains("<|turn>model"))
    }

    func testPromptTemplateGemmaLegacy() {
        let formatted = PromptTemplate.gemmaLegacy.formatSingle("Hello")
        XCTAssertTrue(formatted.contains("<start_of_turn>user"))
        XCTAssertTrue(formatted.contains("Hello"))
        XCTAssertTrue(formatted.contains("<start_of_turn>model"))
    }

    func testPromptTemplateRaw() {
        XCTAssertEqual(PromptTemplate.raw.formatSingle("Hello"), "Hello")
    }

    func testPromptTemplateConversation() {
        let messages: [Message] = [
            .user("Hi"),
            .model("Hello!"),
            .user("How are you?"),
        ]
        let formatted = PromptTemplate.gemma.formatConversation(messages)
        XCTAssertTrue(formatted.hasPrefix("<|turn>user"))
        XCTAssertTrue(formatted.hasSuffix("<|turn>model\n"))
        XCTAssertTrue(formatted.contains("Hello!"))
    }

    func testPromptTemplateLegacyConversation() {
        let messages: [Message] = [
            .user("Hi"),
            .model("Hello!"),
        ]
        let formatted = PromptTemplate.gemmaLegacy.formatConversation(messages)
        XCTAssertTrue(formatted.hasPrefix("<start_of_turn>user"))
        XCTAssertTrue(formatted.hasSuffix("<start_of_turn>model\n"))
        XCTAssertTrue(formatted.contains("Hello!"))
    }

    func testContentTypes() {
        let text = Content.text("hello")
        let image = Content.image(Data(), maxDimension: 512)
        let audio = Content.audio(Data(), format: .wav)

        if case .text(let t) = text { XCTAssertEqual(t, "hello") }
        if case .image(_, let dim) = image { XCTAssertEqual(dim, 512) }
        if case .audio(_, let fmt) = audio { XCTAssertEqual(fmt, .wav) }
    }

    func testMessageConvenience() {
        let msg = Message.user("test")
        XCTAssertEqual(msg.role, .user)
        XCTAssertEqual(msg.content.count, 1)
    }

    func testToolJSONSchema() {
        let tool = Tool(
            name: "search",
            description: "Search the web",
            parameters: [
                .init(name: "query", type: .string, description: "Search query", required: true),
                .init(name: "limit", type: .integer, description: "Max results"),
            ]
        ) { _ in [:] }

        let schema = tool.toJSONSchema()
        XCTAssertNotNil(schema["function"])
    }

    func testEngineInitialState() async {
        let url = URL(fileURLWithPath: "/tmp/model.litertlm")
        let config = EngineConfiguration(modelPath: url)
        let engine = LMEngine(configuration: config)
        let isReady = await engine.isReady
        XCTAssertFalse(isReady)
    }

    func testTokenStreamCollect() async throws {
        let stream = AsyncThrowingStream<String, Error> { continuation in
            continuation.yield("Hello")
            continuation.yield(" World")
            continuation.finish()
        }
        let tokenStream = TokenStream(stream)
        let result = try await tokenStream.collect()
        XCTAssertEqual(result, "Hello World")
    }

    func testBenchmarkInfoMetrics() {
        let info = BenchmarkInfo(
            initTime: 5.0,
            timeToFirstToken: 0.3,
            prefillTurns: [
                .init(tokensPerSecond: 100, tokenCount: 50),
                .init(tokensPerSecond: 120, tokenCount: 60),
            ],
            decodeTurns: [
                .init(tokensPerSecond: 30, tokenCount: 200),
                .init(tokensPerSecond: 32, tokenCount: 150),
            ]
        )
        XCTAssertEqual(info.averagePrefillSpeed, 110.0)
        XCTAssertEqual(info.averageDecodeSpeed, 31.0)
        XCTAssertEqual(info.totalTokensGenerated, 350)
    }

    func testConversationResponseParsing() {
        // Plain text passthrough
        XCTAssertEqual(LMConversation.parseResponseJSON("hello"), "hello")
        // Direct text field
        XCTAssertEqual(LMConversation.parseResponseJSON(#"{"text": "parsed"}"#), "parsed")
        // Content as string
        XCTAssertEqual(LMConversation.parseResponseJSON(#"{"content": "content"}"#), "content")
        // Content as array of parts
        XCTAssertEqual(
            LMConversation.parseResponseJSON(#"{"role":"assistant","content":[{"type":"text","text":"hello"}]}"#),
            "hello"
        )
        // Parts format
        XCTAssertEqual(
            LMConversation.parseResponseJSON(#"{"parts":[{"text":"from parts"}]}"#),
            "from parts"
        )
    }

    func testErrorDescriptions() {
        let errors: [LiteRTLMError] = [
            .engineNotReady,
            .noActiveSession,
            .emptyResponse,
            .modelNotFound(path: "/tmp/x"),
        ]
        for error in errors {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }
    }
}
