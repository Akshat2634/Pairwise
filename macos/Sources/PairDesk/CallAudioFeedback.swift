import AVFoundation
import Foundation

@MainActor
protocol CallTonePlaying: AnyObject {
    var numberOfLoops: Int { get set }
    @discardableResult func play() -> Bool
    func stop()
}

extension AVAudioPlayer: CallTonePlaying {}

enum CallTone {
    case ringing, calling, connected, disconnected

    /// Original, quiet PCM tones; no downloaded sounds or system alert-volume dependency.
    var wavData: Data {
        let sampleRate = 24_000
        let duration: Double
        switch self {
        case .ringing, .calling: duration = 3
        case .connected: duration = 0.65
        case .disconnected: duration = 0.45
        }
        let count = Int(duration * Double(sampleRate))
        var pcm = Data(capacity: count * 2)
        for index in 0..<count {
            let time = Double(index) / Double(sampleRate)
            let start: Double
            let length: Double
            let frequencies: [Double]
            switch self {
            case .ringing:
                start = time < 0.5 ? 0 : 0.65
                length = 0.5
                frequencies = [440, 554.37]
            case .calling:
                start = 0
                length = 1
                frequencies = [440, 480]
            case .connected:
                start = floor(time / 0.18) * 0.18
                length = time < 0.54 ? 0.16 : 0
                frequencies = [time < 0.18 ? 523.25 : (time < 0.36 ? 659.25 : 783.99)]
            case .disconnected:
                start = time < 0.20 ? 0 : 0.20
                length = 0.18
                frequencies = [time < 0.20 ? 659.25 : 440]
            }
            let localTime = time - start
            let envelope = localTime >= 0 && localTime < length
                ? max(0, min(1, min(localTime / 0.015, (length - localTime) / 0.04))) : 0
            let wave = frequencies.reduce(0) { $0 + sin(2 * .pi * $1 * time) } / Double(frequencies.count)
            var sample = Int16(wave * envelope * 0.18 * Double(Int16.max)).littleEndian
            withUnsafeBytes(of: &sample) { pcm.append(contentsOf: $0) }
        }
        var data = Data("RIFF".utf8)
        func append<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        append(UInt32(36 + pcm.count))
        data.append(Data("WAVEfmt ".utf8))
        append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(sampleRate)); append(UInt32(sampleRate * 2))
        append(UInt16(2)); append(UInt16(16))
        data.append(Data("data".utf8)); append(UInt32(pcm.count)); data.append(pcm)
        return data
    }
}

/// State follows invitations and actual media presence, never a view appearing or a poll tick.
@MainActor
final class CallAudioFeedback {
    private let makePlayer: (CallTone) -> CallTonePlaying?
    private var ring: CallTonePlaying?
    private var calling: CallTonePlaying?
    private var transitionTone: CallTonePlaying?
    private var ringingID: String?
    private var callingID: String?
    private var silencedID: String?
    private var wasConnected = false

    init(makePlayer: @escaping (CallTone) -> CallTonePlaying? = { try? AVAudioPlayer(data: $0.wavData) }) {
        self.makePlayer = makePlayer
    }

    func update(incomingID: String?, outgoingID: String? = nil, connected: Bool, enabled: Bool) {
        if incomingID != silencedID { silencedID = nil }
        let desiredRing = enabled && !connected && incomingID != silencedID ? incomingID : nil
        if desiredRing != ringingID {
            ring?.stop()
            ring = nil
            ringingID = desiredRing
            if desiredRing != nil {
                ring = makePlayer(.ringing)
                ring?.numberOfLoops = -1
                ring?.play()
            }
        }
        let desiredCalling = enabled && !connected && incomingID == nil ? outgoingID : nil
        if desiredCalling != callingID {
            calling?.stop()
            calling = nil
            callingID = desiredCalling
            if desiredCalling != nil {
                calling = makePlayer(.calling)
                calling?.numberOfLoops = -1
                calling?.play()
            }
        }
        if !enabled {
            transitionTone?.stop()
            transitionTone = nil
        } else if connected != wasConnected {
            transitionTone?.stop()
            transitionTone = makePlayer(connected ? .connected : .disconnected)
            transitionTone?.play()
        }
        wasConnected = connected
    }

    func silenceIncoming(_ id: String) {
        silencedID = id
        ring?.stop()
        ring = nil
        ringingID = nil
    }

    func retryIncoming() { silencedID = nil }
}
