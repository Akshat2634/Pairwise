import XCTest
@testable import PairDesk

final class ScreenAnnotationsTests: XCTestCase {
    func testViewerPacketsRequireCurrentSessionParticipantAndBoundedCoordinates() {
        let valid = ScreenAnnotationMessage(session: "share-1", sequence: 1, kind: .point,
                                            strokeID: "stroke-1", point: .init(x: 0.4, y: 0.7))
        XCTAssertTrue(ScreenAnnotationPolicy.acceptsViewer(valid, session: "share-1", senderIsParticipant: true,
                                                           hostEnabled: true, lastSequence: nil))
        XCTAssertFalse(ScreenAnnotationPolicy.acceptsViewer(valid, session: "share-2", senderIsParticipant: true,
                                                            hostEnabled: true, lastSequence: nil))
        XCTAssertFalse(ScreenAnnotationPolicy.acceptsViewer(valid, session: "share-1", senderIsParticipant: false,
                                                            hostEnabled: true, lastSequence: nil))
        XCTAssertFalse(ScreenAnnotationPolicy.acceptsViewer(valid, session: "share-1", senderIsParticipant: true,
                                                            hostEnabled: false, lastSequence: nil))
        let invalidPoint = ScreenAnnotationMessage(session: "share-1", sequence: 2, kind: .point,
                                                   strokeID: "stroke-1", point: .init(x: .nan, y: 0.5))
        XCTAssertFalse(ScreenAnnotationPolicy.acceptsViewer(invalidPoint, session: "share-1", senderIsParticipant: true,
                                                            hostEnabled: true, lastSequence: 1))
        let spoofed = ScreenAnnotationMessage(session: "share-1", sequence: 2, kind: .point,
                                              strokeID: "stroke-1", point: .init(x: 0.5, y: 0.5),
                                              participantIdentity: "other-user")
        XCTAssertFalse(ScreenAnnotationPolicy.acceptsViewer(spoofed, session: "share-1", senderIsParticipant: true,
                                                            hostEnabled: true, lastSequence: 1))
        XCTAssertFalse(ScreenAnnotationPolicy.acceptsViewer(valid, session: "share-1", senderIsParticipant: true,
                                                            hostEnabled: true, lastSequence: 1))
    }

    func testBroadcastRequiresSharerAndAuthenticAuthor() {
        let message = ScreenAnnotationMessage(session: "share-1", sequence: 3, kind: .point,
                                              strokeID: "stroke-1", point: .init(x: 0, y: 1),
                                              participantIdentity: "viewer-1")
        XCTAssertTrue(ScreenAnnotationPolicy.acceptsBroadcast(message, session: "share-1", senderIsSharer: true,
                                                               authorIsParticipant: true, lastSequence: 2))
        XCTAssertFalse(ScreenAnnotationPolicy.acceptsBroadcast(message, session: "share-1", senderIsSharer: false,
                                                                authorIsParticipant: true, lastSequence: 2))
        XCTAssertFalse(ScreenAnnotationPolicy.acceptsBroadcast(message, session: "share-1", senderIsSharer: true,
                                                                authorIsParticipant: false, lastSequence: 2))
    }

    func testAnnotationBookBoundsStrokesAndClearsOneParticipant() {
        var book = ScreenAnnotationBook()
        for _ in 0..<300 {
            book.add(.init(x: 0.5, y: 0.5), strokeID: "stroke", participantIdentity: "viewer")
        }
        XCTAssertEqual(book.strokes.first?.points.count, ScreenAnnotationBook.maximumPointsPerStroke)
        book.add(.init(x: 0.25, y: 0.75), strokeID: "stroke-2", participantIdentity: "other")
        book.clear(participantIdentity: "viewer")
        XCTAssertEqual(book.strokes.map(\.participantIdentity), ["other"])
        book.clear()
        XCTAssertTrue(book.strokes.isEmpty)
    }

    func testAnnotationRateLimiterCapsBurstsPerParticipant() {
        var limiter = ScreenAnnotationRateLimiter()
        for index in 0..<90 {
            XCTAssertTrue(limiter.accepts(sender: "viewer", now: Double(index) / 100))
        }
        XCTAssertFalse(limiter.accepts(sender: "viewer", now: 0.9))
        XCTAssertTrue(limiter.accepts(sender: "viewer", now: 1.01))
        XCTAssertTrue(limiter.accepts(sender: "other", now: 0.9))
    }
}
