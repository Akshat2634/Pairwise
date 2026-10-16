import AppKit
import XCTest
@preconcurrency import LiveKit
@testable import PairDesk

final class RemoteMuteIntegrationTests: XCTestCase {
    @MainActor
    func testRemoteMicrophoneStateAcrossPublishMuteUnpublishAndRejoin() async throws {
        guard let address = ProcessInfo.processInfo.environment["PAIRDESK_TEST_API"],
              let password = ProcessInfo.processInfo.environment["PAIRDESK_TEST_PASSWORD"] else {
            throw XCTSkip("Run scripts/test-call.sh for remote mute integration")
        }
        _ = NSApplication.shared
        // Signal real microphone publications without opening an input or output
        // device. These checks verify state propagation, not audible capture.
        let availability = AudioManager.shared.engineAvailability
        try AudioManager.shared.setEngineAvailability(.none)
        defer { try? AudioManager.shared.setEngineAvailability(availability) }

        struct LoginBody: Encodable { let email: String; let password: String }
        struct RoomBody: Encodable { let name: String }
        let unsigned = try APIClient(server: address)
        var clients: [APIClient] = []
        for i in 1...2 {
            let login: LoginResponse = try await unsigned.post("v1/login", body: LoginBody(email: "integration-\(i)@pairdesk.invalid", password: password))
            clients.append(try APIClient(server: address, token: login.token))
        }
        let response: RoomResponse = try await clients[0].post("v1/rooms", body: RoomBody(name: "Remote microphone state fixture"))
        let observer = RTCService()
        let publisher = Room()
        do {
            let viewerJoin: JoinResponse = try await clients[0].post("v1/rooms/\(response.room.id)/join", body: EmptyBody())
            try await observer.connect(url: viewerJoin.url, token: viewerJoin.token,
                                       identity: viewerJoin.participantIdentity, name: "Observer")
            let peerJoin: JoinResponse = try await clients[1].post("v1/rooms/\(response.room.id)/join", body: EmptyBody())
            try await publisher.connect(url: peerJoin.url, token: peerJoin.token)
            let peerID = peerJoin.participantIdentity
            try await expectMicrophone(observer, identity: peerID, muted: true)

            let track = await LocalAudioTrack.createTrack()
            let publication = try await publisher.localParticipant.publish(audioTrack: track)
            try await expectMicrophone(observer, identity: peerID, muted: false)
            try await publication.mute()
            try await expectMicrophone(observer, identity: peerID, muted: true)
            try await publication.unmute()
            try await expectMicrophone(observer, identity: peerID, muted: false)
            try await publisher.localParticipant.unpublish(publication: publication)
            try await expectMicrophone(observer, identity: peerID, muted: true)

            let replacement = await LocalAudioTrack.createTrack()
            let replacementPublication = try await publisher.localParticipant.publish(audioTrack: replacement)
            try await expectMicrophone(observer, identity: peerID, muted: false)
            try await replacementPublication.mute()
            try await expectMicrophone(observer, identity: peerID, muted: true)
            await observer.disconnect()
            XCTAssertTrue(observer.participants.isEmpty)
            let rejoin: JoinResponse = try await clients[0].post("v1/rooms/\(response.room.id)/join", body: EmptyBody())
            try await observer.connect(url: rejoin.url, token: rejoin.token,
                                       identity: rejoin.participantIdentity, name: "Observer")
            try await expectMicrophone(observer, identity: peerID, muted: true)
            try await replacementPublication.unmute()
            try await expectMicrophone(observer, identity: peerID, muted: false)
        } catch {
            await observer.disconnect()
            await publisher.disconnect()
            for client in clients { try? await client.send("v1/rooms/\(response.room.id)/leave", body: EmptyBody()) }
            throw error
        }
        await observer.disconnect()
        await publisher.disconnect()
        for client in clients { try? await client.send("v1/rooms/\(response.room.id)/leave", body: EmptyBody()) }
    }

    @MainActor
    private func expectMicrophone(_ rtc: RTCService, identity: String, muted: Bool,
                                  file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<100 {
            if rtc.participants.first(where: { $0.identity == identity })?.isMicrophoneMuted == muted { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(rtc.participants.first(where: { $0.identity == identity })?.isMicrophoneMuted,
                       muted, "Remote microphone state did not propagate", file: file, line: line)
    }
}
