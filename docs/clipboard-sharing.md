# Clipboard sharing

Pairwise can move plain text between Macs in the same call. The Clipboard button in the shared-screen toolbar offers two modes:

- **Send clipboard** sends the current text to one teammate. The recipient reviews the offer and chooses **Paste on this Mac**.
- **Sync text clipboard during this call** is opt-in on each Mac. Once enabled, copying plain text with `Cmd+C` shares it with the other call participants, so `Cmd+V` works on their Mac. Each Mac must enable sync. It turns off when the call ends.

Images and files are not transferred. Text is limited to 64 KiB, sent only to current call participants over the call's reliable data channel, and accepted only for its intended recipient. Sync reads the system text clipboard only while its toggle is on; it does not run in the background or outside a call. Turning sync off stops the local clipboard watcher immediately. If only one person enables sync, received text is presented as a reviewable paste offer instead of being written automatically.

This is an early implementation. Test with non-sensitive text first. Password managers and other apps may put sensitive material on the clipboard; do not enable sync when you do not want copied text shared with everyone in the call.
