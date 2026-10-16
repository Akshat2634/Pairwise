import Foundation

/// The SDK's default-route alias can have the same name as a physical device.
struct AudioDeviceChoice: Identifiable, Equatable {
    let id: String
    let name: String
    let isDefault: Bool

    var title: String { isDefault ? "System default" : name }

    static func unique(_ choices: [AudioDeviceChoice]) -> [AudioDeviceChoice] {
        var seen = Set<String>()
        return choices.filter { seen.insert($0.id).inserted }
    }
}
