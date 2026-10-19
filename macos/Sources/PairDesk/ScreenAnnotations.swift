import Foundation

struct ScreenAnnotationPoint: Codable, Equatable {
    let x: Double
    let y: Double

    var isValid: Bool { x.isFinite && y.isFinite && (0...1).contains(x) && (0...1).contains(y) }
}

struct ScreenAnnotationMessage: Codable, Equatable {
    enum Kind: String, Codable { case point, clear, availability }
    var version = 1
    let session: String
    var sequence: UInt64
    let kind: Kind
    var strokeID: String?
    var point: ScreenAnnotationPoint?
    /// Set by the sharer when relaying; never trusted on viewer-originated packets.
    var participantIdentity: String?
    var enabled: Bool?
}

struct ScreenAnnotationStroke: Identifiable, Equatable {
    let participantIdentity: String
    let strokeID: String
    var points: [ScreenAnnotationPoint]
    var id: String { "\(participantIdentity):\(strokeID)" }
}

enum ScreenAnnotationPolicy {
    static let maximumStrokeIDLength = 64

    static func acceptsViewer(_ message: ScreenAnnotationMessage, session: String?, senderIsParticipant: Bool,
                              hostEnabled: Bool, lastSequence: UInt64?) -> Bool {
        guard senderIsParticipant, message.version == 1, message.participantIdentity == nil,
              let session, !session.isEmpty, message.session == session,
              message.sequence > (lastSequence ?? 0) else { return false }
        switch message.kind {
        case .point:
            guard hostEnabled, let strokeID = message.strokeID, !strokeID.isEmpty,
                  strokeID.utf8.count <= maximumStrokeIDLength,
                  let point = message.point, point.isValid, message.enabled == nil else { return false }
            return true
        case .clear:
            return message.strokeID == nil && message.point == nil && message.enabled == nil
        case .availability:
            return false
        }
    }

    static func acceptsBroadcast(_ message: ScreenAnnotationMessage, session: String?, senderIsSharer: Bool,
                                 authorIsParticipant: Bool, lastSequence: UInt64?) -> Bool {
        guard senderIsSharer, authorIsParticipant, message.version == 1,
              let session, !session.isEmpty, message.session == session,
              message.sequence > (lastSequence ?? 0),
              let author = message.participantIdentity, !author.isEmpty else { return false }
        switch message.kind {
        case .point:
            guard let strokeID = message.strokeID, !strokeID.isEmpty,
                  strokeID.utf8.count <= maximumStrokeIDLength,
                  let point = message.point, point.isValid, message.enabled == nil else { return false }
            return true
        case .clear:
            return message.strokeID == nil && message.point == nil && message.enabled == nil
        case .availability:
            return message.strokeID == nil && message.point == nil && message.enabled != nil
        }
    }
}

struct ScreenAnnotationBook {
    static let maximumStrokes = 48
    static let maximumPointsPerStroke = 256
    private(set) var strokes: [ScreenAnnotationStroke] = []

    mutating func add(_ point: ScreenAnnotationPoint, strokeID: String, participantIdentity: String) {
        guard point.isValid, !strokeID.isEmpty, !participantIdentity.isEmpty else { return }
        let id = "\(participantIdentity):\(strokeID)"
        if let index = strokes.firstIndex(where: { $0.id == id }) {
            guard strokes[index].points.count < Self.maximumPointsPerStroke else { return }
            strokes[index].points.append(point)
        } else {
            if strokes.count >= Self.maximumStrokes { strokes.removeFirst() }
            strokes.append(ScreenAnnotationStroke(participantIdentity: participantIdentity, strokeID: strokeID, points: [point]))
        }
    }

    mutating func clear(participantIdentity: String? = nil) {
        guard let participantIdentity else { strokes.removeAll(); return }
        strokes.removeAll { $0.participantIdentity == participantIdentity }
    }
}

struct ScreenAnnotationRateLimiter {
    private var samplesBySender: [String: [TimeInterval]] = [:]

    mutating func accepts(sender: String, now: TimeInterval, maximumPerSecond: Int = 90) -> Bool {
        guard !sender.isEmpty, now.isFinite, maximumPerSecond > 0 else { return false }
        var recent = samplesBySender[sender, default: []].filter { now >= $0 && now - $0 < 1 }
        guard recent.count < maximumPerSecond else {
            samplesBySender[sender] = recent
            return false
        }
        recent.append(now)
        samplesBySender[sender] = recent
        return true
    }

    mutating func remove(sender: String) { samplesBySender.removeValue(forKey: sender) }
    mutating func reset() { samplesBySender.removeAll() }
}
