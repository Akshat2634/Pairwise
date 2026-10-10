# Upstream source changes

## LiveKit Swift client 2.17.0

The source under `vendor/livekit-client-swift/` is based on LiveKit's Apache-2.0 client SDK at commit `f07831a7f06bca9e2fc2e136db591b7b42f16d8d`. The upstream copyright headers, `LICENSE`, and `NOTICE` are retained.

Pairwise adds a `LocalVideoTrack.createMacOSScreenShareTrack(contentFilter:options:)` overload to `Sources/LiveKit/Track/Capturers/MacOSScreenCapturer.swift`. It lets the app pass the `SCContentFilter` that macOS returns from `SCContentSharingPicker` directly to `SCStream`. Existing upstream source-enumeration APIs remain intact for other SDK consumers. Pairwise's app code uses the system-picker overload and does not call `SCShareableContent` to enumerate the desktop.

To refresh the vendor, start from the pinned upstream commit, reapply this small overload and capturer initializer, run the macOS tests, and review the upstream license and API changes before updating this record.
