import AppKit
import AVFoundation
import ApplicationServices
import SwiftUI

@MainActor
final class PermissionManager: ObservableObject {
    static let shared = PermissionManager()
    private var requestedAccessibility = false
    @Published private(set) var microphone = false
    @Published private(set) var accessibility = false
    init() { refresh() }
    func refresh() {
        microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibility = AXIsProcessTrusted()
    }
    func requestMicrophone() async {
        refresh()
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        } else { open("Privacy_Microphone") }
        refresh()
    }
    func requestAccessibility() {
        refresh()
        if !accessibility && !requestedAccessibility {
            requestedAccessibility = true
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        open("Privacy_Accessibility")
        refresh()
    }
    func open(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        if !NSWorkspace.shared.open(url) { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app")) }
    }
}

struct PermissionsView: View {
    @ObservedObject private var permissions = PermissionManager.shared
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Set up PairDesk").font(.title2.bold())
            Text("Screen sharing uses the macOS picker and does not require Screen Recording permission. Microphone access is used only when you join voice. Accessibility access enables optional remote mouse and keyboard control.").foregroundStyle(.secondary)
            row("Microphone", detail: "Talk with your teammates.", ready: permissions.microphone) { if permissions.microphone { permissions.open("Privacy_Microphone") } else { Task { await permissions.requestMicrophone() } } }
            row("Control your Mac", detail: "Allow teammates to control your shared display. Enable PairDesk in the app permission list named Accessibility.", ready: permissions.accessibility) { if permissions.accessibility { permissions.open("Privacy_Accessibility") } else { permissions.requestAccessibility() } }
            Text("Settings labels and placement vary by macOS version. If the Accessibility page does not open directly, search System Settings for ‘Accessibility’ and find the list of apps allowed to control your Mac.").font(.caption).foregroundStyle(.secondary)
            Text("Stop remote control in the menu bar or press Control–Option–Escape at any time.").font(.caption)
            Text("Running app: \(Bundle.main.bundleURL.path)").font(.caption).textSelection(.enabled)
            Text("Ad-hoc signed test updates can require fresh permission approval. Use the installed copy in Applications; avoid running another copy from the disk image.").font(.caption).foregroundStyle(.secondary)
            HStack { Button("Check again") { permissions.refresh() }; Spacer(); Button("Done") { PermissionWindowController.shared.close(); dismiss() } }
        }.padding(26).frame(width: 490)
        .task {
            while !Task.isCancelled {
                permissions.refresh()
                do { try await Task.sleep(for: .seconds(2)) } catch { break }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in permissions.refresh() }
    }
    private func row(_ title: String, detail: String, ready: Bool, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: ready ? "checkmark.circle.fill" : "circle").foregroundStyle(ready ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 5) { Text(title).bold(); Text(detail).font(.caption).foregroundStyle(.secondary) }
            Spacer()
            Button(ready ? "Settings" : "Allow", action: action)
        }
    }
}

// Retain a standalone window so permission setup is reachable from an accessory
// menu-bar app even when SwiftUI's menu popover is closing.
@MainActor
final class PermissionWindowController {
    static let shared = PermissionWindowController()
    private var window: NSWindow?
    func close() { window?.orderOut(nil) }
    func show() {
        PermissionManager.shared.refresh()
        if window == nil {
            let controller = NSHostingController(rootView: PermissionsView())
            let created = NSWindow(contentViewController: controller)
            created.title = "PairDesk permissions"
            created.styleMask = [.titled, .closable]
            created.isReleasedWhenClosed = false
            created.center()
            window = created
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
