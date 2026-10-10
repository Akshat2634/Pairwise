import Foundation
import ScreenCaptureKit

/// Uses Apple's native picker and limits capture access to one user-selected display or window.
@available(macOS 14.0, *)
@MainActor
final class SystemScreenPicker: NSObject, @preconcurrency SCContentSharingPickerObserver {
    static let shared = SystemScreenPicker()
    private var continuation: CheckedContinuation<SCContentFilter, Error>?

    func chooseDisplay() async throws -> SCContentFilter {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let picker = SCContentSharingPicker.shared
            var configuration = picker.defaultConfiguration
            configuration.allowedPickerModes = [.singleDisplay, .singleWindow]
            picker.defaultConfiguration = configuration
            picker.add(self)
            picker.isActive = true
            picker.present(using: .display)
        }
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        finish(.success(filter), picker: picker)
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        finish(.failure(CocoaError(.userCancelled)), picker: picker)
    }

    func contentSharingPickerStartDidFailWithError(_ error: Error) {
        finish(.failure(error), picker: .shared)
    }

    private func finish(_ result: Result<SCContentFilter, Error>, picker: SCContentSharingPicker) {
        picker.remove(self)
        picker.isActive = false
        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume(with: result)
    }
}
