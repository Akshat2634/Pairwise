import AppKit
import CoreGraphics

/// A local, click-through outline. It never activates PairDesk or steals keyboard focus.
@MainActor
final class ScreenShareIndicator {
    enum Target {
        case display(CGDirectDisplayID, crop: CGRect)
        case window(CGWindowID)
    }

    private(set) var panel: NSPanel?
    private var trackingTask: Task<Void, Never>?

    func show(_ target: Target) {
        hide()
        let panel = SharingBorderPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                       backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.sharingType = .none
        panel.animationBehavior = .none
        panel.contentView = SharingBorderView()
        self.panel = panel
        update(target)
        trackingTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
                guard let self else { return }
                self.update(target)
            }
        }
    }

    func hide() {
        trackingTask?.cancel()
        trackingTask = nil
        panel?.close()
        panel = nil
    }

    private func update(_ target: Target) {
        guard let panel, let primary = NSScreen.screens.first else { return }
        let bounds: CGRect?
        switch target {
        case .display(let id, let crop):
            if CGDisplayIsActive(id) != 0 {
                let display = CGDisplayBounds(id)
                bounds = crop.isEmpty ? display : crop.offsetBy(dx: display.minX, dy: display.minY)
            } else { bounds = nil }
        case .window(let id):
            // Query only the window explicitly chosen in the native picker.
            if let info = (CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]])?.first,
               (info[kCGWindowIsOnscreen as String] as? Bool) == true,
               let dictionary = info[kCGWindowBounds as String] as? NSDictionary {
                bounds = CGRect(dictionaryRepresentation: dictionary)
            } else { bounds = nil }
        }
        guard let bounds, !bounds.isEmpty, !bounds.isInfinite, !bounds.isNull else {
            panel.orderOut(nil)
            return
        }
        let frame = Self.appKitFrame(captureBounds: bounds, primaryScreenMaxY: primary.frame.maxY)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    /// Capture coordinates start at the primary display's top left; AppKit starts at its bottom left.
    static func appKitFrame(captureBounds: CGRect, primaryScreenMaxY: CGFloat) -> CGRect {
        CGRect(x: captureBounds.minX, y: primaryScreenMaxY - captureBounds.maxY,
               width: captureBounds.width, height: captureBounds.height)
    }
}

private final class SharingBorderPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class SharingBorderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let outline = NSBezierPath(rect: bounds.insetBy(dx: 2.5, dy: 2.5))
        NSColor.black.withAlphaComponent(0.8).setStroke()
        outline.lineWidth = 5
        outline.stroke()
        NSColor.systemRed.setStroke()
        outline.lineWidth = 3
        outline.stroke()
    }
}
