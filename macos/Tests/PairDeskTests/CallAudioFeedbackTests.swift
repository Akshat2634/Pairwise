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
        let audio = CallAudioFeedback { $0 == .ringing ? ring : connected }
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
        let audio = CallAudioFeedback { $0 == .ringing ? ring : connected }
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

    func testGeneratedTonesDecodeAsPlayablePCMWithDistinctDurations() throws {
        let ring = try AVAudioPlayer(data: CallTone.ringing.wavData)
        let connected = try AVAudioPlayer(data: CallTone.connected.wavData)
        XCTAssertEqual(ring.duration, 3, accuracy: 0.01)
        XCTAssertEqual(connected.duration, 0.65, accuracy: 0.01)
        XCTAssertEqual(ring.numberOfChannels, 1)
        XCTAssertEqual(connected.format.sampleRate, 24_000)
    }
}
