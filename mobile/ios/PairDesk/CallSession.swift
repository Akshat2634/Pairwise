import Foundation
import AVFAudio
import AVFoundation
import LiveKit

struct CameraTile: Identifiable {
    let id: String
    let name: String
    let track: VideoTrack
}

@MainActor @Observable final class CallSession: NSObject, RoomDelegate {
    private(set) var room: Room?
    private(set) var microphoneOn = false
    private(set) var cameraOn = false
    var speakerOn = false
    @ObservationIgnored private var speakerOverrideActive = false
    private(set) var connected = false
    private(set) var videoTiles: [CameraTile] = []

    override init() { super.init() }

    func join(url: String, token: String, startMicrophone: Bool = true) async throws {
        await leave()
        let room = Room(delegate: self)
        self.room = room
        do {
            try await room.connect(url: url, token: token)
            connected = true
            if startMicrophone {
                try await room.localParticipant.setMicrophone(enabled: true)
                microphoneOn = true
            }
            refreshVideoTiles()
        } catch {
            await leave()
            throw error
        }
    }
    func toggleMicrophone() async throws {
        guard let room else { return }
        try await room.localParticipant.setMicrophone(enabled: !microphoneOn)
        microphoneOn.toggle()
    }
    func activateMicrophoneAfterCallKit() async throws {
        guard let room, !microphoneOn else { return }
        try await room.localParticipant.setMicrophone(enabled: true)
        microphoneOn = true
    }
    func deactivateMicrophoneForCallKit() async {
        guard let room, microphoneOn else { return }
        try? await room.localParticipant.setMicrophone(enabled: false)
        microphoneOn = false
    }
    func toggleCamera() async throws {
        guard let room else { return }
        if !cameraOn {
            let allowed = await AVCaptureDevice.requestAccess(for: .video)
            guard allowed else { throw APIError(message: "Camera access is off. Enable PairDesk in Settings > Privacy & Security > Camera.") }
        }
        _ = try await room.localParticipant.setCamera(enabled: !cameraOn, captureOptions: CameraCaptureOptions())
        cameraOn.toggle()
        refreshVideoTiles()
    }
    func refreshVideoTiles() {
        guard let room else { videoTiles = []; return }
        var tiles: [CameraTile] = []
        if let track = room.localParticipant.firstCameraVideoTrack {
            tiles.append(CameraTile(id: "local", name: "You", track: track))
        }
        for person in room.remoteParticipants.values {
            if let identity = person.identity?.stringValue, let track = person.firstCameraVideoTrack {
                tiles.append(CameraTile(id: identity, name: person.name ?? "Teammate", track: track))
            }
        }
        videoTiles = tiles
    }
    func setSpeaker(_ enabled: Bool) throws {
        try AVAudioSession.sharedInstance().overrideOutputAudioPort(enabled ? .speaker : .none)
        speakerOverrideActive = enabled
        speakerOn = enabled
    }
    func leave() async {
        if speakerOverrideActive { try? AVAudioSession.sharedInstance().overrideOutputAudioPort(.none) }
        speakerOverrideActive = false
        if let room { await room.disconnect() }
        room = nil; connected = false; microphoneOn = false; cameraOn = false; speakerOn = false; videoTiles = []
    }

    nonisolated func room(_ room: Room, participant: LocalParticipant, didPublishTrack publication: LocalTrackPublication) {
        Task { @MainActor [weak self] in self?.refreshVideoTiles() }
    }
    nonisolated func room(_ room: Room, participant: LocalParticipant, didUnpublishTrack publication: LocalTrackPublication) {
        Task { @MainActor [weak self] in self?.refreshVideoTiles() }
    }
    nonisolated func room(_ room: Room, participant: RemoteParticipant, didPublishTrack publication: RemoteTrackPublication) {
        Task { @MainActor [weak self] in self?.refreshVideoTiles() }
    }
    nonisolated func room(_ room: Room, participant: RemoteParticipant, didUnpublishTrack publication: RemoteTrackPublication) {
        Task { @MainActor [weak self] in self?.refreshVideoTiles() }
    }
    nonisolated func room(_ room: Room, participant: RemoteParticipant, didSubscribeTrack publication: RemoteTrackPublication) {
        Task { @MainActor [weak self] in self?.refreshVideoTiles() }
    }
    nonisolated func room(_ room: Room, participant: RemoteParticipant, didUnsubscribeTrack publication: RemoteTrackPublication) {
        Task { @MainActor [weak self] in self?.refreshVideoTiles() }
    }
}
