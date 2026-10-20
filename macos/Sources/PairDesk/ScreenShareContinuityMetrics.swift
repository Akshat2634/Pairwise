import Foundation

/// Counts sustained periods where a subscribed screen stream reports zero FPS.
/// Missing stats are treated as unknown; they never become an inferred outage.
struct ScreenShareContinuityMetrics: Equatable {
    private(set) var interruptionCount = 0
    private(set) var lastRecoveryMilliseconds: Int?
    private(set) var longestRecoveryMilliseconds: Int?
    private(set) var activeInterruptionMilliseconds: Int?

    private var zeroFPSStartedAt: TimeInterval?
    private let interruptionThreshold: TimeInterval = 2

    mutating func observe(framesPerSecond: Int?, at uptime: TimeInterval) {
        guard let framesPerSecond else {
            // Do not bridge an unobserved stats gap and turn it into a long
            // outage estimate. The next valid sample starts a new interval.
            zeroFPSStartedAt = nil
            activeInterruptionMilliseconds = nil
            return
        }
        if framesPerSecond == 0 {
            if zeroFPSStartedAt == nil { zeroFPSStartedAt = uptime }
            guard let started = zeroFPSStartedAt else { return }
            let duration = max(0, uptime - started)
            if duration >= interruptionThreshold {
                activeInterruptionMilliseconds = Int((duration * 1_000).rounded())
            }
            return
        }

        guard let started = zeroFPSStartedAt else { return }
        let duration = max(0, uptime - started)
        zeroFPSStartedAt = nil
        activeInterruptionMilliseconds = nil
        guard duration >= interruptionThreshold else { return }
        let milliseconds = Int((duration * 1_000).rounded())
        interruptionCount += 1
        lastRecoveryMilliseconds = milliseconds
        longestRecoveryMilliseconds = max(longestRecoveryMilliseconds ?? 0, milliseconds)
    }

    mutating func reset() {
        self = Self()
    }

    var summary: String {
        if let activeInterruptionMilliseconds {
            return "\(interruptionCount) recovered · interruption ongoing (\(activeInterruptionMilliseconds) ms)"
        }
        guard interruptionCount > 0 else { return "No sustained interruption observed" }
        return "\(interruptionCount) recovered · last \(lastRecoveryMilliseconds ?? 0) ms · longest \(longestRecoveryMilliseconds ?? 0) ms"
    }
}
