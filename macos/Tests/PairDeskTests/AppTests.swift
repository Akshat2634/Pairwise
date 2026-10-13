import XCTest
@testable import PairDesk

final class AppTests: XCTestCase {
    func testMicrophoneMeterIsSilentForEmptyAndClampsRMS() {
        XCTAssertEqual(AudioMeter.level(samples: []), 0)
        XCTAssertEqual(AudioMeter.level(samples: [0, 0, 0]), 0)
        XCTAssertEqual(AudioMeter.level(samples: [0.5, -0.5]), 0.5, accuracy: 0.0001)
        XCTAssertEqual(AudioMeter.level(samples: [2, -2]), 1)
    }
    func testScreenNetworkQualityUsesMeasuredRTTAndHandlesMissingStats() {
        XCTAssertEqual(ScreenNetworkQuality.from(roundTripTimeSeconds: nil), .measuring)
        XCTAssertEqual(ScreenNetworkQuality.from(roundTripTimeSeconds: .nan), .measuring)
        XCTAssertEqual(ScreenNetworkQuality.from(roundTripTimeSeconds: 0.08), .good(roundTripMilliseconds: 80))
        XCTAssertEqual(ScreenNetworkQuality.from(roundTripTimeSeconds: 0.151), .fair(roundTripMilliseconds: 151))
        XCTAssertEqual(ScreenNetworkQuality.from(roundTripTimeSeconds: 0.301), .highLatency(roundTripMilliseconds: 301))
    }
    func testSupportDiagnosticsReduceErrorsToSafeCategories() {
        XCTAssertEqual(SupportDiagnostics.safeErrorCategory(nil), "none")
        XCTAssertEqual(SupportDiagnostics.safeErrorCategory("Accessibility permission denied for alice@example.com"), "permission")
        XCTAssertEqual(SupportDiagnostics.safeErrorCategory("Bearer secret-token connection failed"), "network")
        XCTAssertEqual(SupportDiagnostics.safeErrorCategory("Unexpected opaque error with private details"), "other (details omitted)")
    }
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
    func testRemotePointerMapsIntoAspectFitContentAndRejectsOutsideCoordinates() {
        let container = CGRect(x: 0, y: 0, width: 1000, height: 600)
        let size = CGSize(width: 200, height: 100)
        XCTAssertEqual(ScreenCoordinateMapper.displayedPoint(normalized: CGPoint(x: 0.5, y: 0.5), container: container, contentSize: size), CGPoint(x: 500, y: 300))
        XCTAssertEqual(ScreenCoordinateMapper.displayedPoint(normalized: CGPoint(x: 0, y: 0), container: container, contentSize: size), CGPoint(x: 0, y: 50))
        XCTAssertNil(ScreenCoordinateMapper.displayedPoint(normalized: CGPoint(x: 1.1, y: 0.5), container: container, contentSize: size))
    }
    func testPermissionGuidanceIdentifiesMountedImageAndInstalledCopies() {
        let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
        XCTAssertEqual(AppCopyLocation.classify(bundleURL: URL(fileURLWithPath: "/Applications/PairDesk.app"), homeDirectory: home), .applications)
        XCTAssertEqual(AppCopyLocation.classify(bundleURL: URL(fileURLWithPath: "/Users/example/Applications/PairDesk.app"), homeDirectory: home), .applications)
        XCTAssertEqual(AppCopyLocation.classify(bundleURL: URL(fileURLWithPath: "/Volumes/PairDesk/PairDesk.app"), homeDirectory: home), .diskImage)
        XCTAssertEqual(AppCopyLocation.classify(bundleURL: URL(fileURLWithPath: "/tmp/PairDesk.app"), homeDirectory: home), .other("/tmp/PairDesk.app"))
    }
    func testBackendWireContractsDecode() throws {
        let data = Data(#"{"room":{"id":"abc","name":"Debugging","participantCount":1,"participants":[{"id":"u1","name":"Sam","email":"sam@example.com"}]},"url":"wss://rtc.example.com","token":"opaque","participantIdentity":"u1"}"#.utf8)
        let join = try JSONDecoder().decode(JoinResponse.self, from: data)
        XCTAssertEqual(join.participantIdentity, join.room.participants.first?.id)
    }
    func testHostAccessibilityBlockIsReportedOverControlChannel() throws {
        let message = RemoteControlMessage(epoch: "", sequence: 1, kind: .hostPermissionRequired)
        let decoded = try JSONDecoder().decode(RemoteControlMessage.self, from: JSONEncoder().encode(message))
        XCTAssertEqual(decoded.kind, .hostPermissionRequired)
        XCTAssertFalse(RemoteControlState.hostPermissionRequired.isGranted)
    }
}
