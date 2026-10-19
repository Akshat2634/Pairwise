import XCTest
@testable import PairDesk

final class CameraVideoMetricsTests: XCTestCase {
    func testCameraMetricsSummarizeMeasuredDimensionsAndFrameRate() {
        let metrics = CameraVideoMetrics(width: 1_280, height: 720, framesPerSecond: 29.6)
        XCTAssertEqual(metrics.summary, "1280 × 720 · 30 fps")
    }

    func testCameraMetricsKeepUnavailableAndInvalidValuesDistinctFromZero() {
        XCTAssertEqual(CameraVideoMetrics().summary, "Video stats unavailable")
        XCTAssertEqual(CameraVideoMetrics(width: 0, height: 720, framesPerSecond: .infinity).summary,
                       "Video stats unavailable")
        XCTAssertEqual(CameraVideoMetrics(width: 1_920, height: 1_080).summary, "1920 × 1080")
    }
}
