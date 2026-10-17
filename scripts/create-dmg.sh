#!/bin/bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "$0")/.." && pwd)
APP=${PAIRDESK_DISTRIBUTION_APP:-"$ROOT/dist/PairDesk.app"}
OUTPUT=${PAIRDESK_DMG_OUTPUT:-"$ROOT/dist/PairDesk-test.dmg"}
[[ -x "$APP/Contents/MacOS/PairDesk" ]] || { echo 'Build the app first' >&2; exit 1; }
[[ ! -e "$OUTPUT" ]] || { echo 'Installer already exists; preserve it before replacing' >&2; exit 1; }
codesign --verify --deep --strict "$APP"
STAGING=$(mktemp -d "$ROOT/.cache/dmg.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/PairDesk.app"
ln -s /Applications "$STAGING/Applications"
cat > "$STAGING/Read me first.txt" <<'TEXT'
PairDesk — internal macOS pairing app

1. Drag PairDesk.app onto Applications.
2. Eject this disk image and open PairDesk from Applications.
3. Sign in using the account created by your team administrator.
4. PairDesk registers automatic startup at first launch from Applications.
   You can turn Start at login off using its menu-bar menu or Account settings.
   macOS may require approval in System Settings > General > Login Items.
5. For calls, allow microphone access when requested. To share, choose a
   display in the macOS screen-sharing picker; no Screen Recording setting is
   needed. Camera video is optional; allow camera access when you turn it on.
   To let teammates control your Mac, enable PairDesk in Accessibility.
6. PairDesk lives in the top-right menu bar. Click its icon to call an online
   teammate; they accept. Click another available teammate to add them.
   Share screen opens Apple's system picker. A shared display allows call
   participants to control it when Accessibility access is enabled.
   Stop control in the menu bar or press Control+Option+Escape.
   Permissions setup in the gear menu opens the relevant macOS Settings pages.
   A remote screen opens a large viewer with a Full screen button.
   Hanging up ends a two-person call for both people.

This file may be a development/test build. Only a Developer ID signed,
notarized release is ready for normal team distribution. If macOS blocks
opening it, ask your administrator for the signed release. Do not disable
Gatekeeper or remove quarantine as a substitute for signing.

Voice, optional camera video, and screen sharing. Transcription is optional
and local. Startup does not activate the microphone, camera, sharing, remote
control or transcription.
TEXT
hdiutil create -volname PairDesk -srcfolder "$STAGING" -format UDZO "$OUTPUT"
hdiutil verify "$OUTPUT"
shasum -a 256 "$OUTPUT" > "$OUTPUT.sha256"
echo "Installer created: $OUTPUT"
