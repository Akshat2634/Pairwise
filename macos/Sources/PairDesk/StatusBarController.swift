import AppKit
import Combine
import SwiftUI

/// The menu bar presence, built on AppKit like Tuple's: a status item whose
/// popover AppKit keeps attached to it, can be opened from the Dock, and a
/// mute button that sits beside the icon during calls. SwiftUI's MenuBarExtra
/// offers none of those.
@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private(set) static var shared: StatusBarController?

    private let store: AppStore
    private let rtc: RTCService
    private let item: NSStatusItem
    private var muteItem: NSStatusItem?
    private let popover = NSPopover()
    private let popoverBackground = SurfaceView()
    private var subscriptions = Set<AnyCancellable>()

    init(store: AppStore, rtc: RTCService, loginItem: LoginItemManager) {
        self.store = store
        self.rtc = rtc
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        item.button?.toolTip = "PairDesk"

        let content = NSHostingController(rootView: MenuBarPanel(store: store, rtc: rtc, loginItem: loginItem))
        content.sizingOptions = [.preferredContentSize]
        popover.contentViewController = content
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        // @Published emits before the value lands; hop once so reads see the new state.
        Publishers.Merge(store.$callInvitations.map { _ in () }, store.$activeRoom.map { _ in () })
            .sink { [weak self] in Task { @MainActor [weak self] in self?.refreshIcon() } }
            .store(in: &subscriptions)
        Publishers.Merge(store.$activeRoom.map { _ in () }, rtc.$isMicrophoneEnabled.map { _ in () })
            .sink { [weak self] in Task { @MainActor [weak self] in self?.refreshMuteItem() } }
            .store(in: &subscriptions)
        refreshIcon()
        refreshMuteItem()
        Self.shared = self
    }

    func showPopover() {
        guard let button = item.button, !popover.isShown else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func closePopover() { popover.performClose(nil) }

    @objc private func togglePopover() {
        if popover.isShown { closePopover() } else { showPopover() }
    }

    @objc private func toggleMute() {
        let enable = !rtc.isMicrophoneEnabled
        Task { @MainActor in
            do { try await store.setMicrophoneEnabled(enable) }
            catch { store.error = error.localizedDescription }
        }
    }

    private func refreshIcon() {
        let symbol = store.incomingCall != nil ? "phone.arrow.down.left" : (store.activeRoom != nil ? "phone.fill" : "rectangle.on.rectangle")
        item.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "PairDesk")
    }

    /// Status items created later sit to the left of earlier ones, so the mute
    /// button appears beside the PairDesk icon for the duration of a call.
    private func refreshMuteItem() {
        guard store.activeRoom != nil else {
            if let muteItem { NSStatusBar.system.removeStatusItem(muteItem) }
            muteItem = nil
            return
        }
        if muteItem == nil {
            let created = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            created.button?.target = self
            created.button?.action = #selector(toggleMute)
            muteItem = created
        }
        let micOn = rtc.isMicrophoneEnabled
        muteItem?.button?.image = NSImage(systemSymbolName: micOn ? "mic.fill" : "mic.slash.fill", accessibilityDescription: micOn ? "Mute" : "Unmute")
        muteItem?.button?.contentTintColor = micOn ? nil : NSColor(Theme.attention)
        muteItem?.button?.toolTip = micOn ? "Mute microphone" : "Unmute microphone"
    }

    // MARK: NSPopoverDelegate

    /// Paint the popover frame, arrow included, in the panel's surface color
    /// so the panel reads as one shape.
    func popoverDidShow(_ notification: Notification) {
        guard popoverBackground.superview == nil,
              let frameView = popover.contentViewController?.view.window?.contentView?.superview else { return }
        popoverBackground.frame = frameView.bounds
        popoverBackground.autoresizingMask = [.width, .height]
        frameView.addSubview(popoverBackground, positioned: .below, relativeTo: frameView.subviews.first)
    }
}

/// A view filled with Theme.surface that follows appearance changes.
private final class SurfaceView: NSView {
    override var wantsUpdateLayer: Bool { true }
    override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); wantsLayer = true }
    override func updateLayer() { layer?.backgroundColor = NSColor(Theme.surface).cgColor }
}
