#!/bin/sh
# Render PairDesk's key screens with fixture data to PNG files (2x) for visual
# review. Uses a debug build; never reads the saved session or calls a server.
#
#   sh scripts/ui-snapshots.sh [output-dir]    # default: .cache/ui-snapshots
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUTPUT=${1:-"$ROOT/.cache/ui-snapshots"}
case "$OUTPUT" in /*) ;; *) OUTPUT="$PWD/$OUTPUT" ;; esac
SCRATCH="$ROOT/macos/.build"

# Without Xcode, the macOS 27 SDK's SwiftUI macros have no plugin. Build
# against the Command Line Tools' macOS 26 SDK in its own scratch directory.
if ! xcode-select -p 2>/dev/null | grep -q '\.app/'; then
  CLT_SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk
  if [ -d "$CLT_SDK" ]; then
    export SDKROOT="$CLT_SDK"
    SCRATCH="$ROOT/macos/.build-sdk26"
  fi
fi

(cd "$ROOT/macos" && swift build --scratch-path "$SCRATCH")
mkdir -p "$OUTPUT"
# A hung render must not block the caller; macOS has no timeout(1).
PAIRDESK_SNAPSHOT_DIR="$OUTPUT" perl -e 'alarm 120; exec @ARGV' "$SCRATCH/debug/PairDesk"
ls "$OUTPUT"/*.png
