import XCTest
@testable import PairDesk

final class ScreenShareQualityTests: XCTestCase {
    func testReceivedStreamMetricsFormatMeasuredResolutionFrameRateAndLoss() {
        let metrics = ScreenStreamMetrics(width: 2_560,
                                          height: 1_440,
                                          framesPerSecond: 29.6,
                                          packetsReceived: 9_900,
                                          packetsLost: 100)
        XCTAssertEqual(metrics.width, 2_560)
        XCTAssertEqual(metrics.height, 1_440)
        XCTAssertEqual(metrics.framesPerSecond, 30)
        XCTAssertEqual(try XCTUnwrap(metrics.packetLossPercent), 1.0, accuracy: 0.0001)
        XCTAssertEqual(metrics.summary, "2560 × 1440 · 30 fps · 1.0% loss")
    }

    func testReceivedStreamMetricsOmitInvalidOrUnavailableValues() {
        XCTAssertEqual(ScreenStreamMetrics().summary, "Stream stats unavailable")
        XCTAssertEqual(ScreenStreamMetrics(width: 0, height: 1, framesPerSecond: .infinity).summary,
                       "Stream stats unavailable")
        XCTAssertNil(ScreenStreamMetrics(packetsReceived: 10, packetsLost: -1).packetLossPercent)
        XCTAssertNil(ScreenStreamMetrics(packetsReceived: UInt64.max, packetsLost: 1).packetLossPercent)
    }

    func testPresetsMapToRequestedResolutionFrameRateAndBitrate() {
        XCTAssertEqual(ScreenShareQuality.fast.width, 1_920)
        XCTAssertEqual(ScreenShareQuality.fast.height, 1_080)
        XCTAssertEqual(ScreenShareQuality.fast.framesPerSecond, 30)
        XCTAssertEqual(ScreenShareQuality.fast.maxBitrate, 3_000_000)

        XCTAssertEqual(ScreenShareQuality.balanced.width, 2_560)
        XCTAssertEqual(ScreenShareQuality.balanced.height, 1_440)
        XCTAssertEqual(ScreenShareQuality.balanced.framesPerSecond, 30)
        XCTAssertEqual(ScreenShareQuality.balanced.maxBitrate, 5_000_000)

        XCTAssertEqual(ScreenShareQuality.sharp.width, 3_840)
        XCTAssertEqual(ScreenShareQuality.sharp.height, 2_160)
        XCTAssertEqual(ScreenShareQuality.sharp.framesPerSecond, 30)
        XCTAssertEqual(ScreenShareQuality.sharp.maxBitrate, 8_000_000)
    }

    func testPresetSelectionPersistsAndInvalidStoredValueFallsBackToBalanced() {
        let suiteName = "ScreenShareQualityTests.\(UUID().uuidString)"
        let defaults = try! XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(ScreenShareQuality.load(from: defaults), .balanced)
        ScreenShareQuality.sharp.persist(to: defaults)
        XCTAssertEqual(ScreenShareQuality.load(from: defaults), .sharp)

        defaults.set("unknown-quality", forKey: ScreenShareQuality.defaultsKey)
        XCTAssertEqual(ScreenShareQuality.load(from: defaults), .balanced)
    }

    func testRTTUsesExactlyTheSelectedCandidatePair() {
        let pairs = [
            CandidatePairRTT(id: "selected-relay", roundTripTimeSeconds: 0.24),
            CandidatePairRTT(id: "unused-direct-probe", roundTripTimeSeconds: 0.02),
        ]

        let selectedRTT = ScreenNetworkQuality.selectedRoundTripTimeSeconds(
            selectedPairID: "selected-relay",
            pairs: pairs
        )
        XCTAssertEqual(selectedRTT, 0.24)
        XCTAssertEqual(ScreenNetworkQuality.from(roundTripTimeSeconds: selectedRTT), .fair(roundTripMilliseconds: 240))
    }

    func testRTTIsUnavailableWhenTransportHasNoMatchingSelectedPair() {
        let pairs = [CandidatePairRTT(id: "candidate-a", roundTripTimeSeconds: 0.01)]
        XCTAssertNil(ScreenNetworkQuality.selectedRoundTripTimeSeconds(selectedPairID: nil, pairs: pairs))
        XCTAssertNil(ScreenNetworkQuality.selectedRoundTripTimeSeconds(selectedPairID: "candidate-b", pairs: pairs))
        XCTAssertEqual(ScreenNetworkQuality.from(roundTripTimeSeconds: nil), .measuring)
    }

    func testAdaptiveQualityOnlyReducesBelowTheSelectedMaximumAndRecoversWithHysteresis() {
        var controller = AdaptiveShareController(maximum: .sharp)
        XCTAssertEqual(controller.current, .fourK)
        XCTAssertNil(controller.observe(.init(availableOutgoingBitrate: nil, bandwidthLimited: false, cpuLimited: false)))

        let constrained = AdaptiveShareSignal(availableOutgoingBitrate: 2_000_000, bandwidthLimited: true, cpuLimited: false)
        XCTAssertNil(controller.observe(constrained))
        XCTAssertNil(controller.observe(constrained))
        XCTAssertEqual(controller.observe(constrained), .q1440)
        XCTAssertEqual(controller.current.dimensions.width, 2_560)
        XCTAssertEqual(controller.current.fps, 30)

        let healthy = AdaptiveShareSignal(availableOutgoingBitrate: 12_000_000, bandwidthLimited: false, cpuLimited: false,
                                         receiversHealthy: true)
        for _ in 0..<7 { XCTAssertNil(controller.observe(healthy)) }
        XCTAssertEqual(controller.observe(healthy), .fourK)
        XCTAssertEqual(controller.current.dimensions.width, 3_840)
        XCTAssertEqual(controller.current.fps, 30)
    }

    func testAdaptiveQualityHonorsLowerMaximumAndNeverExceedsFourK30() {
        let balanced = AdaptiveShareController(maximum: .balanced)
        XCTAssertEqual(balanced.current, .q1440)
        XCTAssertFalse(AdaptiveShareTier.tiers(maximum: .fast).contains(.fourK))
        XCTAssertTrue(AdaptiveShareTier.allCases.allSatisfy { $0.fps <= 30 && $0.dimensions.width <= 3_840 })
    }
}
