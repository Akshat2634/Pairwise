import SwiftUI
import AppKit
import Combine

extension Notification.Name {
    /// Posted when the person clicks the Dock icon, which exists only during a call.
    static let pairDeskReopen = Notification.Name("app.internal.pairdesk.reopen")
}

@MainActor
final class AppRuntime {
    static let shared = AppRuntime()
    let store = AppStore()
    let loginItem = LoginItemManager()
    private var started = false
    var suppressInitialWindow = true
    func start() {
        guard !started else { return }
        started = true
        loginItem.prepareInstalledApp()
        Task { await store.restore() }
    }
}

@main
struct PairDeskApp: App {
    @NSApplicationDelegateAdaptor(PairDeskDelegate.self) private var delegate
    @StateObject private var store = AppRuntime.shared.store
    @StateObject private var loginItem = AppRuntime.shared.loginItem
    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel(store: store, rtc: store.rtc, loginItem: loginItem)
        } label: { MenuBarStatusLabel(store: store, rtc: store.rtc) }
        .menuBarExtraStyle(.window)
        Window("PairDesk", id: "main") {
            RootView(store: store).environmentObject(loginItem).preferredColorScheme(.dark)
                .background(InitialWindowHider())
        }.windowStyle(.hiddenTitleBar).windowResizability(.contentSize)
        Window("PairDesk · Shared screen", id: "screen") {
            SharedScreenWindow(store: store, rtc: store.rtc, transcripts: store.transcripts).frame(minWidth: 700, minHeight: 450).preferredColorScheme(.dark)
        }.defaultSize(width: 1440, height: 900)
        Window("Share your screen", id: "share") { ScreenSharePickerView(store: store).preferredColorScheme(.dark) }
            .windowResizability(.contentSize)
        Window("PairDesk permissions", id: "permissions") { PermissionsView().preferredColorScheme(.dark) }
            .windowResizability(.contentSize)
        Window("PairDesk account", id: "account") {
            AccountView(store: store).environmentObject(loginItem).preferredColorScheme(.dark)
        }.windowResizability(.contentSize)
        Window("Incoming PairDesk call", id: "incoming") { IncomingCallView(store: store).preferredColorScheme(.dark) }
            .windowResizability(.contentSize)
            .commands {
                CommandGroup(after: .appSettings) {
                    Toggle("Start at login", isOn: Binding(get: { loginItem.enabled }, set: { loginItem.setEnabled($0) }))
                }
                CommandGroup(after: .newItem) {
                    Button("Stop Remote Control") { store.rtc.revokeControl() }.keyboardShortcut(.escape, modifiers: [.control, .option])
                }
            }
    }
}

@MainActor
final class PairDeskDelegate: NSObject, NSApplicationDelegate {
    var store: AppStore { AppRuntime.shared.store }
    private var dockPresence: AnyCancellable?
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Accessory mode and LSUIElement keep calling in the menu bar. Like
        // Tuple, the Dock icon appears only while a call is active, so the
        // call is reachable with Cmd-Tab and the icon is a reminder it's on.
        NSApp.setActivationPolicy(.accessory)
        dockPresence = store.$activeRoom.map { $0 != nil }.removeDuplicates().sink { inCall in
            NSApp.setActivationPolicy(inCall ? .regular : .accessory)
        }
        #if DEBUG
        if let directory = ProcessInfo.processInfo.environment["PAIRDESK_SNAPSHOT_DIR"] {
            UISnapshots.render(to: URL(fileURLWithPath: directory, isDirectory: true))
            exit(0)
        }
        #endif
        AppRuntime.shared.start()

    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard store.activeRoom != nil else { return .terminateNow }
        Task { await store.leave(); sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NotificationCenter.default.post(name: .pairDeskReopen, object: nil)
        return false
    }
}

private struct InitialWindowHider: NSViewRepresentable {
    func makeNSView(context: Context) -> InitialWindowView { InitialWindowView() }
    func updateNSView(_ nsView: InitialWindowView, context: Context) {}
}
@MainActor
private final class InitialWindowView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window, AppRuntime.shared.suppressInitialWindow else { return }
        AppRuntime.shared.suppressInitialWindow = false
        DispatchQueue.main.async { window.orderOut(nil) }
    }
}
