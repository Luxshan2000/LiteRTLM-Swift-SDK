import Foundation

/// Sampling strategy for text generation.
public struct SamplerConfiguration: Sendable {

    /// Controls randomness. 0.0 = greedy, 1.0+ = creative.
    public var temperature: Float

    /// Top-K filtering. Only the top K tokens are considered.
    public var topK: Int32

    /// Top-P (nucleus) filtering. Tokens with cumulative probability ≤ topP.
    public var topP: Float

    /// Greedy decoding (temperature = 0).
    public static let greedy = SamplerConfiguration(temperature: 0.0, topK: 1, topP: 1.0)

    /// Balanced defaults.
    public static let balanced = SamplerConfiguration(temperature: 0.7, topK: 40, topP: 0.95)

    /// Creative generation.
    public static let creative = SamplerConfiguration(temperature: 1.0, topK: 100, topP: 0.98)

    public init(temperature: Float = 0.7, topK: Int32 = 40, topP: Float = 0.95) {
        self.temperature = temperature
        self.topK = topK
        self.topP = topP
    }
}

/// Configuration for a generation session.
///
/// ```swift
/// let config = SessionConfiguration()
///     .maxOutputTokens(1024)
///     .sampler(.creative)
/// ```
public struct SessionConfiguration: Sendable {

    /// Maximum tokens to generate per response.
    public private(set) var maxOutputTokens: Int32 = 512

    /// Sampling parameters.
    public private(set) var sampler: SamplerConfiguration = .balanced

    public init() {}

    public func maxOutputTokens(_ count: Int32) -> SessionConfiguration {
        var copy = self
        copy.maxOutputTokens = count
        return copy
    }

    public func sampler(_ sampler: SamplerConfiguration) -> SessionConfiguration {
        var copy = self
        copy.sampler = sampler
        return copy
    }
}
