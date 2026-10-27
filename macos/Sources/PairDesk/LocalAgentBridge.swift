import Combine
import Foundation
import Darwin
import Security

extension Notification.Name {
    static let pairDeskAgentScreenshotRequested = Notification.Name("PairDesk.AgentScreenshotRequested")
}

final class AgentScreenshotRequest: @unchecked Sendable {
    private let lock = NSLock()
    private let completed = DispatchSemaphore(value: 0)
    private var result: Result<Data, AgentScreenshotFailure>?
    private var didComplete = false

    func resolve(data: Data) { finish(.success(data)) }
    func resolve(error: String) { finish(.failure(AgentScreenshotFailure(message: error))) }

    func wait(timeout: DispatchTimeInterval) -> Result<Data, AgentScreenshotFailure>? {
        guard completed.wait(timeout: .now() + timeout) == .success else { return nil }
        lock.lock(); defer { lock.unlock() }
        return result
    }

    private func finish(_ result: Result<Data, AgentScreenshotFailure>) {
        lock.lock()
        guard !didComplete else { lock.unlock(); return }
        didComplete = true
        self.result = result
        lock.unlock()
        completed.signal()
    }
}

struct AgentScreenshotFailure: Error {
    let message: String
}

/// Call-scoped, local-only bridge for explicitly granted coding-agent context.
/// The socket is created only after the person grants at least one capability.
@MainActor
final class LocalAgentBridge: ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var grantedCapabilities: Set<String> = []
    @Published private(set) var socketPath = ""
    @Published private(set) var credential: String?
    @Published private(set) var screenshotActivity: String?
    @Published private(set) var hasActiveCall = false

    private let state: AgentBridgeState
    private let endpoint: URL
    private var listener: Int32 = -1
    private var listenerQueue: DispatchQueue?
    private var callID: String?
    private var screenshotObserver: NSObjectProtocol?

    init(socketURL: URL? = nil, auditURL: URL? = nil,
         screenshotProvider: (() -> Result<Data, AgentScreenshotFailure>?)? = nil) {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        endpoint = socketURL ?? root.appendingPathComponent("PairDesk/agent.sock")
        state = AgentBridgeState(auditURL: auditURL ?? LocalAgentBridgeAudit.url, screenshotProvider: screenshotProvider)
        screenshotObserver = NotificationCenter.default.addObserver(
            forName: .pairDeskAgentScreenshotRequested, object: nil, queue: .main
        ) { [weak self] notification in
            guard let request = notification.object as? AgentScreenshotRequest else { return }
            Task { @MainActor [weak self] in await self?.captureScreenshot(for: request) }
        }
    }

    func update(callID: String?, participants: [[String: String]], transcript: [[String: String]]) {
        if self.callID != callID {
            revoke(reason: "call-ended")
            self.callID = callID
        }
        hasActiveCall = callID != nil
        state.update(callID: callID, participants: participants, transcript: transcript)
    }

    @discardableResult
    func authorize(capabilities: Set<String>) -> String? {
        guard callID != nil, !capabilities.isEmpty,
              capabilities.isSubset(of: ["participants", "transcript", "screenshot"]) else { return nil }
        revoke(reason: "replaced")
        guard let token = Self.randomCredential() else { return nil }
        let path = endpoint.path
        guard startListener(path: path) else { return nil }
        state.authorize(token: token, capabilities: capabilities)
        credential = token
        grantedCapabilities = capabilities
        socketPath = path
        isEnabled = true
        state.audit("grant", capability: capabilities.sorted().joined(separator: ","))
        return token
    }

    func revoke(reason: String = "user-revoked") {
        guard isEnabled || listener >= 0 else { return }
        state.revoke(reason: reason)
        if listener >= 0 {
            shutdown(listener, SHUT_RDWR)
            close(listener)
            listener = -1
        }
        if !socketPath.isEmpty { unlink(socketPath) }
        credential = nil
        grantedCapabilities = []
        isEnabled = false
        socketPath = ""
        screenshotActivity = nil
    }

    private func captureScreenshot(for request: AgentScreenshotRequest) async {
        guard isEnabled, grantedCapabilities.contains("screenshot") else {
            request.resolve(error: "screenshot access is no longer enabled")
            return
        }
        screenshotActivity = "Choose one window in the macOS picker to share a screenshot with your local agent."
        do {
            let png = try await SystemScreenPicker.shared.captureAgentScreenshot()
            guard isEnabled, grantedCapabilities.contains("screenshot") else {
                request.resolve(error: "screenshot access was revoked before delivery")
                screenshotActivity = nil
                return
            }
            screenshotActivity = "One screenshot was shared with the local agent."
            request.resolve(data: png)
        } catch {
            screenshotActivity = (error as? CocoaError)?.code == .userCancelled
                ? "Screenshot cancelled; nothing was shared."
                : "Screenshot was not shared."
            request.resolve(error: "screenshot was cancelled or unavailable")
        }
    }

    private func startListener(path: String) -> Bool {
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        } catch { return false }
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { close(fd); return false }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
        }
        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0, chmod(path, 0o600) == 0, listen(fd, 8) == 0 else {
            close(fd); unlink(path); return false
        }
        listener = fd
        listenerQueue = DispatchQueue(label: "app.pairdesk.agent-bridge", qos: .utility)
        let bridgeState = state
        listenerQueue?.async { Self.acceptLoop(fd, state: bridgeState) }
        return true
    }

    nonisolated private static func acceptLoop(_ fd: Int32, state: AgentBridgeState) {
        while true {
            let client = accept(fd, nil, nil)
            if client < 0 { return }
            defer { close(client) }
            var noSignal: Int32 = 1
            _ = setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
            var timeout = timeval(tv_sec: 3, tv_usec: 0)
            _ = setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            guard let data = readLine(client, limit: 4 * 1024 * 1024),
                  let request = try? JSONDecoder().decode(AgentBridgeRequest.self, from: data) else { continue }
            let response = state.handle(request)
            guard let data = try? JSONEncoder().encode(response) else { continue }
            guard data.count <= 4 * 1024 * 1024 else { continue }
            writeAll(client, data + Data([0x0a]))
        }
    }

    nonisolated private static func readLine(_ fd: Int32, limit: Int) -> Data? {
        var data = Data()
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while data.count < limit {
            let count = read(fd, &chunk, chunk.count)
            if count == 0 { break }
            guard count > 0 else { return nil }
            if data.count + count > limit, chunk[..<count].firstIndex(of: 0x0a) == nil { return nil }
            if let newline = chunk[..<count].firstIndex(of: 0x0a) {
                data.append(contentsOf: chunk[..<newline])
                return data
            }
            data.append(contentsOf: chunk[..<count])
        }
        return data.isEmpty ? nil : data
    }

    nonisolated private static func writeAll(_ fd: Int32, _ data: Data) {
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < data.count {
                let count = write(fd, base.advanced(by: offset), data.count - offset)
                if count <= 0 { return }
                offset += count
            }
        }
    }

    private static func randomCredential() -> String? {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return nil }
        return Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

struct AgentBridgeRequest: Decodable {
    let token: String
    let method: String
}

struct AgentBridgeResponse: Encodable {
    let ok: Bool
    let result: [String: AnyCodable]?
    let error: String?
    init(result: [String: Any]?) {
        self.ok = true
        self.result = result?.mapValues(AnyCodable.init)
        self.error = nil
    }
    init(error: String) { self.ok = false; self.result = nil; self.error = error }
}

struct AnyCodable: Encodable {
    private let value: Any
    init(_ value: Any) { self.value = value }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let value as String: try container.encode(value)
        case let value as [String]: try container.encode(value)
        case let value as [[String: String]]: try container.encode(value)
        case let value as [String: String]: try container.encode(value)
        default: try container.encodeNil()
        }
    }
}

final class AgentBridgeState: @unchecked Sendable {
    private let lock = NSLock()
    private var activeCallID: String?
    private var token: String?
    private var capabilities = Set<String>()
    private var participants = [[String: String]]()
    private var transcript = [[String: String]]()
    private let auditURL: URL
    private let screenshotProvider: (() -> Result<Data, AgentScreenshotFailure>?)?

    init(auditURL: URL, screenshotProvider: (() -> Result<Data, AgentScreenshotFailure>?)? = nil) {
        self.auditURL = auditURL
        self.screenshotProvider = screenshotProvider
    }

    func update(callID: String?, participants: [[String: String]], transcript: [[String: String]]) {
        lock.lock(); defer { lock.unlock() }
        activeCallID = callID
        self.participants = participants
        self.transcript = transcript
    }
    func authorize(token: String, capabilities: Set<String>) {
        lock.lock(); defer { lock.unlock() }
        self.token = token
        self.capabilities = capabilities
    }
    func revoke(reason: String) {
        lock.lock(); defer { lock.unlock() }
        token = nil; capabilities = []
        LocalAgentBridgeAudit.write(action: "revoke", capability: reason, to: auditURL)
    }
    func audit(_ action: String, capability: String) {
        lock.lock(); defer { lock.unlock() }
        LocalAgentBridgeAudit.write(action: action, capability: capability, to: auditURL)
    }
    func handle(_ request: AgentBridgeRequest) -> AgentBridgeResponse {
        lock.lock()
        guard let token, Self.constantTimeEqual(token, request.token), activeCallID != nil else {
            LocalAgentBridgeAudit.write(action: "denied", capability: "unauthorized", to: auditURL)
            lock.unlock()
            return AgentBridgeResponse(error: "unauthorized or call ended")
        }
        if request.method == "screenshot" {
            guard capabilities.contains("screenshot") else {
                LocalAgentBridgeAudit.write(action: "denied", capability: "screenshot", to: auditURL)
                lock.unlock()
                return AgentBridgeResponse(error: "screenshot capability not granted")
            }
            lock.unlock()
            return captureScreenshot(token: request.token)
        }
        defer { lock.unlock() }
        switch request.method {
        case "capabilities":
            LocalAgentBridgeAudit.write(action: "read", capability: "capabilities", to: auditURL)
            return AgentBridgeResponse(result: ["capabilities": Array(capabilities).sorted()])
        case "participants":
            guard capabilities.contains("participants") else {
                LocalAgentBridgeAudit.write(action: "denied", capability: "participants", to: auditURL)
                return AgentBridgeResponse(error: "participant capability not granted")
            }
            LocalAgentBridgeAudit.write(action: "read", capability: "participants", to: auditURL)
            return AgentBridgeResponse(result: ["participants": participants])
        case "transcript":
            guard capabilities.contains("transcript") else {
                LocalAgentBridgeAudit.write(action: "denied", capability: "transcript", to: auditURL)
                return AgentBridgeResponse(error: "transcript capability not granted")
            }
            LocalAgentBridgeAudit.write(action: "read", capability: "transcript", to: auditURL)
            return AgentBridgeResponse(result: ["segments": transcript])
        default:
            LocalAgentBridgeAudit.write(action: "denied", capability: "unknown", to: auditURL)
            return AgentBridgeResponse(error: "unknown method")
        }
    }

    private func captureScreenshot(token requestedToken: String) -> AgentBridgeResponse {
        let result: Result<Data, AgentScreenshotFailure>?
        if let screenshotProvider {
            result = screenshotProvider()
        } else {
            let request = AgentScreenshotRequest()
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .pairDeskAgentScreenshotRequested, object: request)
            }
            result = request.wait(timeout: .seconds(90))
        }
        guard let result else {
            audit("denied", capability: "screenshot-timeout")
            return AgentBridgeResponse(error: "screenshot request timed out or was not approved")
        }
        switch result {
        case let .failure(error):
            audit("denied", capability: "screenshot-cancelled")
            return AgentBridgeResponse(error: error.message)
        case let .success(png):
            guard finishScreenshotIfAuthorized(token: requestedToken) else {
                return AgentBridgeResponse(error: "screenshot access expired before delivery")
            }
            return AgentBridgeResponse(result: ["mimeType": "image/png", "data": png.base64EncodedString()])
        }
    }

    private func finishScreenshotIfAuthorized(token requestedToken: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let token, Self.constantTimeEqual(token, requestedToken), activeCallID != nil,
              capabilities.contains("screenshot") else {
            LocalAgentBridgeAudit.write(action: "denied", capability: "screenshot-revoked", to: auditURL)
            return false
        }
        LocalAgentBridgeAudit.write(action: "read", capability: "screenshot", to: auditURL)
        return true
    }

    private static func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs.utf8), b = Array(rhs.utf8)
        guard a.count == b.count else { return false }
        var difference: UInt8 = 0
        for index in a.indices {
            difference |= a[index] ^ b[index]
        }
        return difference == 0
    }
}

private enum LocalAgentBridgeAudit {
    static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("PairDesk/agent-audit.jsonl")
    }
    static func write(action: String, capability: String, to url: URL) {
        let row: [String: String] = ["time": ISO8601DateFormatter().string(from: Date()),
                                     "action": action, "capability": capability]
        guard let data = try? JSONSerialization.data(withJSONObject: row),
              let handle = try? FileHandle(forWritingTo: url) else {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700])
                let data = try JSONSerialization.data(withJSONObject: row) + Data([0x0a])
                try data.write(to: url, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            } catch { }
            return
        }
        defer { try? handle.close() }
        do { try handle.seekToEnd(); try handle.write(contentsOf: data + Data([0x0a])) } catch { }
    }
}
