import Foundation

struct CameraDeviceChoice: Identifiable, Equatable {
    let id: String
    let name: String
}

enum CameraDeviceSelection {
    static func resolve(savedID: String?, available: [CameraDeviceChoice]) -> (id: String?, savedDeviceUnavailable: Bool) {
        guard !available.isEmpty else { return (nil, savedID != nil) }
        if let savedID, available.contains(where: { $0.id == savedID }) {
            return (savedID, false)
        }
        return (available[0].id, savedID != nil)
    }
}
