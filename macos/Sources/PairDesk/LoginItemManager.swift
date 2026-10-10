import AppKit
import Combine
import Foundation
import ServiceManagement

@MainActor
final class LoginItemManager: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var needsApproval = false
    @Published private(set) var message: String?

    func prepareInstalledApp() {
        refresh()
        let path = Bundle.main.bundleURL.resolvingSymlinksInPath().path
        let userApplications = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path + "/"
        guard path.hasPrefix("/Applications/") || path.hasPrefix(userApplications) else {
            message = "Move PairDesk to Applications and open it there to enable automatic startup."
            return
        }
        guard !UserDefaults.standard.bool(forKey: "loginItemInitiallyConfigured") else { return }
        UserDefaults.standard.set(true, forKey: "loginItemInitiallyConfigured")
        setEnabled(true)
    }

    func refresh() {
        enabled = SMAppService.mainApp.status == .enabled
        needsApproval = SMAppService.mainApp.status == .requiresApproval
    }

    func setEnabled(_ value: Bool) {
        do {
            if value { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            message = nil
        } catch {
            message = "Could not change automatic startup: \(error.localizedDescription)"
        }
        UserDefaults.standard.set(true, forKey: "loginItemInitiallyConfigured")
        refresh()
        if needsApproval { message = "Approve PairDesk in System Settings → General → Login Items." }
    }

    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
