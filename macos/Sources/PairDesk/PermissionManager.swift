import AppKit
import AVFoundation
import ApplicationServices
import Security
import SwiftUI

enum AppCopyLocation: Equatable {
    case applications
    case diskImage
    case other(String)

    static func classify(bundleURL: URL, homeDirectory: URL) -> AppCopyLocation {
        let bundlePath = bundleURL.standardizedFileURL.path
        if bundlePath.hasPrefix("/Volumes/") { return .diskImage }
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            homeDirectory.appendingPathComponent("Applications", isDirectory: true)
        ]
        if roots.contains(where: { bundlePath.hasPrefix($0.standardizedFileURL.path + "/") }) {
            return .applications
        }
        return .other(bundlePath)
    }

    var guidance: String {
        switch self {
        case .applications:
            return "PairDesk is running from an Applications folder."
        case .diskImage:
            return "PairDesk is running from a mounted disk image. Drag it to Applications, eject the image, and open the Applications copy."
        case .other(let path):
            return "This copy is outside Applications: \(path). For normal team use, keep one copy in Applications and open that copy."
        }
    }
}

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
    private var appCopyLocation: AppCopyLocation {
        AppCopyLocation.classify(bundleURL: Bundle.main.bundleURL, homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
    }
    private var signingSummary: String {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &code) == errSecSuccess,
              let code else { return "Signature status unavailable" }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let values = information as? [String: Any] else { return "Signature status unavailable" }
        let identifier = values[kSecCodeInfoIdentifier as String] as? String ?? Bundle.main.bundleIdentifier ?? "unknown"
        if let team = values[kSecCodeInfoTeamIdentifier as String] as? String {
            return "\(identifier) · Apple team \(team)"
        }
        return "\(identifier) · no Apple Developer team"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Privacy and access").font(.title2.bold())
            Text("Pairwise asks for access only when you use the related feature. You can call and view a teammate's screen without enabling remote control.").foregroundStyle(.secondary)
            Label("Voice · Microphone access is needed to talk. You can still join and listen without it.", systemImage: permissions.microphone ? "checkmark.circle.fill" : "mic")
                .font(.callout).foregroundStyle(permissions.microphone ? Color.green : Color.primary)
            Label("Screen sharing · Choose a display in Apple's picker each time. No separate Screen Recording setting is needed.", systemImage: "display")
                .font(.callout).foregroundStyle(.secondary)
            Label("Remote control · Accessibility is optional and is needed only on the Mac being controlled.", systemImage: permissions.accessibility ? "checkmark.circle.fill" : "cursorarrow.motionlines")
                .font(.callout).foregroundStyle(permissions.accessibility ? Color.green : Color.primary)
            row("Microphone", detail: "Allow Pairwise to send your voice during a call.", ready: permissions.microphone) { if permissions.microphone { permissions.open("Privacy_Microphone") } else { Task { await permissions.requestMicrophone() } } }
            row("Remote control", detail: "Allow a teammate to use mouse and keyboard while you share your display. You can stop control at any time.", ready: permissions.accessibility) { if permissions.accessibility { permissions.open("Privacy_Accessibility") } else { permissions.requestAccessibility() } }
            Text("Settings labels and placement vary by macOS version. If the Accessibility page does not open directly, search System Settings for ‘Accessibility’ and find the list of apps allowed to control your Mac.").font(.caption).foregroundStyle(.secondary)
            Text("Stop remote control in the menu bar or press Control–Option–Escape at any time. If you enable Accessibility while sharing a display, return to PairDesk; control becomes available automatically.").font(.caption)
            Text("If System Settings shows PairDesk as enabled but input still does not work, check that the enabled entry matches the copy in Applications. Remove any stale PairDesk entry and add the Applications copy, then quit and reopen PairDesk. Development builds may need permission approval again after an update.").font(.caption).foregroundStyle(.secondary)
            Text("App signature: \(signingSummary)").font(.caption.monospaced()).textSelection(.enabled)
            Text(appCopyLocation.guidance).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Text("Development builds are ad-hoc signed and may need fresh approval after an update. A stable Developer ID signed release is required for normal distribution.").font(.caption).foregroundStyle(.secondary)
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
