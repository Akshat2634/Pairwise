# Releasing Pairwise for macOS

Installable releases are built by the [`macOS release` workflow](../.github/workflows/macos-release.yml) after a `v*` tag is pushed. It tests the macOS app, builds the universal Whisper runtime and app bundle, signs the app with Developer ID, notarizes and staples the app and disk image, runs Gatekeeper checks, then publishes the DMG, app ZIP, and checksums to a GitHub Release.

## Required GitHub configuration

Configure these repository secrets before pushing a release tag:

- `DEVELOPER_SIGNING_IDENTITY`: the exact `Developer ID Application: ...` identity.
- `DEVELOPER_ID_CERTIFICATE_BASE64`: base64-encoded `.p12` containing that certificate and private key.
- `DEVELOPER_ID_CERTIFICATE_PASSWORD`: password used to export the `.p12`.
- `APPLE_ID`: Apple ID authorized for notarization.
- `APPLE_TEAM_ID`: Apple Developer team identifier.
- `APPLE_APP_SPECIFIC_PASSWORD`: app-specific password used by `notarytool`.

Configure this repository variable:

- `PAIRDESK_SERVER_URL`: the HTTPS API origin embedded in the release app, with no path or credentials.

The workflow imports the signing certificate into a temporary keychain, stores notarization credentials in that keychain, and deletes the keychain and certificate after the job. Do not commit signing material or put it in workflow logs. Limit access to release secrets and protect the `v*` tag pattern with repository rules.

## Creating a release

1. Update `CFBundleShortVersionString` in `macos/Info.plist`, review the changes, and merge them to `main`.
2. Create an annotated tag whose version matches the plist, for example `v0.3.4` for app version `0.3.4`.
3. Push the tag. The workflow rejects a version mismatch or missing signing configuration before building.
4. Confirm the workflow's notarization, stapling, and Gatekeeper assessment steps pass. The GitHub Release contains the installable `PairDesk.dmg`, a `PairDesk.zip` with the app bundle, and `SHA256SUMS`.
5. Download the DMG on a clean supported Mac, install it from Applications, and verify microphone, screen picker, Accessibility, login item, and in-place update behavior.

## Local development builds

`scripts/build-app.sh` and `scripts/create-dmg.sh` remain available for local development. Those builds are ad-hoc signed and are not a substitute for this release workflow: Gatekeeper may block them, and macOS may require permission approval again after a rebuild. Never bypass Gatekeeper to distribute a development image.
