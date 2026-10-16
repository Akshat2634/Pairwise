import AppKit
import XCTest
@testable import PairDesk

final class CallFeedbackIntegrationTests: XCTestCase {
    /// Exercises AppStore actions, invitation polling, and real RTCService/LiveKit connections.
    /// Only sound playback is recorded, keeping automated runs quiet and observable.
    @MainActor
    func testIncomingRingAcceptConnectionTuneDeclineAndCancel() async throws {
        guard let address = ProcessInfo.processInfo.environment["PAIRDESK_TEST_API"],
              let password = ProcessInfo.processInfo.environment["PAIRDESK_TEST_PASSWORD"] else {
            throw XCTSkip("Run scripts/test-call.sh for app call-feedback integration")
        }
        _ = NSApplication.shared
        struct LoginBody: Encodable { let email: String; let password: String }
        let api = try APIClient(server: address)
        let callerLogin: LoginResponse = try await api.post("v1/login", body: LoginBody(email: "integration-1@pairdesk.invalid", password: password))
        let targetLogin: LoginResponse = try await api.post("v1/login", body: LoginBody(email: "integration-2@pairdesk.invalid", password: password))
        let callerTune = RecordingCallTone()
        let ring = RecordingCallTone()
        let targetTune = RecordingCallTone()
        let caller = AppStore(callAudio: CallAudioFeedback { _ in callerTune })
        let target = AppStore(callAudio: CallAudioFeedback { $0 == .ringing ? ring : targetTune })
        trace("Created app clients")
        let savedMuted = UserDefaults.standard.object(forKey: "startCallsMuted")
        let savedSounds = UserDefaults.standard.object(forKey: "playCallSounds")
        defer {
            UserDefaults.standard.set(savedMuted, forKey: "startCallsMuted")
            UserDefaults.standard.set(savedSounds, forKey: "playCallSounds")
        }
        caller.debugUseSession(user: callerLogin.user, token: callerLogin.token, server: address)
        target.debugUseSession(user: targetLogin.user, token: targetLogin.token, server: address)
        caller.startCallsMuted = true
        target.startCallsMuted = true
        caller.playCallSounds = true
        target.playCallSounds = true
        do {
            await target.refresh()
            await caller.refresh()
            let person = try XCTUnwrap(caller.users.first { $0.id == targetLogin.user.id })
            trace("Calling online recipient")
            await caller.call(person)
            trace("Caller joined")
            XCTAssertNotNil(caller.activeRoom, caller.error ?? "Caller failed to join")
            XCTAssertEqual(callerTune.plays, 0, "Joining an empty room must not confirm a call")
            await target.refreshInvitations()
            let incoming = try XCTUnwrap(target.incomingCall)
            XCTAssertEqual(ring.plays, 1)
            XCTAssertEqual(ring.numberOfLoops, -1)
            await target.refreshInvitations()
            XCTAssertEqual(ring.plays, 1, "Polling must not restart ringing")
            trace("Accepting incoming call")
            await target.acceptCall(incoming)
            trace("Recipient joined")
            XCTAssertNotNil(target.activeRoom, target.error ?? "Target failed to join")
            for _ in 0..<100 {
                if callerTune.plays == 1 && targetTune.plays == 1 { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            XCTAssertEqual(ring.stops, 1)
            XCTAssertEqual(callerTune.plays, 1)
            XCTAssertEqual(targetTune.plays, 1)
            XCTAssertTrue(caller.rtc.connected)
            XCTAssertTrue(target.rtc.connected)
            XCTAssertFalse(caller.rtc.isMicrophoneEnabled)
            XCTAssertFalse(target.rtc.isMicrophoneEnabled)
            await caller.refreshInvitations()
            await target.refreshInvitations()
            XCTAssertEqual(callerTune.plays, 1)
            XCTAssertEqual(targetTune.plays, 1)
            await target.leave()
            await caller.leave()
            trace("Connected call ended")

            await caller.refresh()
            await target.refresh()
            await caller.call(person)
            await target.refreshInvitations()
            let declined = try XCTUnwrap(target.incomingCall)
            XCTAssertEqual(ring.plays, 2)
            await target.declineCall(declined)
            trace("Second call declined")
            await caller.refreshInvitations()
            XCTAssertNil(target.incomingCall)
            XCTAssertEqual(ring.stops, 2)
            XCTAssertEqual(targetTune.plays, 1, "Declining must not confirm a connection")
            await caller.leave()

            await caller.refresh()
            await target.refresh()
            await caller.call(person)
            await target.refreshInvitations()
            let cancelled = try XCTUnwrap(caller.outgoingCalls.first)
            XCTAssertEqual(ring.plays, 3)
            await caller.cancelCall(cancelled)
            trace("Third call cancelled")
            await target.refreshInvitations()
            XCTAssertNil(target.incomingCall)
            XCTAssertEqual(ring.stops, 3)
            XCTAssertEqual(callerTune.plays, 1, "Unanswered calls must not confirm a connection")
        } catch {
            await target.leave()
            await caller.leave()
            throw error
        }
        await target.leave()
        await caller.leave()
    }

    private func trace(_ message: String) {
        FileHandle.standardError.write(Data("Call feedback integration: \(message)\n".utf8))
    }
}
