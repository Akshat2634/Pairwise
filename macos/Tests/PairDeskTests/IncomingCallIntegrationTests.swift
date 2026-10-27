import AppKit
import Testing
@testable import PairDesk

@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["PAIRDESK_TEST_API"] != nil,
                            "Run scripts/test-call.sh for API, media, and popup integration"))
struct IncomingCallIntegrationTests {
    @MainActor
    private func withClients(_ run: ([AppStore]) async throws -> Void) async throws {
        _ = NSApplication.shared
        let address = try #require(ProcessInfo.processInfo.environment["PAIRDESK_TEST_API"])
        let password = try #require(ProcessInfo.processInfo.environment["PAIRDESK_TEST_PASSWORD"])
        let savedMuted = UserDefaults.standard.object(forKey: "startCallsMuted")
        defer { UserDefaults.standard.set(savedMuted, forKey: "startCallsMuted") }
        struct LoginBody: Encodable { let email: String; let password: String }
        let api = try APIClient(server: address)
        var stores: [AppStore] = []
        for i in 1...4 {
            let login: LoginResponse = try await api.post("v1/login", body: LoginBody(
                email: "integration-notification-\(i)@pairdesk.invalid", password: password))
            let store = AppStore(callAudio: CallAudioFeedback { _ in nil })
            store.debugUseSession(user: login.user, token: login.token, server: address)
            store.startCallsMuted = true
            stores.append(store)
        }
        do {
            // Publish everyone's presence before any client reads the roster.
            for store in stores { try await store.api.send("v1/heartbeat", body: EmptyBody()) }
            for store in stores { await store.refresh() }
            try await run(stores)
        } catch {
            for store in stores { await store.leave() }
            throw error
        }
        for store in stores { await store.leave() }
    }

    @MainActor
    private func settle(until condition: () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(condition(), "Call state did not settle")
    }

    @Test @MainActor
    func testIdlePopupAcceptDeclineAndCallerCancellation() async throws {
        try await withClients { clients in
            let caller = clients[0], recipient = clients[1]
            let windows = AppWindows()
            let presenter = IncomingCallPresenter(store: recipient, windows: windows)
            defer { windows.close("incoming") }
            let person = try #require(caller.users.first { $0.id == recipient.user?.id })

            await caller.call(person)
            #expect(caller.error == nil)
            _ = try #require(caller.activeRoom)
            await recipient.refreshInvitations()
            try await settle { windows.isShown("incoming") }
            let prompt = try #require(recipient.incomingCallPrompts.first)
            #expect(prompt.person.name == caller.user?.name)
            #expect(!prompt.isJoinRequest)
            await recipient.respond(to: prompt, accepting: true)
            #expect(recipient.error == nil)
            #expect(recipient.rtc.connected)
            #expect(recipient.activeRoom?.id == caller.activeRoom?.id)
            try await settle { !windows.isShown("incoming") }
            await recipient.leave()
            await caller.leave()

            await caller.refresh()
            await recipient.refresh()
            await caller.call(person)
            await recipient.refreshInvitations()
            try await settle { windows.isShown("incoming") }
            let declined = try #require(recipient.incomingCallPrompts.first)
            await recipient.respond(to: declined, accepting: false)
            try await settle { !windows.isShown("incoming") }
            #expect(recipient.activeRoom == nil)
            #expect(!recipient.rtc.connected)
            await caller.refreshInvitations()
            await caller.leave()

            await caller.refresh()
            await recipient.refresh()
            await caller.call(person)
            await recipient.refreshInvitations()
            try await settle { windows.isShown("incoming") }
            let cancelled = try #require(caller.outgoingCalls.first)
            await caller.cancelCall(cancelled)
            await recipient.refreshInvitations()
            try await settle { !windows.isShown("incoming") }
            #expect(presenter.shownPromptID == nil)
        }
    }

    @Test @MainActor
    func testActiveCallPopupDeclineCancelAndAcceptWithoutReplacingCall() async throws {
        try await withClients { clients in
            let host = clients[0], peer = clients[1], requester = clients[2], other = clients[3]
            let peerPerson = try #require(host.users.first { $0.id == peer.user?.id })
            await host.call(peerPerson)
            #expect(host.error == nil)
            _ = try #require(host.activeRoom)
            await peer.refreshInvitations()
            await peer.acceptCall(try #require(peer.incomingCall))
            let room = try #require(host.activeRoom)
            let hostWindows = AppWindows(), peerWindows = AppWindows()
            let hostPresenter = IncomingCallPresenter(store: host, windows: hostWindows)
            let peerPresenter = IncomingCallPresenter(store: peer, windows: peerWindows)
            defer { hostWindows.close("incoming"); peerWindows.close("incoming") }

            await requester.requestToJoin(room)
            await host.refreshInvitations()
            await peer.refreshInvitations()
            try await settle { hostWindows.isShown("incoming") && peerWindows.isShown("incoming") }
            let declined = try #require(host.incomingCallPrompts.first)
            #expect(declined.isJoinRequest)
            #expect(declined.person.name == requester.user?.name)
            await host.respond(to: declined, accepting: false)
            await peer.refreshInvitations()
            try await settle { !hostWindows.isShown("incoming") && !peerWindows.isShown("incoming") }
            #expect(host.activeRoom?.id == room.id)
            #expect(host.rtc.connected && peer.rtc.connected)
            #expect(requester.activeRoom == nil)

            await requester.requestToJoin(room)
            await host.refreshInvitations()
            try await settle { hostWindows.isShown("incoming") }
            await requester.cancelJoinRequest(try #require(requester.outgoingJoinRequests.first))
            await host.refreshInvitations()
            try await settle { !hostWindows.isShown("incoming") }

            await other.requestToJoin(room)
            await requester.requestToJoin(room)
            await host.refreshInvitations()
            await peer.refreshInvitations()
            #expect(host.incomingCallPrompts.count == 2)
            let accepted = try #require(peer.incomingCallPrompts.first)
            #expect(accepted.person.id == requester.user?.id, "Respond to the request actually displayed by the popup")
            await peer.respond(to: accepted, accepting: true)
            #expect(peer.error == nil)
            await requester.refreshInvitations()
            #expect(requester.rtc.connected, "Requester must join after acceptance")
            #expect(requester.activeRoom?.id == room.id)
            await host.refreshInvitations()
            try await settle { hostPresenter.shownPromptID != accepted.id && peerPresenter.shownPromptID != accepted.id }
            #expect(host.incomingCallPrompts.count == 1)
            #expect(host.activeRoom?.id == room.id && peer.activeRoom?.id == room.id)
            #expect(host.rtc.connected && peer.rtc.connected)
            let remaining = try #require(host.incomingCallPrompts.first)
            await host.respond(to: remaining, accepting: false)
            await peer.refreshInvitations()
            try await settle { !hostWindows.isShown("incoming") && !peerWindows.isShown("incoming") }
        }
    }

    @Test @MainActor
    func testApprovalWhileBusyConnectsAfterwardsAndDoesNotRejoinAfterLeaving() async throws {
        try await withClients { clients in
            let host = clients[0], peer = clients[1], requester = clients[2]
            await host.call(try #require(host.users.first { $0.id == peer.user?.id }))
            await peer.refreshInvitations()
            await peer.acceptCall(try #require(peer.incomingCall))
            let room = try #require(host.activeRoom)
            await requester.requestToJoin(room)
            requester.busy = true
            await peer.refreshInvitations()
            await peer.acceptJoinRequest(try #require(peer.incomingJoinRequests.first))
            await requester.refreshInvitations()
            #expect(requester.activeRoom == nil)
            requester.busy = false
            try await settle { requester.activeRoom?.id == room.id }
            #expect(requester.rtc.connected)
            await requester.leave()
            await requester.refreshInvitations()
            try await Task.sleep(for: .milliseconds(100))
            #expect(requester.activeRoom == nil)
            #expect(!requester.rtc.connected)
        }
    }

    @Test @MainActor
    func testJoinedParticipantsKeepTheCallWhenBothOriginalParticipantsLeave() async throws {
        try await withClients { clients in
            let host = clients[0], peer = clients[1]
            await host.call(try #require(host.users.first { $0.id == peer.user?.id }))
            await peer.refreshInvitations()
            await peer.acceptCall(try #require(peer.incomingCall))
            let room = try #require(host.activeRoom)
            for requester in clients.suffix(2) {
                await requester.requestToJoin(room)
                await host.refreshInvitations()
                await host.acceptJoinRequest(try #require(host.incomingJoinRequests.first))
                await requester.refreshInvitations()
                try await settle { requester.activeRoom?.id == room.id }
            }
            try await settle { clients[2].rtc.participants.count == 4 && clients[3].rtc.participants.count == 4 }
            await host.leave()
            await peer.leave()
            for remaining in clients.suffix(2) {
                await remaining.refreshInvitations()
                await remaining.refresh()
                #expect(remaining.activeRoom?.id == room.id)
                #expect(remaining.rtc.connected)
            }
            try await settle { clients[2].rtc.participants.count == 2 && clients[3].rtc.participants.count == 2 }
        }
    }
}
