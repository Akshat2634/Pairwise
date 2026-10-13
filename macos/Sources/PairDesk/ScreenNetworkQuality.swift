import Foundation

struct CandidatePairRTT: Equatable {
    let id: String
    let roundTripTimeSeconds: Double?
}

enum ScreenNetworkQuality: Equatable {
    case measuring
    case good(roundTripMilliseconds: Int)
    case fair(roundTripMilliseconds: Int)
    case highLatency(roundTripMilliseconds: Int)

    static func from(roundTripTimeSeconds: Double?) -> Self {
        guard let seconds = roundTripTimeSeconds, seconds.isFinite, seconds >= 0 else { return .measuring }
        let milliseconds = Int((seconds * 1_000).rounded())
        if milliseconds <= 150 { return .good(roundTripMilliseconds: milliseconds) }
        if milliseconds <= 300 { return .fair(roundTripMilliseconds: milliseconds) }
        return .highLatency(roundTripMilliseconds: milliseconds)
    }

    /// Returns the RTT of the ICE pair selected by the transport. Other
    /// succeeded/nominated pairs can be probes or stale alternatives and must
    /// not make the active media path look faster than it is.
    static func selectedRoundTripTimeSeconds(selectedPairID: String?, pairs: [CandidatePairRTT]) -> Double? {
        guard let selectedPairID, !selectedPairID.isEmpty else { return nil }
        return pairs.first(where: { $0.id == selectedPairID })?.roundTripTimeSeconds
    }

    var label: String {
        switch self {
        case .measuring: "Measuring network"
        case let .good(milliseconds): "Good · \(milliseconds) ms RTT"
        case let .fair(milliseconds): "Fair · \(milliseconds) ms RTT"
        case let .highLatency(milliseconds): "High latency · \(milliseconds) ms RTT"
        }
    }
}
