import AppKit
import SwiftUI
import XCTest
@preconcurrency import LiveKit
@testable import PairDesk

final class HostCursorIntegrationTests: XCTestCase {
    @MainActor
    func testAuthenticatedCursorPacketsShowNamesOnHostAndClearWithTheShare() async throws {
        guard let address = ProcessInfo.processInfo.environment["PAIRDESK_TEST_API"],
              let password = ProcessInfo.processInfo.environment["PAIRDESK_TEST_PASSWORD"] else {
            throw XCTSkip("Run scripts/test-call.sh for host cursor integration")
        }
        _ = NSApplication.shared
        struct LoginBody: Encodable { let email: String; let password: String }
        struct RoomBody: Encodable { let name: String }
        let unsigned = try APIClient(server: address)
        var clients: [APIClient] = []
        var users: [TeamUser] = []
        for i in 1...2 {
            let login: LoginResponse = try await unsigned.post("v1/login", body: LoginBody(email: "integration-\(i)@pairdesk.invalid", password: password))
            clients.append(try APIClient(server: address, token: login.token))
            users.append(login.user)
        }
        let response: RoomResponse = try await clients[0].post("v1/rooms", body: RoomBody(name: "Host cursor fixture"))
        let host = RTCService()
        let viewer = Room()
        do {
            let hostJoin: JoinResponse = try await clients[0].post("v1/rooms/\(response.room.id)/join", body: EmptyBody())
            try await host.connect(url: hostJoin.url, token: hostJoin.token, identity: hostJoin.participantIdentity, name: users[0].name)
            let viewerJoin: JoinResponse = try await clients[1].post("v1/rooms/\(response.room.id)/join", body: EmptyBody())
            try await viewer.connect(url: viewerJoin.url, token: viewerJoin.token)
            let viewerID = viewerJoin.participantIdentity
            try await waitFor { host.participants.contains { $0.identity == viewerID } }
            // Use real authenticated RTC packets and the production desktop
            // overlay, with synthetic share geometry instead of screen capture.
            host.debugStartCursorShare(bounds: CGRect(x: 100, y: 100, width: 800, height: 500), session: "share-one")
            let panel = try XCTUnwrap(host.debugHostCursorPanel)
            let content = try XCTUnwrap(panel.contentView as? NSHostingView<SharedCursorLayer>)
            func send(_ sequence: UInt64, x: Double = 0.25, y: Double = 0.75,
                      visible: Bool = true, session: String = "share-one") async throws {
                let message = RemoteControlMessage(epoch: session, sequence: sequence, kind: .cursor, x: x, y: y, visible: visible)
                try await viewer.localParticipant.publish(data: JSONEncoder().encode(message),
                    options: DataPublishOptions(destinationIdentities: [Participant.Identity(from: hostJoin.participantIdentity)],
                                                topic: "pairdesk.control.v1", reliable: false))
            }
            try await send(1)
            try await waitFor { host.remotePointers.first?.x == 0.25 }
            XCTAssertTrue(panel.isVisible)
            XCTAssertEqual(content.rootView.names[viewerID], users[1].name)
            XCTAssertEqual(content.rootView.pointers.first?.id, viewerID)
            XCTAssertFalse(panel.canBecomeKey)
            XCTAssertTrue(panel.ignoresMouseEvents)
            try await send(2, x: 0.8, y: 0.2)
            try await waitFor { host.remotePointers.first?.x == 0.8 }
            XCTAssertEqual(host.remotePointers.count, 1)
            XCTAssertEqual(content.rootView.pointers.first?.y, 0.2)
            try await send(3, visible: false)
            try await waitFor { host.remotePointers.isEmpty }
            XCTAssertFalse(panel.isVisible)
            try await send(4)
            try await waitFor { !host.remotePointers.isEmpty }
            try await waitFor { host.remotePointers.isEmpty }
            XCTAssertFalse(panel.isVisible, "A silent viewer's stale cursor must expire")

            host.debugStartCursorShare(bounds: CGRect(x: 150, y: 150, width: 400, height: 300), session: "share-two")
            XCTAssertFalse(panel.isVisible)
            let replacement = try XCTUnwrap(host.debugHostCursorPanel)
            XCTAssertFalse(replacement === panel)
            try await send(99, session: "share-one")
            try await send(1, x: 0.5, y: 0.5, session: "share-two")
            try await waitFor { host.remotePointers.first?.x == 0.5 }
            XCTAssertTrue(replacement.isVisible)
            await viewer.disconnect()
            try await waitFor { host.remotePointers.isEmpty }
            XCTAssertFalse(replacement.isVisible)
            await host.disconnect()
            XCTAssertNil(host.debugHostCursorPanel)
        } catch {
            await host.disconnect()
            await viewer.disconnect()
            for client in clients { try? await client.send("v1/rooms/\(response.room.id)/leave", body: EmptyBody()) }
            throw error
        }
        await host.disconnect()
        await viewer.disconnect()
        for client in clients { try? await client.send("v1/rooms/\(response.room.id)/leave", body: EmptyBody()) }
    }

    @MainActor
    private func waitFor(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("Host cursor state did not propagate", file: file, line: line)
    }
}
