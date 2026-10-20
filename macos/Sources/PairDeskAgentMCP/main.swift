import Foundation
import Darwin

// Minimal MCP stdio adapter. It has no network transport and only forwards
// read-only, capability-scoped requests to the app's active-call Unix socket.
let output = FileHandle.standardOutput
var initializedLegacy = false
while let line = readLine() {
    guard let request = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
          let method = request["method"] as? String else { continue }
    let id = request["id"] ?? NSNull()
    if method.hasPrefix("notifications/") { continue }
    let response: [String: Any]
    switch method {
    case "server/discover":
        response = ["jsonrpc": "2.0", "id": id, "result": ["resultType": "complete",
            "supportedVersions": ["2026-07-28", "2025-11-25"], "capabilities": ["tools": [:]],
            "_meta": ["io.modelcontextprotocol/serverInfo": ["name": "pairdesk-local", "version": "0.1.0"]],
            "instructions": "Read-only PairDesk call context. Access is limited by the person's active-call grants."]]
    case "initialize":
        initializedLegacy = true
        response = ["jsonrpc": "2.0", "id": id,
                    "result": ["protocolVersion": "2025-11-25",
                               "capabilities": ["tools": ["listChanged": false]],
                               "serverInfo": ["name": "pairdesk-local", "version": "0.1.0"]]]
    case "ping":
        guard supportsRequestMetadata(request, legacy: initializedLegacy) else {
            response = protocolError(id: id); send(response, to: output); continue
        }
        response = ["jsonrpc": "2.0", "id": id, "result": ["resultType": "complete"]]
    case "tools/list":
        guard supportsRequestMetadata(request, legacy: initializedLegacy) else {
            response = protocolError(id: id); send(response, to: output); continue
        }
        let capabilities = (try? callBridge(method: "capabilities")["capabilities"] as? [String]) ?? []
        var tools = [[String: Any]]()
        if capabilities.contains("participants") {
            tools.append(["name": "pairdesk_call_participants", "description": "Read participant names for the active PairDesk call.",
                "inputSchema": ["type": "object", "properties": [:], "additionalProperties": false]])
        }
        if capabilities.contains("transcript") {
            tools.append(["name": "pairdesk_call_transcript", "description": "Read the local transcript for the active PairDesk call.",
                "inputSchema": ["type": "object", "properties": [:], "additionalProperties": false]])
        }
        if capabilities.contains("screenshot") {
            tools.append(["name": "pairdesk_call_screenshot", "description": "Request one screenshot of a window the person selects in the native macOS picker. The person must approve each request.",
                "inputSchema": ["type": "object", "properties": [:], "additionalProperties": false]])
        }
        response = ["jsonrpc": "2.0", "id": id, "result": ["resultType": "complete", "tools": tools]]
    case "tools/call":
        guard supportsRequestMetadata(request, legacy: initializedLegacy) else {
            response = protocolError(id: id); send(response, to: output); continue
        }
        let params = request["params"] as? [String: Any] ?? [:]
        let name = params["name"] as? String ?? ""
        let bridgeMethod: String
        let returnsImage: Bool
        switch name {
        case "pairdesk_call_participants": bridgeMethod = "participants"; returnsImage = false
        case "pairdesk_call_transcript": bridgeMethod = "transcript"; returnsImage = false
        case "pairdesk_call_screenshot": bridgeMethod = "screenshot"; returnsImage = true
        default:
            response = ["jsonrpc": "2.0", "id": id,
                        "error": ["code": -32602, "message": "Unknown PairDesk tool"]]
            send(response, to: output); continue
        }
        do {
            let result = try callBridge(method: bridgeMethod)
            if returnsImage {
                guard result["mimeType"] as? String == "image/png",
                      let encoded = result["data"] as? String,
                      let image = Data(base64Encoded: encoded), !image.isEmpty, image.count <= 2_000_000 else {
                    throw BridgeError.message("PairDesk returned an invalid screenshot.")
                }
                response = ["jsonrpc": "2.0", "id": id,
                            "result": ["resultType": "complete", "content": [["type": "image", "data": encoded, "mimeType": "image/png"]], "isError": false]]
                send(response, to: output); continue
            }
            let text = String(data: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), encoding: .utf8) ?? "{}"
            response = ["jsonrpc": "2.0", "id": id,
                        "result": ["resultType": "complete", "content": [["type": "text", "text": text]], "isError": false]]
        } catch {
            response = ["jsonrpc": "2.0", "id": id,
                        "result": ["resultType": "complete", "content": [["type": "text", "text": error.localizedDescription]], "isError": true]]
        }
    default:
        response = ["jsonrpc": "2.0", "id": id,
                    "error": ["code": -32601, "message": "Method not found"]]
    }
    send(response, to: output)
}

func supportsRequestMetadata(_ request: [String: Any], legacy: Bool) -> Bool {
    if legacy { return true }
    let params = request["params"] as? [String: Any] ?? [:]
    let metadata = params["_meta"] as? [String: Any] ?? [:]
    return metadata["io.modelcontextprotocol/protocolVersion"] as? String == "2026-07-28"
        && metadata["io.modelcontextprotocol/clientCapabilities"] is [String: Any]
}

func protocolError(id: Any) -> [String: Any] {
    ["jsonrpc": "2.0", "id": id, "error": ["code": -32600,
        "message": "This request needs valid MCP metadata for protocol version 2026-07-28, or a legacy initialize handshake."]]
}

func send(_ response: [String: Any], to output: FileHandle) {
    guard let data = try? JSONSerialization.data(withJSONObject: response) else { return }
    output.write(data); output.write(Data([0x0a]))
}

func callBridge(method: String) throws -> [String: Any] {
    guard let token = ProcessInfo.processInfo.environment["PAIRDESK_BRIDGE_TOKEN"], !token.isEmpty else {
        throw BridgeError.message("PairDesk bridge token is missing; enable access in the active call and configure the current call token.")
    }
    let defaultPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        .appendingPathComponent("PairDesk/agent.sock").path
    let path = ProcessInfo.processInfo.environment["PAIRDESK_BRIDGE_SOCKET"] ?? defaultPath
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw BridgeError.message("Could not open PairDesk's local socket.") }
    defer { close(fd) }
    var timeout = timeval(tv_sec: method == "screenshot" ? 100 : 5, tv_usec: 0)
    _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    var noSignal: Int32 = 1
    _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8) + [0]
    guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw BridgeError.message("PairDesk socket path is too long.") }
    withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
    let connected = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard connected == 0 else { throw BridgeError.message("PairDesk local access is unavailable or has expired.") }
    let object: [String: String] = ["token": token, "method": method]
    let data = try JSONSerialization.data(withJSONObject: object) + Data([0x0a])
    let wrote = data.withUnsafeBytes { write(fd, $0.baseAddress, data.count) }
    guard wrote == data.count else { throw BridgeError.message("Could not send the local PairDesk request.") }
    guard let response = readLine(fd, limit: 4 * 1024 * 1024),
          let result = try JSONSerialization.jsonObject(with: response) as? [String: Any] else {
        throw BridgeError.message("PairDesk returned an invalid local response.")
    }
    guard result["ok"] as? Bool == true else {
        throw BridgeError.message(result["error"] as? String ?? "PairDesk denied this capability.")
    }
    return result["result"] as? [String: Any] ?? [:]
}

func readLine(_ fd: Int32, limit: Int) -> Data? {
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

enum BridgeError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { return text }; return nil }
}
