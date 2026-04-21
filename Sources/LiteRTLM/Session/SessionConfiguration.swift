import Foundation
import CLiteRTLM

/// Sampling strategy for text generation.
public struct SamplerConfiguration: Sendable {
    public var temperature: Float
    public var topK: Int32
    public var topP: Float
    public var seed: Int32

    /// Which sampling algorithm to use.
    public var samplerType: SamplerType

    public enum SamplerType: Sendable {
        case topK
        case topP
        case greedy
    }

    public static let greedy = SamplerConfiguration(
        temperature: 0.0, topK: 1, topP: 1.0, seed: 0, samplerType: .greedy)

    public static let balanced = SamplerConfiguration(
        temperature: 0.7, topK: 40, topP: 0.95, seed: 0, samplerType: .topK)

    public static let creative = SamplerConfiguration(
        temperature: 1.0, topK: 100, topP: 0.98, seed: 0, samplerType: .topP)

    public init(
        temperature: Float = 0.7,
        topK: Int32 = 40,
        topP: Float = 0.95,
        seed: Int32 = 0,
        samplerType: SamplerType = .topK
    ) {
        self.temperature = temperature
        self.topK = topK
        self.topP = topP
        self.seed = seed
        self.samplerType = samplerType
    }

    /// Convert to the C struct.
    func toCParams() -> LiteRtLmSamplerParams {
        let cType: Type
        switch samplerType {
        case .topK: cType = kTopK
        case .topP: cType = kTopP
        case .greedy: cType = kGreedy
        }
        return LiteRtLmSamplerParams(
            type: cType,
            top_k: topK,
            top_p: topP,
            temperature: temperature,
            seed: seed
        )
    }
}

/// Configuration for a generation session.
public struct SessionConfiguration: Sendable {
    public private(set) var maxOutputTokens: Int32 = 512
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
