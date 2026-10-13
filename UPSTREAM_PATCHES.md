# Upstream source changes

## LiveKit Swift client 2.17.0

The source under `vendor/livekit-client-swift/` is based on LiveKit's Apache-2.0 client SDK at commit `f07831a7f06bca9e2fc2e136db591b7b42f16d8d`. The upstream copyright headers, `LICENSE`, and `NOTICE` are retained.

Pairwise adds a `LocalVideoTrack.createMacOSScreenShareTrack(contentFilter:options:)` overload to `Sources/LiveKit/Track/Capturers/MacOSScreenCapturer.swift`. It lets the app pass the `SCContentFilter` that macOS returns from `SCContentSharingPicker` directly to `SCStream`. Existing upstream source-enumeration APIs remain intact for other SDK consumers. Pairwise's app code uses the system-picker overload and does not call `SCShareableContent` to enumerate the desktop.

To refresh the vendor, start from the pinned upstream commit, reapply this small overload and capturer initializer, run the macOS tests, and review the upstream license and API changes before updating this record.

Pairwise also changes `MacOSScreenCapturer` and `ScreenShareCaptureOptions` for region sharing and adaptive quality:

- `ScreenShareCaptureOptions.sourceRect` (display-local, in points; `.zero` keeps full-display capture) is applied as `SCStreamConfiguration.sourceRect`.
- The stream is sized from the filter's first included display on macOS 15.2+ instead of always the main display.
- `MacOSScreenCapturer.updateScreenShareSettings(dimensions:fps:)` changes the output size and frame cadence of a live stream through `SCStream.updateConfiguration` without unpublishing the track. Capture state holds the current output dimensions, which the frame path uses instead of the immutable options.
