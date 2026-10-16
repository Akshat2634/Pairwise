import AppKit
import XCTest
@testable import PairDesk

@MainActor
final class ScreenShareIndicatorTests: XCTestCase {
    func testCaptureCoordinatesMapDisplayOffsetsAndCropToAppKit() {
        XCTAssertEqual(ScreenShareIndicator.appKitFrame(
            captureBounds: CGRect(x: -1920, y: -200, width: 1920, height: 1080), primaryScreenMaxY: 900),
            CGRect(x: -1920, y: 20, width: 1920, height: 1080))
        XCTAssertEqual(ScreenShareIndicator.appKitFrame(
            captureBounds: CGRect(x: 120, y: 100, width: 640, height: 480), primaryScreenMaxY: 900),
            CGRect(x: 120, y: 320, width: 640, height: 480))
    }

    func testNativePanelCoversOnlySharedDisplayOrCropAndCannotTakeInput() throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let id = try XCTUnwrap(screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).uint32Value
        let indicator = ScreenShareIndicator()
        defer { indicator.hide() }
        indicator.show(.display(id, crop: .zero))
        let fullDisplay = try XCTUnwrap(indicator.panel)
        XCTAssertTrue(fullDisplay.isVisible)
        XCTAssertEqual(fullDisplay.frame, screen.frame)
        XCTAssertTrue(fullDisplay.ignoresMouseEvents)
        XCTAssertFalse(fullDisplay.canBecomeKey)
        XCTAssertFalse(fullDisplay.canBecomeMain)
        XCTAssertTrue(fullDisplay.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(fullDisplay.collectionBehavior.contains(.fullScreenAuxiliary))

        let crop = CGRect(x: 100, y: 120, width: 400, height: 300)
        indicator.show(.display(id, crop: crop))
        XCTAssertFalse(fullDisplay.isVisible)
        let panel = try XCTUnwrap(indicator.panel)
        let bounds = CGDisplayBounds(id)
        XCTAssertEqual(panel.frame, ScreenShareIndicator.appKitFrame(
            captureBounds: crop.offsetBy(dx: bounds.minX, dy: bounds.minY), primaryScreenMaxY: screen.frame.maxY))
        indicator.hide()
        XCTAssertFalse(panel.isVisible)
        XCTAssertNil(indicator.panel)
    }

    func testWindowIndicatorFollowsMovementAndHidesWhenWindowCloses() async throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: 200, y: 200, width: 400, height: 300),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.orderFrontRegardless()
        let indicator = ScreenShareIndicator()
        defer { indicator.hide(); window.close() }
        indicator.show(.window(CGWindowID(window.windowNumber)))
        let panel = try XCTUnwrap(indicator.panel)
        try await waitFor { panel.isVisible }
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(panel.frame, window.frame)
        window.setFrame(CGRect(x: 250, y: 260, width: 600, height: 400), display: true)
        try await waitFor { panel.frame == window.frame }
        XCTAssertEqual(panel.frame, window.frame)
        window.orderOut(nil)
        try await waitFor { !panel.isVisible }
        XCTAssertFalse(panel.isVisible)
        window.orderFrontRegardless()
        try await waitFor { panel.isVisible }
        XCTAssertTrue(panel.isVisible)
        window.close()
        try await waitFor { !panel.isVisible }
        XCTAssertFalse(panel.isVisible)
    }

    func testBorderRendersRedWithTransparentInterior() throws {
        let view = SharingBorderView(frame: CGRect(x: 0, y: 0, width: 800, height: 500))
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let center = try XCTUnwrap(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2))
        XCTAssertEqual(center.alphaComponent, 0)
        let edge = try XCTUnwrap(bitmap.colorAt(x: Int(2 * CGFloat(bitmap.pixelsWide) / 800),
                                               y: bitmap.pixelsHigh / 2)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(edge.redComponent, edge.greenComponent * 1.5)
        XCTAssertGreaterThan(edge.alphaComponent, 0.9)
    }

    private func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<40 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
    }
}
