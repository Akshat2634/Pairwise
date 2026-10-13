import XCTest
@testable import PairDesk

final class ScreenShareCropTests: XCTestCase {
    func testSelectionClipsToTheDisplayedImageAndNormalizesAgainstItsAspectFitRect() throws {
        let content = CGRect(x: 0, y: 50, width: 800, height: 450)
        let crop = try XCTUnwrap(ScreenCropGeometry.normalizedCrop(
            dragRect: CGRect(x: 100, y: 20, width: 300, height: 200),
            contentRect: content
        ))
        XCTAssertEqual(crop.origin.x, 0.125, accuracy: 0.0001)
        XCTAssertEqual(crop.origin.y, 0, accuracy: 0.0001)
        XCTAssertEqual(crop.width, 0.375, accuracy: 0.0001)
        XCTAssertEqual(crop.height, 170.0 / 450.0, accuracy: 0.0001)
    }

    func testTinyAndOutOfBoundsSelectionsAreRejected() {
        XCTAssertNil(ScreenCropGeometry.normalizedCrop(
            dragRect: CGRect(x: 10, y: 10, width: 10, height: 10),
            contentRect: CGRect(x: 0, y: 0, width: 100, height: 100)
        ))
        XCTAssertNil(ScreenCropGeometry.normalizedCrop(
            dragRect: CGRect(x: 200, y: 200, width: 40, height: 40),
            contentRect: CGRect(x: 0, y: 0, width: 100, height: 100)
        ))
    }

    func testNormalizedCropMapsToDisplayLocalSourceRect() throws {
        let source = try XCTUnwrap(ScreenCropGeometry.sourceRect(
            normalizedCrop: CGRect(x: 0.25, y: 0.2, width: 0.5, height: 0.6),
            displaySize: CGSize(width: 1_920, height: 1_080)
        ))
        XCTAssertEqual(source, CGRect(x: 480, y: 216, width: 960, height: 648))
        XCTAssertNil(ScreenCropGeometry.sourceRect(normalizedCrop: CGRect(x: 0.9, y: 0, width: 0.2, height: 1),
                                                    displaySize: CGSize(width: 1_920, height: 1_080)))
    }
}
