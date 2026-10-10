import XCTest
@testable import PairDesk

final class AppTests: XCTestCase {
    func testPrivateTokensRequireHTTPSOutsideLoopback() throws {
        XCTAssertThrowsError(try APIClient(server: "http://192.168.1.1:8080"))
        XCTAssertThrowsError(try APIClient(server: "https://user:secret@example.com"))
        XCTAssertThrowsError(try APIClient(server: "https://example.com/path"))
        XCTAssertNoThrow(try APIClient(server: "http://127.0.0.1:8080"))
        XCTAssertNoThrow(try APIClient(server: "https://pair.example.com"))
    }
    func testPortraitLetterboxRejectsOutsideClicks() {
        let box = CGRect(x: 0, y: 0, width: 1000, height: 600)
        let screen = CGSize(width: 600, height: 1000)
        XCTAssertNil(ScreenCoordinateMapper.normalized(point: CGPoint(x: 100, y: 300), container: box, contentSize: screen))
        let center = ScreenCoordinateMapper.normalized(point: CGPoint(x: 500, y: 300), container: box, contentSize: screen)
        XCTAssertEqual(center?.x, 0.5)
        XCTAssertEqual(center?.y, 0.5)
    }
    func testLandscapeLetterboxCoordinatesAreNotStretched() {
        let p = ScreenCoordinateMapper.normalized(point: CGPoint(x: 100, y: 50), container: CGRect(x: 0, y: 0, width: 200, height: 200), contentSize: CGSize(width: 200, height: 100))
        XCTAssertEqual(p?.x, 0.5)
        XCTAssertEqual(p?.y, 0)
        XCTAssertNil(ScreenCoordinateMapper.normalized(point: CGPoint(x: 100, y: 25), container: CGRect(x: 0, y: 0, width: 200, height: 200), contentSize: CGSize(width: 200, height: 100)))
    }
    func testBackendWireContractsDecode() throws {
        let data = Data(#"{"room":{"id":"abc","name":"Debugging","participantCount":1,"participants":[{"id":"u1","name":"Sam","email":"sam@example.com"}]},"url":"wss://rtc.example.com","token":"opaque","participantIdentity":"u1"}"#.utf8)
        let join = try JSONDecoder().decode(JoinResponse.self, from: data)
        XCTAssertEqual(join.participantIdentity, join.room.participants.first?.id)
    }
}
