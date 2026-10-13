import AppKit
import SwiftUI

struct ClipboardPeer: Identifiable, Equatable {
    let identity: String
    let name: String
    var id: String { identity }
}

/// Embeddable in-call clipboard UI. Reading the local pasteboard only happens
/// after the sender presses Send; writing it only happens after the receiver
/// presses Paste on this Mac.
struct ClipboardTransferView: View {
    let peers: [ClipboardPeer]
    let incoming: (senderName: String, message: ClipboardTransferMessage)?
    let onSend: (String, String) async throws -> Void
    let onPaste: () -> Void
    let onDismiss: () -> Void
    let clipboardSyncEnabled: Bool
    let clipboardSyncNotice: String?
    let onToggleSync: (Bool) -> Void

    @State private var selectedPeerIdentity = ""
    @State private var status: String?
    @State private var sending = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Sync text clipboard during this call", isOn: Binding(
                get: { clipboardSyncEnabled },
                set: onToggleSync
            ))
            .font(.callout.weight(.medium))
            Text("Enable this on both Macs for direct Cmd+C / Cmd+V. Copied plain text is shared with everyone on this call; images and files are not transferred.")
                .font(.caption).foregroundStyle(.secondary)

            if !peers.isEmpty {
                HStack(spacing: 8) {
                    Picker("Send to", selection: $selectedPeerIdentity) {
                        ForEach(peers) { peer in Text(peer.name).tag(peer.identity) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity)

                    Button {
                        sendClipboard()
                    } label: {
                        Label("Send clipboard", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(selectedPeerIdentity.isEmpty || sending)
                }
            } else {
                Text("Join a call with someone to share clipboard text.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if let incoming {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Clipboard text from \(incoming.senderName)")
                        .font(.caption.weight(.semibold))
                    Text(incoming.message.text)
                        .font(.caption)
                        .lineLimit(3)
                        .textSelection(.enabled)
                    HStack {
                        Button("Paste on this Mac", action: onPaste).buttonStyle(PrimaryButtonStyle())
                        Button("Dismiss", action: onDismiss).buttonStyle(QuietButtonStyle(compact: true))
                    }
                }
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }

            if let clipboardSyncNotice { Text(clipboardSyncNotice).font(.caption).foregroundStyle(.secondary) }
            if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
        }
        .onChange(of: peers) { _, newPeers in
            if !newPeers.contains(where: { $0.identity == selectedPeerIdentity }) {
                selectedPeerIdentity = newPeers.first?.identity ?? ""
            }
        }
        .onAppear {
            if selectedPeerIdentity.isEmpty { selectedPeerIdentity = peers.first?.identity ?? "" }
        }
    }

    private func sendClipboard() {
        // This explicit button is the only path that reads the system pasteboard.
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            status = "There is no text in the clipboard."
            return
        }
        guard text.utf8.count <= ClipboardTransferMessage.maximumTextBytes else {
            status = "Text is larger than the 64 KB sharing limit."
            return
        }
        guard !selectedPeerIdentity.isEmpty else { return }
        let peer = selectedPeerIdentity
        sending = true
        status = "Sending…"
        Task {
            // The status reports the outcome, not the attempt: a clip that
            // exceeds the transport's packet limits fails here, visibly.
            do { try await onSend(text, peer); status = "Sent clipboard text." }
            catch { status = error.localizedDescription }
            sending = false
        }
    }

}
