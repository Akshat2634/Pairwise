import SwiftUI

/// A named, readable state rather than relying on color or speech activity.
struct ParticipantMicrophoneStatus: View {
    let participant: CallParticipant

    private var status: String {
        participant.isMicrophoneMuted ? "Muted" : (participant.isSpeaking ? "Speaking" : "Mic on")
    }

    var body: some View {
        Label {
            Text(status).foregroundStyle(.primary)
        } icon: {
            Image(systemName: participant.isMicrophoneMuted ? "mic.slash.fill" :
                  (participant.isSpeaking ? "waveform" : "mic.fill"))
                .foregroundStyle(participant.isMicrophoneMuted ? Theme.attention :
                                 (participant.isSpeaking ? Theme.online : Theme.textMuted))
        }
            .font(.caption)
            .fixedSize()
            .accessibilityLabel("\(participant.name), \(status)")
    }
}
