import AppKit
import SwiftUI
import LiveKit

struct InteractiveScreenView: NSViewRepresentable {
    let track: VideoTrack
    @ObservedObject var rtc: RTCService
    func makeNSView(context: Context) -> ScreenCanvas { ScreenCanvas(rtc: rtc) }
    func updateNSView(_ view: ScreenCanvas, context: Context) {
        view.video.track = track
        view.driving = rtc.controlState.isGranted && !rtc.isSharing
        view.needsLayout = true
    }
    static func dismantleNSView(_ view: ScreenCanvas, coordinator: ()) {
        if view.driving { view.rtc?.releaseHeldInputs() }
        view.video.track = nil
    }
}

@MainActor
final class ScreenCanvas: NSView {
    let video = VideoView()
    weak var rtc: RTCService?
    var driving = false { didSet { if !driving && oldValue { window?.makeFirstResponder(nil) } } }
    private var tracking: NSTrackingArea?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    init(rtc: RTCService) {
        self.rtc = rtc
        super.init(frame: .zero)
        video.layoutMode = .fit
        video.mirrorMode = .off
        addSubview(video)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func layout() { super.layout(); video.frame = bounds }
    override func hitTest(_ point: NSPoint) -> NSView? { bounds.contains(point) ? self : nil }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }
    private func normalized(_ event: NSEvent) -> CGPoint? {
        guard let dimensions = video.track?.dimensions, dimensions.width > 0, dimensions.height > 0 else { return nil }
        return ScreenCoordinateMapper.normalized(point: convert(event.locationInWindow, from: nil), container: bounds,
                                                  contentSize: CGSize(width: Int(dimensions.width), height: Int(dimensions.height)))
    }
    private func pointer(_ event: NSEvent) {
        guard driving, let point = normalized(event) else { return }
        rtc?.sendPointer(x: point.x, y: point.y)
    }
    override func mouseMoved(with event: NSEvent) { pointer(event) }
    override func mouseDragged(with event: NSEvent) { dragPointer(event) }
    override func rightMouseDragged(with event: NSEvent) { dragPointer(event) }
    override func otherMouseDragged(with event: NSEvent) { dragPointer(event) }
    private func dragPointer(_ event: NSEvent) {
        guard let point = normalized(event) else { return }
        rtc?.sendPointer(x: point.x, y: point.y)
    }
    override func mouseDown(with event: NSEvent) { press(event, down: true) }
    override func mouseUp(with event: NSEvent) { press(event, down: false) }
    override func rightMouseDown(with event: NSEvent) { press(event, down: true) }
    override func rightMouseUp(with event: NSEvent) { press(event, down: false) }
    override func otherMouseDown(with event: NSEvent) { press(event, down: true) }
    private func press(_ event: NSEvent, down: Bool) {
        guard let point = normalized(event), (0...2).contains(event.buttonNumber) else { return }
        window?.makeFirstResponder(self)
        rtc?.sendButton(button: event.buttonNumber, down: down, x: point.x, y: point.y)
    }
    override func scrollWheel(with event: NSEvent) {
        guard normalized(event) != nil else { return }
        rtc?.sendScroll(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY)
    }
    override func keyDown(with event: NSEvent) {
        guard let rtc else { return }
        if event.keyCode == 53 && event.modifierFlags.contains([.control, .option]) { rtc.emergencyStop(); return }
        rtc.sendKey(code: event.keyCode, down: true, modifiers: UInt64(event.modifierFlags.rawValue))
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        keyDown(with: event)
        return true
    }
    override func keyUp(with event: NSEvent) {
        guard rtc != nil else { return }
        rtc?.sendKey(code: event.keyCode, down: false, modifiers: UInt64(event.modifierFlags.rawValue))
    }
    override func flagsChanged(with event: NSEvent) {
        guard rtc != nil else { return }
        let flag: NSEvent.ModifierFlags
        switch event.keyCode {
        case 54, 55: flag = .command
        case 56, 60: flag = .shift
        case 58, 61: flag = .option
        case 59, 62: flag = .control
        case 57: flag = .capsLock
        default: return
        }
        rtc?.sendKey(code: event.keyCode, down: event.modifierFlags.contains(flag), modifiers: UInt64(event.modifierFlags.rawValue))
    }
    override func resignFirstResponder() -> Bool {
        if driving { rtc?.releaseHeldInputs() }
        return true
    }
}

enum ScreenCoordinateMapper {
    static func normalized(point: CGPoint, container: CGRect, contentSize: CGSize) -> CGPoint? {
        guard contentSize.width > 0, contentSize.height > 0, container.width > 0, container.height > 0,
              point.x.isFinite, point.y.isFinite else { return nil }
        let scale = min(container.width / contentSize.width, container.height / contentSize.height)
        let rect = CGRect(x: container.midX - contentSize.width * scale / 2,
                          y: container.midY - contentSize.height * scale / 2,
                          width: contentSize.width * scale, height: contentSize.height * scale)
        guard rect.contains(point) else { return nil }
        return CGPoint(x: (point.x - rect.minX) / rect.width, y: (point.y - rect.minY) / rect.height)
    }
}
