# Pairwise product parity and improvement plan

Assessment date: 10 October 2026. This compares the current Pairwise source and recorded verification against publicly documented Tuple and Hopp capabilities. A feature marked implemented in code is not automatically considered accepted on physical Macs; the hardware acceptance record remains pending.

## Product boundary

Pairwise is a macOS-first, open-source pairing client for a 10–15 person internal team, with roughly 3–4 people in a call. The product should make it easy to find a teammate, call them, share a display, talk, and collaborate on the remote Mac. Keep voice and screen sharing; do not add camera sharing, call recording, cloud transcription, SSO, calendar/chat integrations, public guest access, or unattended access as part of this roadmap.

## Current feature parity

| Capability | Pairwise now | Tuple / Hopp benchmark | Assessment |
|---|---|---|---|
| Team and presence | Admin-provisioned email/password accounts; online, offline, and busy roster; direct call and Add person; private call sessions | Tuple supports direct calls to available contacts and team administration. Hopp emphasizes click-a-teammate pairing and rooms, up to 10 | Good fit for the internal team. Keep the room as transport detail. Current room cap is four, matching expected concurrency but limiting future growth. |
| Voice | LiveKit voice, explicit microphone enable/mute, no camera | Tuple documents device selection, noise suppression, ringtones, and start-muted preference. Hopp advertises noise cancellation and keeps the last selected mic | Partial. No visible input/output selector, mic test, start-muted preference, or adequate quality/recovery feedback. |
| Screen share | ScreenCaptureKit `SCContentSharingPicker`, currently restricted to one display; 30 fps, 5 Mbps target; screen opens in a dedicated viewer | Tuple documents display switching and cropped regions. Hopp documents display/window sharing, high-resolution streaming, and a developer-oriented viewer | Good privacy foundation; partial source and quality controls. Pairwise should offer display and window selection, quick switching, and sensible resolution adaptation. |
| Remote input | Accessibility-gated mouse, keyboard, modifiers, clicks, and scroll; automatic first-interaction control after host starts sharing; renewable short lease, host stop/resume, emergency shortcut | Tuple and Hopp treat low-friction shared control as central. Hopp also exposes shared cursors, drawing, and control state | Core protocol exists, but physical two-Mac behavior is not accepted. Pairwise records remote pointer positions but does not render them. Control state and host takeover need stronger visible feedback. |
| macOS permissions | Native screen-sharing picker avoids a separate broad Screen Recording permission on macOS 14+; microphone permission is needed for voice; Accessibility is needed on the host for injected input | Apple says the picker scopes capture to what the person explicitly selects and removes the need for separate screen-capture permission. Both Tuple/Hopp still operate within macOS user-consent boundaries | The picker materially reduces setup friction. The capability-based setup panel and copy-location guidance are implemented; physical denied/revoked/update flows remain to be accepted. Ad-hoc signing still means permission approval may need repeating after an update. |
| Transcription | Optional local Whisper Tiny transcript, in-memory by default, user-triggered text export | Tuple documents local capture/transcription options; broad recording features are outside Pairwise's scope | Appropriate differentiator for privacy. Improve only around local consent, clear status, cancellation, crash cleanup, and technical vocabulary quality. |
| Install and updates | Build/package scripts and test DMGs exist; automatic login-item support exists | Tuple and Hopp offer packaged apps and update paths | Not release-ready. No Developer ID identity is installed, no notarized public release exists, and no in-app updater is implemented. Source ZIP is not an installer. |
| Reliability and diagnostics | API/LiveKit integration tests, race tests, TURN/TLS checks, synthetic screen transport tests | Mature calling tools provide reconnect handling, clear call state, and support diagnostics | Automated transport evidence is useful, but actual voice, capture, control, sleep/wake, display changes, and latest macOS permission behavior need two physical Macs. No end-user connection-quality panel exists. |
| Administration and operations | Manual account creation in app; bootstrap and deployment tooling; GCP test deployment | Tuple includes team roles, account management, integrations, and SSO; Hopp offers self-hosting and managed service | Current choices fit a small team. Prioritize admin password reset/disable and production monitoring/backups before adding enterprise identity. |

## Permission answer

Screen sharing is no longer designed around asking users to switch on the broad Screen Recording toggle. Pairwise calls Apple's native content-sharing picker and asks the user to select the display. Apple describes that explicit picker flow as allowing the selected content to be captured for that session without separate screen-capture permission. That choice and system indicator are part of macOS privacy and should remain.

There are still two expected permission decisions: microphone access when using voice, and Accessibility on the Mac being shared if the teammate should control its mouse and keyboard. Apple requires the local user to authorize these. The app can explain the request, open the right Settings pane, detect current access, and remain useful when remote control is unavailable; it cannot grant the permission for them.

The repeat-permission problem is not fully solved for distributed builds. The source still packages an ad-hoc test build, the hardware acceptance checklist says signing is pending, and the UI warns that ad-hoc updates may need fresh approval. A stable Developer ID-signed and notarized build is the release path to validate permission persistence and prevent Gatekeeper's unsigned-app warning. This needs the team's Apple Developer identity. Until that exists, treat each ad-hoc rebuild as a new permission/installation test and avoid telling teammates that permissions are permanently fixed.

The global “Finish permission setup” warning was removed. The menu-bar now surfaces missing microphone access only during a call when the person tries to speak, and remote-control setup only while sharing. The permission window distinguishes microphone, native picker sharing, and optional host Accessibility access; it shows the bundle identifier and explains when the app is running from a disk image or another copy. The UI cannot override Apple's consent or the signature identity of an ad-hoc build. Physical grant/deny/revoke and update flows remain release acceptance work.

## What we should build next

### P0 — Make macOS distribution and permission identity dependable

Produce a stable signed, notarized, stapled app and DMG from a repeatable release workflow. Verify Gatekeeper acceptance and test an in-place upgrade with existing microphone and Accessibility approvals. Publish versioned installable assets and checksums. Until signing is available, keep a clearly labeled development build and state its permission limitations.

### P1 — Close the real-Mac acceptance gap

Run the complete call with two physical Macs on current macOS: clean install, voice, screen picker, readable shared display, automatic remote control, owner takeover, Stop/Resume, emergency stop, hangup on either side, reconnection, sleep/wake, external display changes, denied/revoked permissions, and restart. Repeat with three or four participants and distant networks. Fix observed failures before calling the feature complete.

### P1 — Make permission onboarding capability-based

Use three explicit states: Voice needs Microphone; Share screen opens the macOS picker; Remote control needs Accessibility on the sharing Mac. Do not make Accessibility setup a prerequisite for calling or viewing. If a grant is missing, explain what remains usable and provide a direct Settings link plus a retry check. Detect when the app is running from a disk image or a different copy and identify the app path/signature when macOS reports stale access. Do not continuously reopen settings or trap the user in an onboarding window.

### P1 — Make control state obvious and recoverable

Show who is sharing, who is controlling, and whether control is active, waiting, paused, or unavailable on both Macs. Render the collaborator cursor with a name/color. Keep a one-action host takeover/stop affordance visible while sharing. Preserve the existing safe lease/release behavior and verify held keys/buttons are cleared after every focus, network, app, display, and call transition. Add pointer/laser annotations after cursor and permission correctness are accepted.

### P1 — Improve the shared-screen canvas

Offer display and window sources with a clear switch-source control during a call. Keep the shared content large and aspect-correct at normal and Retina sizes, allow a reliable full-screen viewer, and make control/focus state visible without covering code. Measure quality over real worldwide connections before selecting higher bitrates; use adaptive resolution/frame rate and expose a simple connection-quality indicator.

### P2 — Bring voice to daily-use quality

Add microphone and output-device selection, a mic test/meter, start-muted preference, reliable device hot-plug recovery, clear mute state, and noise suppression if the LiveKit pipeline can provide it without harming latency. Keep microphone activation explicit and never turn it on at app launch.

### P2 — Finish internal operations

Add administrator password reset and account disable/enable in the app. Add health/uptime and backup-restore checks for the GCP services, a call diagnostics bundle that omits secrets/audio/screen content, and a versioned release/update path. Keep SSO, external integrations, and enterprise audit features out of this phase.

## Deliberately not pursuing now

Camera/video, call recording, cloud transcripts, public guest links, cross-platform clients, broad file transfer, calendar/chat integrations, SSO/SCIM, unattended remote access, and enterprise policy controls. These increase permission, privacy, operational, or support burden without improving the stated small-team pairing workflow enough to justify them yet.

## References

- [Apple WWDC23: Screen Capture picker privacy model](https://developer.apple.com/videos/play/wwdc2023/10053/?time=1530)
- [Tuple screen-sharing guide](https://docs.tuple.app/article/46-sharing)
- [Tuple macOS audio preferences](https://docs.tuple.app/application-preferences/macos-preferences-audio)
- [Tuple documentation index](https://docs.tuple.app/)
- [Hopp project and self-hosting overview](https://github.com/gethopp/hopp)
- [Hopp feature documentation](https://docs.gethopp.app/)
- [Hopp macOS permission/onboarding and reliability changelog](https://www.gethopp.app/changelog)
