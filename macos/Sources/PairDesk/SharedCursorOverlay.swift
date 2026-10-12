import AppKit
import SwiftUI

/// A click-through overlay on the sharing Mac. It is intentionally included in
/// the display's video, so everyone sees the same named pointers. It never
/// becomes key, activates PairDesk, or intercepts input in the app being shared.
@MainActor
final class SharedCursorOverlay {
    private var panel: CursorPanel?
    private var host: NSHostingView<SharedCursorLayer>?
    private var bounds: CGRect?

    func show(in bounds: CGRect) {
        hide()
        guard bounds.width > 0, bounds.height > 0 else { return }
        self.bounds = bounds
        let frame = IndependentCursorPolicy.appKitFrame(for: bounds, primaryScreenTop: NSScreen.screens.first?.frame.maxY ?? bounds.maxY)
        let panel = CursorPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let host = NSHostingView(rootView: SharedCursorLayer(pointers: [], names: [:]))
        host.frame = NSRect(origin: .zero, size: frame.size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        self.host = host
        self.panel = panel
        panel.orderFrontRegardless()
    }

    func update(pointers: [RemotePointer], names: [String: String]) {
        guard bounds != nil else { return }
        host?.rootView = SharedCursorLayer(pointers: pointers, names: names)
    }

    func hide() {
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        host = nil
        bounds = nil
    }
}

private final class CursorPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct SharedCursorLayer: View {
    let pointers: [RemotePointer]
    let names: [String: String]

    var body: some View {
        GeometryReader { geometry in
            let colors = Theme.distinctPersonColors(for: pointers.map(\.id))
            ForEach(pointers) { pointer in
                let point = CGPoint(x: pointer.x * geometry.size.width, y: pointer.y * geometry.size.height)
                let color = colors[pointer.id] ?? Theme.personColor(for: pointer.id)
                CursorArrow().fill(color)
                    .overlay(CursorArrow().stroke(.white.opacity(0.95), lineWidth: 1.3))
                    .frame(width: 18, height: 25)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    // Arrow tip, rather than the label's centre, is the hotspot.
                    .position(x: point.x + 9, y: point.y + 12.5)
                Text(names[pointer.id] ?? "Teammate")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .frame(maxWidth: 140)
                    .background(color, in: RoundedRectangle(cornerRadius: 5))
                    .fixedSize(horizontal: true, vertical: false)
                    .position(x: min(max(point.x + 58, 70), max(70, geometry.size.width - 70)),
                              y: min(point.y + 32, geometry.size.height - 12))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct CursorArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let points: [CGPoint] = [.init(x: 0, y: 0), .init(x: 0, y: 19), .init(x: 5, y: 15),
                                 .init(x: 9, y: 25), .init(x: 13, y: 23), .init(x: 9, y: 14),
                                 .init(x: 18, y: 14)]
        path.addLines(points.map { CGPoint(x: $0.x * rect.width / 18, y: $0.y * rect.height / 25) })
        path.closeSubpath()
        return path
    }
}
