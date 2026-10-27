import AppKit
import Testing
@testable import PairDesk

@Suite(.serialized) struct CallFlowRegressionTests {
    @Test @MainActor func mutedCallUpdatesAgentBridgeImmediatelyAndRevokesOnLeave() {
        _ = NSApplication.shared
        let store = AppStore(callAudio: CallAudioFeedback { _ in nil })
        let me = TeamUser(id: "me", name: "Fixture user", email: "me@example.invalid")
        store.user = me
        store.rtc.debugSetCall(participants: [CallParticipant(identity: me.id, name: me.name, isLocal: true)], microphoneEnabled: false)
        store.activeRoom = PairRoom(id: "room", name: "Fixture call", participantCount: 1, participants: [me])
        #expect(store.agentBridge.hasActiveCall)
        store.activeRoom = nil
        #expect(!store.agentBridge.hasActiveCall)
    }

    @Test @MainActor func cachedMediaWindowStopsTestsOnBothHideAndClose() {
        _ = NSApplication.shared
        let tests = SettingsMediaTests()
        let window = MediaTestWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
                                     styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.stopMediaTests = { tests.stop() }
        window.orderFrontRegardless()
        let pendingPermissionGeneration = tests.generation
        window.orderOut(nil)
        #expect(tests.generation > pendingPermissionGeneration, "Pending permission completions must also be invalidated")
        window.orderFrontRegardless()
        let reopened = tests.generation
        window.close()
        #expect(tests.generation > reopened)
    }

    @Test func entireDisplayIsASuccessfulCropResult() {
        #expect(ScreenCropGeometry.sourceRect(normalizedCrop: nil, displaySize: CGSize(width: 1920, height: 1080)) == .zero)
        #expect(ScreenCropGeometry.sourceRect(normalizedCrop: nil, displaySize: .zero) == nil)
        #expect(ScreenCropGeometry.sourceRect(normalizedCrop: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
                                             displaySize: CGSize(width: 1920, height: 1080)) == CGRect(x: 480, y: 270, width: 960, height: 540))
    }

    @Test @MainActor func privacyReviewIsOptionalAndItsPreferenceSurvivesRestart() throws {
        let suite = "PairwiseSharingTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(try JSONEncoder().encode([HiddenApplication(bundleIdentifier: "com.example.private", name: "Private")]),
                     forKey: PrivacyVeilPreferences.defaultsKey)
        let first = PrivacyVeilPreferences(defaults: defaults)
        #expect(!first.reviewBeforeSharing)
        #expect(first.bundleIdentifiers == ["com.example.private"])
        first.reviewBeforeSharing = true
        first.hideNotificationBanners = true
        let restarted = PrivacyVeilPreferences(defaults: defaults)
        #expect(restarted.reviewBeforeSharing && restarted.hideNotificationBanners)
        #expect(restarted.bundleIdentifiers == first.bundleIdentifiers)
        restarted.reviewBeforeSharing = false
        #expect(!PrivacyVeilPreferences(defaults: defaults).reviewBeforeSharing)
    }

    @Test @MainActor func cameraSwitchOptionsPreserveEverySelectedQuality() {
        let saved = UserDefaults.standard.object(forKey: CameraVideoQuality.defaultsKey)
        defer { UserDefaults.standard.set(saved, forKey: CameraVideoQuality.defaultsKey) }
        let rtc = RTCService()
        for quality in CameraVideoQuality.allCases {
            rtc.setCameraVideoQuality(quality)
            let options = rtc.cameraCaptureOptions()
            #expect(options.dimensions == quality.dimensions)
            #expect(options.fps == quality.framesPerSecond)
        }
    }
}
