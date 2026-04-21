import Foundation

/// Hardware backend for inference.
public enum Backend: String, Sendable {
    case cpu = "cpu"
    case gpu = "gpu"
}

/// Log verbosity level.
public enum LogLevel: Int, Sendable {
    case verbose = 0
    case info = 1
    case warning = 2
    case error = 3
    case silent = 4
}

/// Configuration for creating an `LMEngine`.
///
/// Use the builder-style API:
/// ```swift
/// let config = EngineConfiguration(modelPath: modelURL)
///     .backend(.gpu)
///     .cacheDirectory(cacheURL)
///     .benchmarkEnabled(true)
///     .logLevel(.warning)
/// ```
public struct EngineConfiguration: Sendable {

    /// Path to the `.litertlm` model file.
    public let modelPath: URL

    /// Primary compute backend.
    public private(set) var primaryBackend: Backend = .cpu

    /// Optional fallback backends (up to 2).
    public private(set) var fallbackBackends: [Backend] = []

    /// Maximum number of tokens the engine can handle.
    public private(set) var maxTokens: Int?

    /// Directory for caching compiled model artifacts.
    public private(set) var cacheDir: URL?

    /// Enable benchmark timing instrumentation.
    public private(set) var isBenchmarkEnabled: Bool = false

    /// Minimum log level.
    public private(set) var logLevel: LogLevel = .warning

    public init(modelPath: URL) {
        self.modelPath = modelPath
    }

    // MARK: - Builder Methods

    public func backend(_ backend: Backend) -> EngineConfiguration {
        var copy = self
        copy.primaryBackend = backend
        return copy
    }

    public func fallbacks(_ backends: Backend...) -> EngineConfiguration {
        var copy = self
        copy.fallbackBackends = Array(backends.prefix(2))
        return copy
    }

    public func maxTokens(_ count: Int) -> EngineConfiguration {
        var copy = self
        copy.maxTokens = count
        return copy
    }

    public func cacheDirectory(_ url: URL) -> EngineConfiguration {
        var copy = self
        copy.cacheDir = url
        return copy
    }

    public func benchmarkEnabled(_ enabled: Bool) -> EngineConfiguration {
        var copy = self
        copy.isBenchmarkEnabled = enabled
        return copy
    }

    public func logLevel(_ level: LogLevel) -> EngineConfiguration {
        var copy = self
        copy.logLevel = level
        return copy
    }
}
