import XCTest
@testable import PairDesk

final class ClipboardTransferTests: XCTestCase {
    func testTextOfferRoundTripsOnlyForAuthenticatedIntendedRecipient() throws {
        let sent = try ClipboardTransferMessage(recipientIdentity: "bharat", text: "hello 👋")
        let bytes = try sent.encoded()
        let received = try ClipboardTransferMessage.decode(bytes, authenticatedSender: "harshit",
                                                             localIdentity: "bharat")
        XCTAssertEqual(received, sent)
    }

    func testRejectsWrongRecipientAndUnauthenticatedOrLocalSender() throws {
        let bytes = try ClipboardTransferMessage(recipientIdentity: "bharat", text: "hello").encoded()
        XCTAssertThrowsError(try ClipboardTransferMessage.decode(bytes, authenticatedSender: "harshit",
                                                                  localIdentity: "akshat")) {
            XCTAssertEqual($0 as? ClipboardTransferError, .wrongRecipient)
        }
        for sender in ["", "bharat"] {
            XCTAssertThrowsError(try ClipboardTransferMessage.decode(bytes, authenticatedSender: sender,
                                                                      localIdentity: "bharat")) {
                XCTAssertEqual($0 as? ClipboardTransferError, .invalidSender)
            }
        }
    }

    func testRejectsStaleOrFutureDatedOffers() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let stale = try ClipboardTransferMessage(recipientIdentity: "bharat",
                                                  createdAt: now.addingTimeInterval(-121), text: "old")
        XCTAssertThrowsError(try ClipboardTransferMessage.decode(stale.encoded(), authenticatedSender: "harshit",
                                                                  localIdentity: "bharat", now: now)) {
            XCTAssertEqual($0 as? ClipboardTransferError, .expired)
        }
        let future = try ClipboardTransferMessage(recipientIdentity: "bharat",
                                                   createdAt: now.addingTimeInterval(6), text: "future")
        XCTAssertThrowsError(try ClipboardTransferMessage.decode(future.encoded(), authenticatedSender: "harshit",
                                                                  localIdentity: "bharat", now: now)) {
            XCTAssertEqual($0 as? ClipboardTransferError, .expired)
        }
    }

    func testEnforcesPayloadAndWireLimits() throws {
        XCTAssertThrowsError(try ClipboardTransferMessage(recipientIdentity: "bharat",
                                                           text: String(repeating: "x", count: ClipboardTransferMessage.maximumTextBytes + 1))) {
            XCTAssertEqual($0 as? ClipboardTransferError, .textTooLarge)
        }
        XCTAssertThrowsError(try ClipboardTransferMessage.decode(Data(repeating: 0, count: ClipboardTransferMessage.maximumWireBytes + 1),
                                                                  authenticatedSender: "harshit", localIdentity: "bharat")) {
            XCTAssertEqual($0 as? ClipboardTransferError, .messageTooLarge)
        }
    }

    func testReplayWindowRejectsDuplicateAndEvictsOldestWithinBound() {
        var window = ClipboardTransferReplayWindow(capacity: 2)
        let first = UUID(), second = UUID(), third = UUID()
        XCTAssertTrue(window.insert(first))
        XCTAssertFalse(window.insert(first))
        XCTAssertTrue(window.insert(second))
        XCTAssertTrue(window.insert(third))
        XCTAssertFalse(window.seen.contains(first))
        XCTAssertTrue(window.insert(first))
    }
}
