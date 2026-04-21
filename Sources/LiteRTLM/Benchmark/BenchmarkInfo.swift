import Foundation
import CLiteRTLM

/// Performance metrics collected during inference.
public struct BenchmarkInfo: Sendable {

    public let initTime: Double
    public let timeToFirstToken: Double
    public let prefillTurns: [TurnMetric]
    public let decodeTurns: [TurnMetric]

    public struct TurnMetric: Sendable {
        public let tokensPerSecond: Double
        public let tokenCount: Int
    }

    public var averageDecodeSpeed: Double {
        guard !decodeTurns.isEmpty else { return 0 }
        return decodeTurns.reduce(0.0) { $0 + $1.tokensPerSecond } / Double(decodeTurns.count)
    }

    public var averagePrefillSpeed: Double {
        guard !prefillTurns.isEmpty else { return 0 }
        return prefillTurns.reduce(0.0) { $0 + $1.tokensPerSecond } / Double(prefillTurns.count)
    }

    public var totalTokensGenerated: Int {
        decodeTurns.reduce(0) { $0 + $1.tokenCount }
    }

    /// Create from the C benchmark info handle.
    static func from(cInfo info: OpaquePointer) -> BenchmarkInfo {
        let initTime = litert_lm_benchmark_info_get_total_init_time_in_second(info)
        let ttft = litert_lm_benchmark_info_get_time_to_first_token(info)
        let numPrefill = litert_lm_benchmark_info_get_num_prefill_turns(info)
        let numDecode = litert_lm_benchmark_info_get_num_decode_turns(info)

        var prefillTurns: [TurnMetric] = []
        for i in 0..<Int32(numPrefill) {
            prefillTurns.append(.init(
                tokensPerSecond: litert_lm_benchmark_info_get_prefill_tokens_per_sec_at(info, i),
                tokenCount: Int(litert_lm_benchmark_info_get_prefill_token_count_at(info, i))
            ))
        }

        var decodeTurns: [TurnMetric] = []
        for i in 0..<Int32(numDecode) {
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
