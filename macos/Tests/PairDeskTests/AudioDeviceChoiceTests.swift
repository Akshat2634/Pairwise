import XCTest
@testable import PairDesk

final class AudioDeviceChoiceTests: XCTestCase {
    func testSystemDefaultAliasDoesNotRepeatTheHardwareLabel() {
        let choices = AudioDeviceChoice.unique([
            .init(id: "default", name: "MacBook Pro Microphone", isDefault: true),
            .init(id: "built-in-mic", name: "MacBook Pro Microphone", isDefault: false),
            .init(id: "phone-mic", name: "iPhone Microphone", isDefault: false)
        ])
        XCTAssertEqual(choices.map(\.title), ["System default", "MacBook Pro Microphone", "iPhone Microphone"])
        XCTAssertEqual(choices.map(\.id), ["default", "built-in-mic", "phone-mic"])
    }

    func testRepeatedDeviceIDsAreRemovedWithoutHidingDistinctHardware() {
        let choices = AudioDeviceChoice.unique([
            .init(id: "default", name: "USB Speaker", isDefault: true),
            .init(id: "default", name: "USB Speaker", isDefault: true),
            .init(id: "usb-1", name: "USB Speaker", isDefault: false),
            .init(id: "usb-1", name: "USB Speaker", isDefault: false),
            .init(id: "usb-2", name: "USB Speaker", isDefault: false)
        ])
        XCTAssertEqual(choices.map(\.id), ["default", "usb-1", "usb-2"])
        XCTAssertEqual(choices.map(\.title), ["System default", "USB Speaker", "USB Speaker"])
    }

    func testDefaultRouteKeepsItsSelectionWhenTheSystemChangesDevices() {
        let builtIn = AudioDeviceChoice(id: "default", name: "MacBook Pro Speakers", isDefault: true)
        let headphones = AudioDeviceChoice(id: "default", name: "Headphones", isDefault: true)
        XCTAssertEqual(builtIn.id, headphones.id)
        XCTAssertEqual(builtIn.title, headphones.title)
        XCTAssertTrue(AudioDeviceChoice.unique([]).isEmpty)
    }
}
