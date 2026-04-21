import Foundation

/// Performance metrics collected during inference.
public struct BenchmarkInfo: Sendable {

    /// Total engine initialization time in seconds.
    public let initTime: Double

    /// Time to first token in seconds.
    public let timeToFirstToken: Double

    /// Per-turn prefill metrics.
    public let prefillTurns: [TurnMetric]

    /// Per-turn decode metrics.
    public let decodeTurns: [TurnMetric]

    /// A single turn's performance data.
    public struct TurnMetric: Sendable {
        /// Tokens processed per second.
        public let tokensPerSecond: Double
        /// Total token count in this turn.
        public let tokenCount: Int
    }

    /// Average decode speed across all turns (tokens/sec).
    public var averageDecodeSpeed: Double {
        guard !decodeTurns.isEmpty else { return 0 }
        let total = decodeTurns.reduce(0.0) { $0 + $1.tokensPerSecond }
        return total / Double(decodeTurns.count)
    }

    /// Average prefill speed across all turns (tokens/sec).
    public var averagePrefillSpeed: Double {
        guard !prefillTurns.isEmpty else { return 0 }
        let total = prefillTurns.reduce(0.0) { $0 + $1.tokensPerSecond }
        return total / Double(prefillTurns.count)
    }

    /// Total tokens generated across all decode turns.
    public var totalTokensGenerated: Int {
        decodeTurns.reduce(0) { $0 + $1.tokenCount }
    }
}
