import AppKit
import Testing
@testable import PairDesk

@Suite(.serialized)
struct IncomingCallPresentationTests {
    private let me = TeamUser(id: "me", name: "Current user", email: "me@example.invalid")
    private let caller = TeamUser(id: "caller", name: "Alex Rivera", email: "alex@example.invalid")

    @MainActor
    private func store() -> AppStore {
        _ = NSApplication.shared
        let store = AppStore(callAudio: CallAudioFeedback { _ in nil })
        store.serverAddress = "snapshot.invalid"
        store.user = me
        return store
    }

    private func room(_ id: String = "room") -> PairRoom {
        PairRoom(id: id, name: "Direct call", participantCount: 2, participants: [me, caller])
    }

    private func request() -> CallJoinRequest {
        CallJoinRequest(id: "request", status: "pending", requester: caller, room: room(), expiresAt: "")
    }

    @Test @MainActor
    func testJoinRequestsAreActionableOnlyInTheirCurrentRoom() {
        let store = store()
        store.joinRequests = [request()]
        #expect(store.incomingJoinRequests.isEmpty, "A stale room snapshot must not prompt after leaving")
        store.activeRoom = room("another-room")
        #expect(store.incomingJoinRequests.isEmpty, "Do not admit someone to a different call")
        store.activeRoom = room()
        #expect(store.incomingJoinRequests.map(\.id) == ["request"])
        store.user = nil
        #expect(store.incomingJoinRequests.isEmpty)
    }

    @Test @MainActor
    func testIncomingWindowIsANonactivatingPanelThatSurvivesDeactivation() throws {
        let store = store()
        store.callInvitations = [CallInvitation(id: "call", status: "pending", caller: caller,
                                              target: me, room: room(), expiresAt: "")]
        let windows = AppWindows()
        let panel = windows.showIncomingCall(store: store)
        defer { windows.close("incoming") }
        #expect(panel is NSPanel, "A regular window cannot reliably accompany another app's full-screen Space")
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(!panel.hidesOnDeactivate)
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(windows.isShown("incoming"))
        #expect(panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(!panel.isKeyWindow, "Arrival must not steal keyboard focus")
    }

    @MainActor
    private func settle(until condition: () -> Bool) async throws {
        for _ in 0..<50 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition(), "Published state did not reach the popup")
    }

    @Test @MainActor
    func testInvitationBeforeSessionRestorationStillOpensThePopup() async throws {
        let store = store()
        store.user = nil
        store.callInvitations = [CallInvitation(id: "call", status: "pending", caller: caller,
                                              target: me, room: room(), expiresAt: "")]
        let windows = AppWindows()
        let presenter = IncomingCallPresenter(store: store, windows: windows)
        defer { windows.close("incoming") }
        #expect(!windows.isShown("incoming"))
        store.user = me
        try await settle { windows.isShown("incoming") }
        #expect(presenter.shownPromptID == "call-call")
        #expect(store.incomingCallPrompts.first?.person.name == "Alex Rivera")
    }

    @Test @MainActor
    func testJoinPopupAdvancesQueueWithoutReopeningOnRepeatedPolls() async throws {
        let store = store()
        store.activeRoom = room()
        let windows = AppWindows()
        let presenter = IncomingCallPresenter(store: store, windows: windows)
        defer { windows.close("incoming") }
        let other = TeamUser(id: "other", name: "Sam Lee", email: "sam@example.invalid")
        let second = CallJoinRequest(id: "second", status: "pending", requester: other, room: room(), expiresAt: "")
        store.joinRequests = [request(), second]
        try await settle { presenter.shownPromptID == "join-request" }
        #expect(windows.isShown("incoming"))
        #expect(store.incomingCallPrompts.first?.isJoinRequest == true)
        let panel = windows.showIncomingCall(store: store)
        panel.setFrameOrigin(NSPoint(x: 50, y: 50))
        let position = panel.frame.origin
        store.joinRequests = [request(), second]
        try await Task.sleep(for: .milliseconds(30))
        #expect(panel.frame.origin == position, "Polling must not repeatedly move the popup")
        store.joinRequests = [second]
        try await settle { presenter.shownPromptID == "join-second" }
        store.joinRequests = []
        try await settle { !windows.isShown("incoming") }
        #expect(presenter.shownPromptID == nil)
    }

    @Test @MainActor
    func testLeavingAndSigningOutCloseTheJoinPopup() async throws {
        let store = store()
        store.activeRoom = room()
        store.joinRequests = [request()]
        let windows = AppWindows()
        let presenter = IncomingCallPresenter(store: store, windows: windows)
        defer { windows.close("incoming") }
        #expect(windows.isShown("incoming"))
        store.activeRoom = nil
        try await settle { !windows.isShown("incoming") }
        store.activeRoom = room()
        try await settle { windows.isShown("incoming") }
        store.user = nil
        try await settle { !windows.isShown("incoming") }
        #expect(presenter.shownPromptID == nil)
    }

    @Test(arguments: ["accepted", "declined", "cancelled", "expired"]) @MainActor
    func testResolvedInvitationsAndJoinRequestsCloseThePopup(status: String) async throws {
        let store = store()
        store.callInvitations = [CallInvitation(id: "call", status: "pending", caller: caller,
                                              target: me, room: room(), expiresAt: "")]
        let windows = AppWindows()
        let presenter = IncomingCallPresenter(store: store, windows: windows)
        defer { windows.close("incoming") }
        #expect(windows.isShown("incoming"))
        store.callInvitations = [CallInvitation(id: "call", status: status, caller: caller,
                                              target: me, room: room(), expiresAt: "")]
        try await settle { !windows.isShown("incoming") }
        store.activeRoom = room()
        store.joinRequests = [request()]
        try await settle { windows.isShown("incoming") }
        store.joinRequests = [CallJoinRequest(id: "request", status: status, requester: caller,
                                             room: room(), expiresAt: "")]
        try await settle { !windows.isShown("incoming") }
        #expect(presenter.shownPromptID == nil)
    }

    @Test @MainActor
    func testOutgoingAndOtherRecipientsDoNotPrompt() {
        let store = store()
        store.callInvitations = [CallInvitation(id: "outgoing", status: "pending", caller: me,
                                              target: caller, room: room(), expiresAt: "")]
        #expect(store.incomingCallPrompts.isEmpty)
        store.activeRoom = room("another-room")
        store.joinRequests = [request()]
        #expect(store.incomingCallPrompts.isEmpty)
    }

    @Test @MainActor
    func testStalePopupActionCannotAffectAnotherCall() async throws {
        let store = store()
        store.activeRoom = room()
        store.joinRequests = [request()]
        let prompt = try #require(store.incomingCallPrompts.first)
        store.activeRoom = room("another-room")
        await store.respond(to: prompt, accepting: true)
        #expect(store.error == nil, "A stale click must not send an API request")
        #expect(store.activeRoom?.id == "another-room")
        #expect(!store.busy)
    }

    @Test(arguments: [true, false]) @MainActor
    func testFailedResponseKeepsThePopupAvailableForRetry(accepting: Bool) async throws {
        let store = store()
        let windows = AppWindows()
        let presenter = IncomingCallPresenter(store: store, windows: windows)
        defer { windows.close("incoming") }
        store.callInvitations = [CallInvitation(id: "call", status: "pending", caller: caller,
                                              target: me, room: room(), expiresAt: "")]
        try await settle { windows.isShown("incoming") }
        await store.respond(to: try #require(store.incomingCallPrompts.first), accepting: accepting)
        #expect(store.error != nil)
        #expect(!store.busy)
        #expect(windows.isShown("incoming"))
        #expect(presenter.shownPromptID == "call-call")

        store.error = nil
        store.activeRoom = room()
        store.joinRequests = [request()]
        try await settle { presenter.shownPromptID == "join-request" }
        await store.respond(to: try #require(store.incomingCallPrompts.first), accepting: accepting)
        #expect(store.error != nil)
        #expect(!store.busy)
        #expect(windows.isShown("incoming"))
        #expect(store.activeRoom?.id == "room")
    }
}
