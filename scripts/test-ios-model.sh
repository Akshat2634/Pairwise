#!/bin/sh
# Exercise the production iOS model and API on macOS without activating UIKit,
# PushKit, devices, or Keychain. Only media/notification adapters are fixtures.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
mkdir -p "$ROOT/.cache"
FIXTURE=$(mktemp -d "$ROOT/.cache/ios-model-tests.XXXXXX")
trap 'rm -rf "$FIXTURE"' EXIT HUP INT TERM
mkdir -p "$FIXTURE/Sources/PairDeskModel" "$FIXTURE/Tests/PairDeskModelTests"
for source in AppModel APIClient Models; do
  cp "$ROOT/mobile/ios/PairDesk/$source.swift" "$FIXTURE/Sources/PairDeskModel/"
done
cp "$ROOT/mobile/ios/Tests/ModelHarness/PlatformAdapters.swift" "$FIXTURE/Sources/PairDeskModel/"
cp "$ROOT/mobile/ios/Tests/ModelHarness/CallRecoveryTests.swift" "$FIXTURE/Tests/PairDeskModelTests/"
cat > "$FIXTURE/Package.swift" <<MANIFEST
// swift-tools-version: 6.1
import PackageDescription
let package = Package(name: "PairDeskModelHarness", platforms: [.macOS(.v14)],
    dependencies: [.package(path: "$ROOT/shared")],
    targets: [.target(name: "PairDeskModel", dependencies: [.product(name: "PairwiseCore", package: "shared")]),
              .testTarget(name: "PairDeskModelTests", dependencies: ["PairDeskModel"])],
    swiftLanguageModes: [.v5])
MANIFEST
swift test --package-path "$FIXTURE" -j 4 "$@"
