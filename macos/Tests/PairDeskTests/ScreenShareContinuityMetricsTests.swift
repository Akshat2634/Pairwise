import XCTest
@testable import PairDesk

final class ScreenShareContinuityMetricsTests: XCTestCase {
    func testIgnoresBriefFPSDropAndMissingSamples() {
        var metrics = ScreenShareContinuityMetrics()
        metrics.observe(framesPerSecond: 30, at: 10)
        metrics.observe(framesPerSecond: 0, at: 11)
        metrics.observe(framesPerSecond: nil, at: 12)
        metrics.observe(framesPerSecond: 30, at: 14)

        XCTAssertEqual(metrics.interruptionCount, 0)
        XCTAssertEqual(metrics.summary, "No sustained interruption observed")
    }

    func testCountsSustainedDropAndRecoveryDuration() {
        var metrics = ScreenShareContinuityMetrics()
        metrics.observe(framesPerSecond: 30, at: 10)
        metrics.observe(framesPerSecond: 0, at: 11)
        metrics.observe(framesPerSecond: 0, at: 13.25)
        XCTAssertEqual(metrics.activeInterruptionMilliseconds, 2_250)

        metrics.observe(framesPerSecond: 30, at: 14)
        XCTAssertEqual(metrics.interruptionCount, 1)
        XCTAssertEqual(metrics.lastRecoveryMilliseconds, 3_000)
        XCTAssertEqual(metrics.longestRecoveryMilliseconds, 3_000)
        XCTAssertNil(metrics.activeInterruptionMilliseconds)
    }

    func testResetsAtNewObservationSession() {
        var metrics = ScreenShareContinuityMetrics()
        metrics.observe(framesPerSecond: 0, at: 10)
        metrics.observe(framesPerSecond: 30, at: 13)
        metrics.reset()

        XCTAssertEqual(metrics.interruptionCount, 0)
        XCTAssertNil(metrics.lastRecoveryMilliseconds)
        XCTAssertNil(metrics.activeInterruptionMilliseconds)
    }
}
