import Foundation

/// A direct, user-initiated text clipboard offer. It is deliberately not a
/// clipboard monitor or a general pasteboard synchronization protocol.
struct ClipboardTransferMessage: Codable, Equatable {
    static let version = 1
    static let maximumTextBytes = 64 * 1024
    static let maximumWireBytes = 66 * 1024
    static let lifetime: TimeInterval = 120

    let version: Int
    let id: UUID
    let recipientIdentity: String
    let createdAt: Date
    let text: String

    init(id: UUID = UUID(), recipientIdentity: String, createdAt: Date = .now, text: String) throws {
        guard !recipientIdentity.isEmpty, recipientIdentity.utf8.count <= 256 else {
            throw ClipboardTransferError.invalidRecipient
        }
        guard !text.isEmpty else { throw ClipboardTransferError.emptyText }
        guard text.utf8.count <= Self.maximumTextBytes else { throw ClipboardTransferError.textTooLarge }
        self.version = Self.version
        self.id = id
        self.recipientIdentity = recipientIdentity
        self.createdAt = createdAt
        self.text = text
    }

    static func decode(_ data: Data, authenticatedSender: String, localIdentity: String,
                       now: Date = .now) throws -> ClipboardTransferMessage {
        guard data.count <= maximumWireBytes else { throw ClipboardTransferError.messageTooLarge }
        let message: ClipboardTransferMessage
        do { message = try JSONDecoder().decode(Self.self, from: data) }
        catch { throw ClipboardTransferError.malformedMessage }
        guard message.version == version else { throw ClipboardTransferError.unsupportedVersion }
        guard !authenticatedSender.isEmpty, authenticatedSender != localIdentity else {
            throw ClipboardTransferError.invalidSender
        }
        guard message.recipientIdentity == localIdentity else { throw ClipboardTransferError.wrongRecipient }
        guard message.text.utf8.count <= maximumTextBytes else { throw ClipboardTransferError.textTooLarge }
        guard message.createdAt <= now.addingTimeInterval(5),
              now.timeIntervalSince(message.createdAt) <= lifetime else {
            throw ClipboardTransferError.expired
        }
        return message
    }

    func encoded() throws -> Data {
        let data = try JSONEncoder().encode(self)
        guard data.count <= Self.maximumWireBytes else { throw ClipboardTransferError.messageTooLarge }
        return data
    }
}
enum ClipboardTransferError: Error, Equatable {
    case invalidRecipient
    case emptyText
    case textTooLarge
    case messageTooLarge
    case malformedMessage
    case unsupportedVersion
    case invalidSender
    case wrongRecipient
    case expired
    case replayed
}

/// Keeps a bounded in-memory replay window. Sender identity comes from the
/// LiveKit callback, never from clipboard JSON supplied by the remote peer.
struct ClipboardTransferReplayWindow {
    private(set) var seen = Set<UUID>()
    private var insertionOrder: [UUID] = []
    let capacity: Int

    init(capacity: Int = 128) { self.capacity = max(1, capacity) }

    mutating func insert(_ id: UUID) -> Bool {
        guard seen.insert(id).inserted else { return false }
        insertionOrder.append(id)
        if insertionOrder.count > capacity {
            seen.remove(insertionOrder.removeFirst())
        }
        return true
    }
}
