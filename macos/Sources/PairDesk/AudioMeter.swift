import Foundation

enum AudioMeter {
    static func level(samples: [Float]) -> Double {
        guard !samples.isEmpty else { return 0 }
        let meanSquare = samples.reduce(0.0) { $0 + Double($1 * $1) } / Double(samples.count)
        return min(1, max(0, meanSquare.squareRoot()))
    }
}
