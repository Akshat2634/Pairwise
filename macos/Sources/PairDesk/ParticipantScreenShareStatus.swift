import SwiftUI

struct ParticipantScreenShareStatus: View {
    let participant: CallParticipant
    let sharerIdentity: String?

    var body: some View {
        if participant.identity == sharerIdentity {
            Label("Sharing screen", systemImage: "display")
                .font(.caption)
                .foregroundStyle(Theme.accent)
                .fixedSize()
                .accessibilityLabel("\(participant.name), sharing screen")
        }
    }
}
