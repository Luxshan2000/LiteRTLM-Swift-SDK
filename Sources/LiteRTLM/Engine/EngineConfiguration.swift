import Foundation

/// Hardware backend for inference.
public enum Backend: String, Sendable {
    case cpu = "cpu"
    case gpu = "gpu"
}

/// Log verbosity level.
public enum LogLevel: Int, Sendable {
    case info = 0
    case warning = 1
    case error = 2
    case fatal = 3
    case silent = 4
}

/// Configuration for creating an `LMEngine`.
///
/// ```swift
/// let config = EngineConfiguration(modelPath: modelURL)
///     .backend(.gpu)
///     .cacheDirectory(cacheURL)
///     .benchmarkEnabled(true)
/// ```
public struct EngineConfiguration: Sendable {

    public let modelPath: URL
    public private(set) var primaryBackend: Backend = .cpu
    public private(set) var visionBackend: Backend?
    public private(set) var audioBackend: Backend?
    public private(set) var maxTokens: Int?
    public private(set) var cacheDir: URL?
    public private(set) var isBenchmarkEnabled: Bool = false
    public private(set) var logLevel: LogLevel = .warning

    public init(modelPath: URL) {
        self.modelPath = modelPath
    }

    public func backend(_ backend: Backend) -> EngineConfiguration {
        var copy = self
        copy.primaryBackend = backend
        return copy
    }

    public func visionBackend(_ backend: Backend) -> EngineConfiguration {
        var copy = self
        copy.visionBackend = backend
        return copy
    }

    public func audioBackend(_ backend: Backend) -> EngineConfiguration {
        var copy = self
        copy.audioBackend = backend
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
