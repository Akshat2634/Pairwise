import Foundation
import LiveKit

enum AdaptiveShareTier: Equatable, CaseIterable {
    case fourK
    case q1440
    case q1080
    case q720

    var dimensions: Dimensions {
        switch self {
        case .fourK: Dimensions(width: 3_840, height: 2_160)
        case .q1440: Dimensions(width: 2_560, height: 1_440)
        case .q1080: Dimensions(width: 1_920, height: 1_080)
        case .q720: Dimensions(width: 1_280, height: 720)
        }
    }

    var fps: Int {
        switch self {
        case .fourK, .q1440, .q1080: 30
        case .q720: 15
        }
    }

    var bitrateBudget: Double {
        switch self {
        case .fourK: 8_000_000
        case .q1440: 5_000_000
        case .q1080: 3_000_000
        case .q720: 1_500_000
        }
    }

    var title: String {
        switch self {
        case .fourK: "4K · 30 fps"
        case .q1440: "1440p · 30 fps"
        case .q1080: "1080p · 24 fps"
        case .q720: "720p · 15 fps"
        }
    }

    static func tiers(maximum: ScreenShareQuality) -> [Self] {
        switch maximum {
        case .sharp: [.fourK, .q1440, .q1080, .q720]
        case .balanced: [.q1440, .q1080, .q720]
        case .fast: [.q1080, .q720]
        }
    }
}

struct AdaptiveShareSignal: Equatable {
    let availableOutgoingBitrate: Double?
    let bandwidthLimited: Bool
    let cpuLimited: Bool
    var receiverLimited = false
    var receiversHealthy = false
}

/// Hysteretic quality controller: three consecutive constrained samples step
/// down; eight healthy samples step back up. Unknown bandwidth never triggers
/// a downgrade by itself.
struct AdaptiveShareController {
    private(set) var tierIndex = 0
    private(set) var poorSamples = 0
    private(set) var healthySamples = 0
    let tiers: [AdaptiveShareTier]

    init(maximum: ScreenShareQuality) {
        tiers = AdaptiveShareTier.tiers(maximum: maximum)
    }

    var current: AdaptiveShareTier { tiers[min(tierIndex, tiers.count - 1)] }

    mutating func observe(_ signal: AdaptiveShareSignal) -> AdaptiveShareTier? {
        let capacityIsConstrained = signal.availableOutgoingBitrate.map {
            $0 < current.bitrateBudget * 1.15
        } ?? false
        if signal.bandwidthLimited || signal.cpuLimited || signal.receiverLimited || capacityIsConstrained {
            poorSamples += 1
            healthySamples = 0
        } else if !signal.bandwidthLimited, !signal.cpuLimited, !signal.receiverLimited,
                  signal.receiversHealthy,
                  signal.availableOutgoingBitrate.map({ $0 >= current.bitrateBudget * 1.6 }) ?? true {
            healthySamples += 1
            poorSamples = 0
        } else {
            poorSamples = 0
            healthySamples = 0
        }

        if poorSamples >= 3, tierIndex + 1 < tiers.count {
            tierIndex += 1
            poorSamples = 0
            return current
        }
        if healthySamples >= 8, tierIndex > 0 {
            tierIndex -= 1
            healthySamples = 0
            return current
        }
        return nil
    }
}
