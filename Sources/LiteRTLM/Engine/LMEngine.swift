import Foundation
import CLiteRTLM

/// The lifecycle state of the engine.
public enum EngineStatus: Sendable {
    case notLoaded
    case loading
    case ready
    case error(LiteRTLMError)
}

/// Actor-based LLM engine managing the full lifecycle of a LiteRT-LM model.
///
/// ```swift
/// let config = EngineConfiguration(modelPath: modelURL)
///     .backend(.gpu)
///     .benchmarkEnabled(true)
///
/// let engine = LMEngine(configuration: config)
/// try await engine.load()
/// // use sessions / conversations
/// engine.unload()
/// ```
public actor LMEngine {

    // MARK: - Public State

    /// Current engine status.
    public private(set) var status: EngineStatus = .notLoaded

    /// Whether the engine is ready for inference.
    public var isReady: Bool {
        if case .ready = status { return true }
        return false
    }

    /// The configuration used to create this engine.
    public let configuration: EngineConfiguration

    // MARK: - Internal C Handles

    nonisolated(unsafe) var cEngine: OpaquePointer?

    // MARK: - Init

    public init(configuration: EngineConfiguration) {
        self.configuration = configuration
    }

    deinit {
        if let engine = cEngine {
            litert_lm_engine_delete(engine)
        }
    }

    // MARK: - Lifecycle

    /// Load the model into memory. Blocks until ready.
    public func load() async throws {
        guard !isReady else { throw LiteRTLMError.engineAlreadyLoaded }

        let config = configuration
        let modelPath = config.modelPath.path

        guard FileManager.default.fileExists(atPath: modelPath) else {
            let err = LiteRTLMError.modelNotFound(path: modelPath)
            status = .error(err)
            throw err
        }

        status = .loading

        // Set log level
        litert_lm_set_min_log_level(Int32(config.logLevel.rawValue))

        // Create settings
        let fallback1 = config.fallbackBackends.first?.rawValue
        let fallback2 = config.fallbackBackends.count > 1
            ? config.fallbackBackends[1].rawValue : nil

        guard let settings = litert_lm_engine_settings_create(
            modelPath,
            config.primaryBackend.rawValue,
            fallback1,
            fallback2
        ) else {
            let err = LiteRTLMError.engineCreationFailed(
                reason: "Failed to create engine settings")
            status = .error(err)
            throw err
        }

        defer { litert_lm_engine_settings_delete(settings) }

        if let maxTokens = config.maxTokens {
            litert_lm_engine_settings_set_max_num_tokens(
                settings, Int32(maxTokens))
        }

        if let cacheDir = config.cacheDir {
            litert_lm_engine_settings_set_cache_dir(
                settings, cacheDir.path)
        }

        if config.isBenchmarkEnabled {
            litert_lm_engine_settings_enable_benchmark(settings)
        }

        // Create engine (heavy — loads model weights)
        guard let engine = litert_lm_engine_create(settings) else {
            let err = LiteRTLMError.engineCreationFailed(
                reason: "litert_lm_engine_create returned NULL")
            status = .error(err)
            throw err
        }

        cEngine = engine
        status = .ready
    }

    /// Release the model from memory.
    public func unload() {
        if let engine = cEngine {
            litert_lm_engine_delete(engine)
            cEngine = nil
        }
        status = .notLoaded
    }

    // MARK: - Internal Helpers

    /// Ensure the engine is ready, or throw.
    func requireReady() throws -> OpaquePointer {
        guard let engine = cEngine else {
            throw LiteRTLMError.engineNotReady
        }
        return engine
    }
}
