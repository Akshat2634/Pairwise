import Foundation

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

    var label: String {
        switch self {
        case .measuring: "Measuring network"
        case let .good(milliseconds): "Good · \(milliseconds) ms RTT"
        case let .fair(milliseconds): "Fair · \(milliseconds) ms RTT"
        case let .highLatency(milliseconds): "High latency · \(milliseconds) ms RTT"
        }
    }
}
