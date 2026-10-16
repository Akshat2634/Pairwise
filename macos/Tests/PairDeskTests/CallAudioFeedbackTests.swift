import AVFoundation
import XCTest
@testable import PairDesk

@MainActor
final class RecordingCallTone: CallTonePlaying {
    var numberOfLoops = 0
    var plays = 0
    var stops = 0
    func play() -> Bool { plays += 1; return true }
    func stop() { stops += 1 }
}

@MainActor
final class CallAudioFeedbackTests: XCTestCase {
    func testOutgoingCallLoopsWithoutRestartingOnPollAndStopsWhenResolved() {
        let calling = RecordingCallTone()
        let audio = CallAudioFeedback { $0 == .calling ? calling : nil }
        audio.update(incomingID: nil, outgoingID: "call", connected: false, enabled: true)
        audio.update(incomingID: nil, outgoingID: "call", connected: false, enabled: true)
        XCTAssertEqual(calling.plays, 1)
        XCTAssertEqual(calling.numberOfLoops, -1)
        audio.update(incomingID: nil, connected: false, enabled: true)
        XCTAssertEqual(calling.stops, 1)
        audio.update(incomingID: nil, connected: false, enabled: true)
        XCTAssertEqual(calling.stops, 1)
    }

    func testOutgoingCallStopsOnMediaConnectionAndStaysSilentDuringGroupInvites() {
        let calling = RecordingCallTone()
        let audio = CallAudioFeedback { $0 == .calling ? calling : nil }
        audio.update(incomingID: nil, outgoingID: "call", connected: false, enabled: true)
        audio.update(incomingID: nil, outgoingID: "call", connected: true, enabled: true)
        audio.update(incomingID: nil, outgoingID: "group-invite", connected: true, enabled: true)
        XCTAssertEqual(calling.plays, 1)
        XCTAssertEqual(calling.stops, 1)
    }

    func testOutgoingSoundPreferenceAndIncomingRingPriority() {
        let calling = RecordingCallTone()
        let audio = CallAudioFeedback { $0 == .calling ? calling : nil }
        audio.update(incomingID: nil, outgoingID: "call", connected: false, enabled: false)
        XCTAssertEqual(calling.plays, 0)
        audio.update(incomingID: nil, outgoingID: "call", connected: false, enabled: true)
        audio.update(incomingID: nil, outgoingID: "call", connected: false, enabled: false)
        XCTAssertEqual(calling.plays, 1)
        XCTAssertEqual(calling.stops, 1)
        audio.update(incomingID: "incoming", outgoingID: "call", connected: false, enabled: true)
        XCTAssertEqual(calling.plays, 1, "An incoming ring must not overlap ringback")
    }

    func testAppStoreRingbackRequiresActiveRoomAndStopsForEveryResolvedStatus() {
        let savedSounds = UserDefaults.standard.object(forKey: "playCallSounds")
        defer { UserDefaults.standard.set(savedSounds, forKey: "playCallSounds") }
        let calling = RecordingCallTone()
        let store = AppStore(callAudio: CallAudioFeedback { $0 == .calling ? calling : nil })
        let me = TeamUser(id: "caller", name: "Caller", email: "caller@pairdesk.invalid")
        let target = TeamUser(id: "target", name: "Target", email: "target@pairdesk.invalid")
        let room = PairRoom(id: "room", name: "Direct call", participantCount: 1, participants: [me])
        store.debugUseSession(user: me, token: "fixture", server: "http://127.0.0.1:1")
        store.playCallSounds = true
        func invitation(_ status: String) -> CallInvitation {
            CallInvitation(id: "call", status: status, caller: me, target: target, room: room, expiresAt: "")
        }
        store.callInvitations = [invitation("pending")]
        XCTAssertEqual(calling.plays, 0, "Failed or not-yet-joined calls must stay silent")
        store.activeRoom = room
        XCTAssertEqual(calling.plays, 1)
        store.callInvitations = [invitation("pending")]
        XCTAssertEqual(calling.plays, 1)
        store.activeRoom = nil
        XCTAssertEqual(calling.stops, 1, "Hang-up must silence ringback immediately")
        store.callInvitations = [invitation("pending")]
        XCTAssertEqual(calling.plays, 1, "Stale polls after hang-up must not restart ringback")
        for (index, status) in ["accepted", "declined", "cancelled", "expired"].enumerated() {
            store.callInvitations = [invitation("pending")]
            store.activeRoom = room
            XCTAssertEqual(calling.plays, index + 2)
            store.callInvitations = [invitation(status)]
            XCTAssertEqual(calling.stops, index + 2, "Ringback must stop for \(status)")
            store.activeRoom = nil
        }
    }

    func testPendingInvitationLoopsWithoutRestartingOnPollAndStopsWhenGone() {
        let ring = RecordingCallTone()
        let audio = CallAudioFeedback { _ in ring }
        audio.update(incomingID: "call", connected: false, enabled: true)
        audio.update(incomingID: "call", connected: false, enabled: true)
        XCTAssertEqual(ring.plays, 1)
        XCTAssertEqual(ring.numberOfLoops, -1)
        audio.update(incomingID: nil, connected: false, enabled: true)
        XCTAssertEqual(ring.stops, 1)
    }

    func testAnswerSilencesStalePendingPollsAndFailedAnswerCanRingAgain() {
        let ring = RecordingCallTone()
        let audio = CallAudioFeedback { _ in ring }
        audio.update(incomingID: "call", connected: false, enabled: true)
        audio.silenceIncoming("call")
        audio.update(incomingID: "call", connected: false, enabled: true)
        XCTAssertEqual(ring.stops, 1)
        XCTAssertEqual(ring.plays, 1)
        audio.retryIncoming()
        audio.update(incomingID: "call", connected: false, enabled: true)
        XCTAssertEqual(ring.plays, 2)
    }

    func testMediaConnectionStopsRingAndConfirmsOnceUntilNextCall() {
        let ring = RecordingCallTone()
        let connected = RecordingCallTone()
        let audio = CallAudioFeedback {
            switch $0 {
            case .ringing: return ring
            case .connected: return connected
            case .calling, .disconnected: return nil
            }
        }
        audio.update(incomingID: "call", connected: false, enabled: true)
        audio.update(incomingID: "call", connected: true, enabled: true)
        audio.update(incomingID: nil, connected: true, enabled: true)
        XCTAssertEqual(ring.stops, 1)
        XCTAssertEqual(connected.plays, 1)
        XCTAssertEqual(connected.numberOfLoops, 0)
        audio.update(incomingID: nil, connected: false, enabled: true)
        XCTAssertEqual(connected.stops, 1)
        audio.update(incomingID: nil, connected: true, enabled: true)
        XCTAssertEqual(connected.plays, 2)
    }

    func testSoundPreferenceStopsImmediatelyAndDoesNotReplayConnection() {
        let ring = RecordingCallTone()
        let connected = RecordingCallTone()
        let audio = CallAudioFeedback {
            switch $0 {
            case .ringing: return ring
            case .connected: return connected
            case .calling, .disconnected: return nil
            }
        }
        audio.update(incomingID: "call", connected: false, enabled: true)
        audio.update(incomingID: "call", connected: false, enabled: false)
        XCTAssertEqual(ring.stops, 1)
        audio.update(incomingID: nil, connected: true, enabled: false)
        audio.update(incomingID: nil, connected: true, enabled: true)
        XCTAssertEqual(connected.plays, 0)
        audio.update(incomingID: nil, connected: false, enabled: true)
        audio.update(incomingID: "new-call", connected: false, enabled: true)
        XCTAssertEqual(ring.plays, 2)
    }

    func testDisconnectionPlaysOnceAndFinishesAcrossIdleUpdates() {
        let connected = RecordingCallTone()
        let disconnected = RecordingCallTone()
        let audio = CallAudioFeedback {
            switch $0 {
            case .ringing, .calling: return nil
            case .connected: return connected
            case .disconnected: return disconnected
            }
        }
        audio.update(incomingID: nil, connected: false, enabled: true)
        audio.update(incomingID: "unanswered", connected: false, enabled: true)
        audio.update(incomingID: nil, connected: false, enabled: true)
        XCTAssertEqual(disconnected.plays, 0, "Unanswered calls must not play a disconnect tune")
        audio.update(incomingID: nil, connected: true, enabled: true)
        audio.update(incomingID: nil, connected: false, enabled: true)
        audio.update(incomingID: nil, connected: false, enabled: true)
        XCTAssertEqual(connected.stops, 1)
        XCTAssertEqual(disconnected.plays, 1)
        XCTAssertEqual(disconnected.numberOfLoops, 0)
        XCTAssertEqual(disconnected.stops, 0, "Idle updates must let the disconnect tune finish")
        audio.update(incomingID: nil, connected: true, enabled: true)
        XCTAssertEqual(disconnected.stops, 1, "A new connection replaces the disconnect tune")
    }

    func testSoundPreferenceSilencesDisconnectAndDoesNotReplayWhenEnabled() {
        let disconnected = RecordingCallTone()
        let audio = CallAudioFeedback { $0 == .disconnected ? disconnected : nil }
        audio.update(incomingID: nil, connected: true, enabled: true)
        audio.update(incomingID: nil, connected: false, enabled: true)
        audio.update(incomingID: nil, connected: false, enabled: false)
        XCTAssertEqual(disconnected.plays, 1)
        XCTAssertEqual(disconnected.stops, 1)
        audio.update(incomingID: nil, connected: true, enabled: false)
        audio.update(incomingID: nil, connected: false, enabled: false)
        audio.update(incomingID: nil, connected: false, enabled: true)
        XCTAssertEqual(disconnected.plays, 1, "Enabling sounds must not replay an ended call")
    }

    func testGeneratedTonesDecodeAsPlayablePCM() throws {
        let ring = try AVAudioPlayer(data: CallTone.ringing.wavData)
        let calling = try AVAudioPlayer(data: CallTone.calling.wavData)
        let connected = try AVAudioPlayer(data: CallTone.connected.wavData)
        let disconnected = try AVAudioPlayer(data: CallTone.disconnected.wavData)
        XCTAssertEqual(ring.duration, 3, accuracy: 0.01)
        XCTAssertEqual(calling.duration, 3, accuracy: 0.01)
        XCTAssertEqual(connected.duration, 0.65, accuracy: 0.01)
        XCTAssertEqual(disconnected.duration, 0.45, accuracy: 0.01)
        XCTAssertEqual(ring.numberOfChannels, 1)
        XCTAssertEqual(connected.format.sampleRate, 24_000)
        XCTAssertEqual(disconnected.numberOfChannels, 1)
        XCTAssertEqual(disconnected.format.sampleRate, 24_000)
        XCTAssertEqual(calling.numberOfChannels, 1)
        XCTAssertEqual(calling.format.sampleRate, 24_000)
        XCTAssertNotEqual(CallTone.calling.wavData, CallTone.ringing.wavData)
    }
}
