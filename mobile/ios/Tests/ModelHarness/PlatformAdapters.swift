// Test-only adapters. The harness compiles the production AppModel/APIClient;
// UIKit notifications and LiveKit media are replaced without accessing devices.
import Foundation

@MainActor final class CallSession {
    var onDisconnected: (() -> Void)?
    var joinAttempts = 0
    var shouldFailJoin = false
    var connected = false
    func join(url: String, token: String, startMicrophone: Bool = true) async throws {
        joinAttempts += 1
        if shouldFailJoin { throw APIError(message: "Fixture connection failure") }
        connected = true
    }
    func leave() async { connected = false }
    func simulateRemoteDisconnect() { connected = false; onDisconnected?() }
}

@MainActor enum PairDeskAppDelegate {
    static func requestNotificationAuthorizationAfterAuthentication() {}
    static func reconcileIncomingCalls(with invitations: [CallInvitation], activeRoomID: String?) {}
    static func reportActiveCallsEnded() {}
}
