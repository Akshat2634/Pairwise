import XCTest
@testable import PairDesk

final class ScreenShareQualityTests: XCTestCase {
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
}
