import AppKit
import Testing
@testable import PairDesk

@Suite(.serialized)
struct GroupCallInvitationTests {
    private let a = TeamUser(id: "a", name: "Alex", email: "a@example.invalid", online: true, busy: false)
    private let b = TeamUser(id: "b", name: "Blair", email: "b@example.invalid", online: true, busy: false)
    private let c = TeamUser(id: "c", name: "Casey", email: "c@example.invalid", online: true, busy: false)
    private let d = TeamUser(id: "d", name: "Drew", email: "d@example.invalid", online: true, busy: false)
    private var room: PairRoom { PairRoom(id: "room", name: "Group call", participantCount: 2, participants: [a, b]) }

    @MainActor private func store() -> AppStore {
        _ = NSApplication.shared
        let store = AppStore(callAudio: CallAudioFeedback { _ in nil })
        store.serverAddress = "snapshot.invalid"
        store.user = b
        store.users = [a, b, c, d]
        store.activeRoom = room
        store.rtc.debugSetCall(participants: [CallParticipant(identity: "a", name: "Alex", isLocal: false),
                                             CallParticipant(identity: "b", name: "Blair", isLocal: true)], microphoneEnabled: false)
        return store
    }

    private func invite(_ id: String, caller: TeamUser, target: TeamUser, status: String = "pending", room: PairRoom? = nil) -> CallInvitation {
        CallInvitation(id: id, status: status, caller: caller, target: target, room: room ?? self.room, expiresAt: "")
    }

    @Test @MainActor
    func anotherMembersInviteAppearsWithoutBecomingMyOutgoingOrIncomingCall() {
        let store = store()
        store.callInvitations = [invite("a-c", caller: a, target: c)]
        #expect(store.pendingCallInvitations.map(\.target.id) == ["c"])
        #expect(store.outgoingCalls.isEmpty)
        #expect(store.incomingCall == nil)
        #expect(store.incomingCallPrompts.isEmpty)
        #expect(!store.availablePeople.contains { $0.id == "c" }, "A stale directory must not offer an already-invited person")
        let invitation = store.callInvitations[0]
        #expect(invitation.pendingParticipantLabel(viewerID: "b") == "Calling… · invited by Alex")
        #expect(!invitation.canCancelPendingInvitation(userID: "b"))
        #expect(invitation.canCancelPendingInvitation(userID: "a"))
    }

    @Test @MainActor
    func allMembersPendingInvitesReserveSeats() {
        let store = store()
        store.callInvitations = [invite("a-c", caller: a, target: c), invite("b-d", caller: b, target: d)]
        #expect(store.pendingCallInvitations.count == 2)
        #expect(!store.canAddPerson)
    }

    @Test @MainActor
    func acceptedInviteRemainsVisibleUntilThePersonJoinsMedia() throws {
        let store = store()
        store.callInvitations = [invite("a-c", caller: a, target: c, status: "accepted")]
        #expect(store.pendingCallInvitations.first?.status == "accepted")
        let invitation = try #require(store.pendingCallInvitations.first)
        #expect(invitation.pendingParticipantLabel(viewerID: "b") == "Joining… · invited by Alex")
        #expect(!invitation.canCancelPendingInvitation(userID: "a"))
        store.rtc.debugSetCall(participants: [CallParticipant(identity: "a", name: "Alex", isLocal: false),
                                             CallParticipant(identity: "b", name: "Blair", isLocal: true),
                                             CallParticipant(identity: "c", name: "Casey", isLocal: false)], microphoneEnabled: false)
        #expect(store.pendingCallInvitations.isEmpty, "Joined participants must not appear twice")
    }

    @Test @MainActor
    func terminalOtherRoomAndEndedCallInvitesDoNotAppear() {
        let store = store()
        store.callInvitations = [invite("declined", caller: b, target: c, status: "declined"),
                                 invite("other", caller: b, target: d,
                                        room: PairRoom(id: "other", name: "Other call", participantCount: 1, participants: [b]))]
        #expect(store.pendingCallInvitations.isEmpty)
        store.callInvitations = [invite("b-d", caller: b, target: d)]
        store.activeRoom = nil
        #expect(store.pendingCallInvitations.isEmpty)
    }
}
