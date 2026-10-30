import SwiftUI

/// Shared by the menu-bar call list and the screen viewer's participant strip.
struct PendingCallParticipantRow: View {
    @ObservedObject var store: AppStore
    let invitation: CallInvitation

    var body: some View {
        HStack(spacing: 10) {
            PersonAvatar(name: invitation.target.name, id: invitation.target.id, size: 28).opacity(0.6)
            VStack(alignment: .leading, spacing: 1) {
                Text(invitation.target.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(invitation.pendingParticipantLabel(viewerID: store.user?.id))
                    .font(.caption).foregroundStyle(Theme.textMuted).lineLimit(1)
            }
            Spacer(minLength: 4)
            if invitation.canCancelPendingInvitation(userID: store.user?.id) {
                Button("Cancel") { Task { await store.cancelCall(invitation) } }
                    .buttonStyle(QuietButtonStyle(compact: true))
            }
        }
    }
}
