import AppKit
import AVFoundation
import Testing
@testable import PairDesk

@MainActor
final class CallEventTone: CallTonePlaying {
    var numberOfLoops = 0
    var plays = 0
    var stops = 0
    func play() -> Bool { plays += 1; return true }
    func stop() { stops += 1 }
}

@Suite(.serialized)
struct CallEventFeedbackTests {
    @Test @MainActor
    func declineSoundsOnceForCallerAndRecipientButNotObserversOrHistory() {
        _ = NSApplication.shared
        let saved = UserDefaults.standard.object(forKey: "playCallSounds")
        defer { UserDefaults.standard.set(saved, forKey: "playCallSounds") }
        let a = TeamUser(id: "a", name: "Alex", email: "a@example.invalid")
        let b = TeamUser(id: "b", name: "Blair", email: "b@example.invalid")
        let c = TeamUser(id: "c", name: "Casey", email: "c@example.invalid")
        let room = PairRoom(id: "room", name: "Call", participantCount: 2, participants: [a, c])
        func invitation(_ status: String) -> CallInvitation {
            CallInvitation(id: "call", status: status, caller: a, target: b, room: room, expiresAt: "")
        }
        for viewer in [a, b, c] {
            let end = CallEventTone()
            let store = AppStore(callAudio: CallAudioFeedback { $0 == .disconnected ? end : nil })
            store.serverAddress = "snapshot.invalid"
            store.user = viewer
            store.playCallSounds = true
            store.callInvitations = [invitation("declined")]
            #expect(end.plays == 0, "History must stay silent")
            store.callInvitations = [invitation("pending")]
            store.callInvitations = [invitation("declined")]
            store.callInvitations = [invitation("declined")]
            #expect(end.plays == (viewer.id == c.id ? 0 : 1))
            for status in ["cancelled", "expired", "accepted"] {
                store.callInvitations = [invitation("pending")]
                store.callInvitations = [invitation(status)]
            }
            #expect(end.plays == (viewer.id == c.id ? 0 : 1))
            store.playCallSounds = false
            store.callInvitations = [invitation("pending")]
            store.callInvitations = [invitation("declined")]
            store.playCallSounds = true
            #expect(end.plays == (viewer.id == c.id ? 0 : 1), "Enabling sounds must not replay an old decline")
        }
    }

    @Test @MainActor
    func joinRequestDeclineSoundsOnlyForTheRequesterOnRefresh() {
        _ = NSApplication.shared
        let saved = UserDefaults.standard.object(forKey: "playCallSounds")
        defer { UserDefaults.standard.set(saved, forKey: "playCallSounds") }
        let requester = TeamUser(id: "a", name: "Alex", email: "a@example.invalid")
        let member = TeamUser(id: "b", name: "Blair", email: "b@example.invalid")
        let room = PairRoom(id: "room", name: "Group", participantCount: 2, participants: [member])
        for viewer in [requester, member] {
            let end = CallEventTone()
            let store = AppStore(callAudio: CallAudioFeedback { $0 == .disconnected ? end : nil })
            store.user = viewer
            store.playCallSounds = true
            func request(_ status: String) -> CallJoinRequest {
                CallJoinRequest(id: "request", status: status, requester: requester, room: room, expiresAt: "")
            }
            store.joinRequests = [request("declined")]
            #expect(end.plays == 0)
            store.joinRequests = [request("pending")]
            store.joinRequests = [request("declined")]
            store.joinRequests = [request("declined")]
            #expect(end.plays == (viewer.id == requester.id ? 1 : 0))
        }
    }

    @Test @MainActor
    func eventCueRespectsSoundPreferenceAndPreservesConnectionState() throws {
        let end = CallEventTone()
        let join = CallEventTone()
        let audio = CallAudioFeedback {
            if $0 == .disconnected { return end }
            if $0 == .connected { return join }
            return nil
        }
        audio.update(incomingID: nil, connected: true, enabled: true)
        audio.playEndFeedback(enabled: true)
        audio.update(incomingID: nil, connected: true, enabled: true)
        #expect(end.plays == 1)
        #expect(join.plays == 1, "A group departure must not fake a new connection")
        audio.update(incomingID: nil, connected: true, enabled: false)
        #expect(end.stops == 1)
        audio.playEndFeedback(enabled: false)
        audio.update(incomingID: nil, connected: true, enabled: true)
        #expect(end.plays == 1)
        let player = try AVAudioPlayer(data: CallTone.disconnected.wavData)
        #expect(abs(player.duration - 0.45) < 0.01)
    }
}
