import Foundation
import XCTest
@preconcurrency import LiveKit
@testable import PairDesk

final class DirectCallIntegrationTests: XCTestCase {
    @MainActor
    func testRingingAcceptAddingPeopleAndPrivateRoomAccess() async throws {
        guard let address = ProcessInfo.processInfo.environment["PAIRDESK_TEST_API"],
              let password = ProcessInfo.processInfo.environment["PAIRDESK_TEST_PASSWORD"] else {
            throw XCTSkip("Run scripts/test-call.sh for direct-call integration")
        }
        struct LoginBody: Encodable { let email: String; let password: String }
        struct CallBody: Encodable { let userId: String; let roomId: String? }
        let unsigned = try APIClient(server: address)
        var clients: [APIClient] = []
        var users: [TeamUser] = []
        for i in 1...5 {
            let login: LoginResponse = try await unsigned.post("v1/login", body: LoginBody(email: "integration-\(i)@pairdesk.invalid", password: password))
            clients.append(try APIClient(server: address, token: login.token))
            users.append(login.user)
        }
        for client in clients { try await client.send("v1/heartbeat", body: EmptyBody()) }
        var media: [Room] = []
        var activeRoomID: String?
        do {
            let invitation: CallResponse = try await clients[0].post("v1/calls", body: CallBody(userId: users[1].id, roomId: nil))
            let call = invitation.call
            activeRoomID = call.room.id
            XCTAssertEqual(call.status, "pending")
            XCTAssertEqual(call.caller.id, users[0].id)
            XCTAssertEqual(call.target.id, users[1].id)
            let inbox: CallsResponse = try await clients[1].request("v1/calls")
            XCTAssertTrue(inbox.calls.contains { $0.id == call.id && $0.status == "pending" })
            do {
                let _: CallResponse = try await clients[2].post("v1/calls/\(call.id)/accept", body: EmptyBody())
                XCTFail("An unrelated user accepted the call")
            } catch let error as APIError { XCTAssertEqual(error.status, 403) }
            do {
                let _: JoinResponse = try await clients[2].post("v1/rooms/\(call.room.id)/join", body: EmptyBody())
                XCTFail("An uninvited user joined a private call")
            } catch let error as APIError { XCTAssertEqual(error.status, 403) }
            let callerJoin: JoinResponse = try await clients[0].post("v1/rooms/\(call.room.id)/join", body: EmptyBody())
            let caller = Room()
            media.append(caller)
            try await caller.connect(url: callerJoin.url, token: callerJoin.token)
            let accepted: CallResponse = try await clients[1].post("v1/calls/\(call.id)/accept", body: EmptyBody())
            XCTAssertEqual(accepted.call.status, "accepted")
            let targetJoin: JoinResponse = try await clients[1].post("v1/rooms/\(call.room.id)/join", body: EmptyBody())
            XCTAssertEqual(targetJoin.room.id, callerJoin.room.id)
            let target = Room()
            media.append(target)
            try await target.connect(url: targetJoin.url, token: targetJoin.token)
            for _ in 0..<100 {
                if caller.remoteParticipants.count == 1 { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            XCTAssertEqual(caller.remoteParticipants.count, 1)
            for client in clients.prefix(2) { try await client.send("v1/rooms/\(call.room.id)/heartbeat", body: EmptyBody()) }
            for client in clients { try await client.send("v1/heartbeat", body: EmptyBody()) }
            let third: CallResponse = try await clients[0].post("v1/calls", body: CallBody(userId: users[2].id, roomId: call.room.id))
            let _: CallResponse = try await clients[2].post("v1/calls/\(third.call.id)/accept", body: EmptyBody())
            let thirdJoin: JoinResponse = try await clients[2].post("v1/rooms/\(call.room.id)/join", body: EmptyBody())
            let thirdMedia = Room()
            media.append(thirdMedia)
            try await thirdMedia.connect(url: thirdJoin.url, token: thirdJoin.token)
            for client in clients.prefix(3) { try await client.send("v1/rooms/\(call.room.id)/heartbeat", body: EmptyBody()) }
            for client in clients { try await client.send("v1/heartbeat", body: EmptyBody()) }
            let fourth: CallResponse = try await clients[0].post("v1/calls", body: CallBody(userId: users[3].id, roomId: call.room.id))
            do {
                let _: CallResponse = try await clients[0].post("v1/calls", body: CallBody(userId: users[4].id, roomId: call.room.id))
                XCTFail("Pending invitation didn't reserve the fourth seat")
            } catch let error as APIError { XCTAssertEqual(error.status, 409) }
            let declined: CallResponse = try await clients[3].post("v1/calls/\(fourth.call.id)/decline", body: EmptyBody())
            XCTAssertEqual(declined.call.status, "declined")
            let fifth: CallResponse = try await clients[0].post("v1/calls", body: CallBody(userId: users[4].id, roomId: call.room.id))
            let cancelled: CallResponse = try await clients[0].post("v1/calls/\(fifth.call.id)/cancel", body: EmptyBody())
            XCTAssertEqual(cancelled.call.status, "cancelled")
            // Leaving a three-person call keeps the remaining pair connected.
            await caller.disconnect()
            try await clients[0].send("v1/rooms/\(call.room.id)/leave", body: EmptyBody())
            let remaining: CallsResponse = try await clients[1].request("v1/calls")
            XCTAssertTrue(remaining.calls.contains { $0.room.id == call.room.id && $0.status == "accepted" })
            XCTAssertEqual(thirdMedia.connectionState, .connected)
            let directoryAfterFirstLeave: UsersResponse = try await clients[0].request("v1/users")
            XCTAssertEqual(directoryAfterFirstLeave.users.first { $0.id == users[0].id }?.busy, false)
            // When the pair becomes one, the server ends the last participant's call.
            await target.disconnect()
            try await clients[1].send("v1/rooms/\(call.room.id)/leave", body: EmptyBody())
            for _ in 0..<100 {
                if thirdMedia.connectionState == .disconnected { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            XCTAssertEqual(thirdMedia.connectionState, .disconnected)
            let directoryAfterEnd: UsersResponse = try await clients[2].request("v1/users")
            XCTAssertEqual(directoryAfterEnd.users.first { $0.id == users[2].id }?.busy, false)

        } catch {
            for room in media { await room.disconnect() }
            if let activeRoomID { for client in clients { try? await client.send("v1/rooms/\(activeRoomID)/leave", body: EmptyBody()) } }
            throw error
        }
        for room in media { await room.disconnect() }
        if let activeRoomID { for client in clients { try? await client.send("v1/rooms/\(activeRoomID)/leave", body: EmptyBody()) } }
    }
}
