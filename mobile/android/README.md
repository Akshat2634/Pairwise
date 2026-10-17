# PairDesk Android companion (early scaffold)

This native Kotlin/Compose app uses the existing PairDesk API and LiveKit room-token flow. It supports email/password sign-in, a custom API URL, encrypted local session storage, foreground roster/presence, an availability toggle, direct calls, incoming-call accept/decline, active-call join requests, voice mute, speaker routing, and opt-in camera publishing. It does not share a mobile screen or control a Mac.

## Build

Install JDK 17 and Android SDK platform 35, then run:

```sh
./gradlew testDebugUnitTest assembleDebug
```

The debug APK is written to `app/build/outputs/apk/debug/app-debug.apk` and uses the standard local debug key. It is intended for internal installation/testing, not a production release.
The exact built artifact size, checksum, signature, and test result are recorded in [BUILD.md](BUILD.md).

## Presence and notification limitations

The PairDesk API expires presence after 30 seconds and has authenticated device-registration endpoints. The app marks the account online while available and the app is running in the foreground; turning availability off stops heartbeats, so other clients may take up to 30 seconds to show it offline. Android may suspend the app in the background.

FCM device registration uses the authenticated `POST /v1/devices` contract with a stable per-install UUID, platform `android`, and the FCM token; sign-out deletes the device with `DELETE /v1/devices/{deviceId}`. The service sends only event type and call/room ID, so Android opens the app and fetches authenticated invitation state before a person can accept or decline. Register the Android package in Firebase and add `google-services.json` locally to enable token retrieval; the Gradle build detects it and applies Google's plugin automatically. Do not commit Firebase configuration or credentials. Without that file, sign-in/calls still work and push registration is skipped. Android 13+ notification permission is controlled by the OS. Server-side FCM credentials must also be configured before pushes can be delivered.

Set the API URL to an HTTPS endpoint for normal use. Cleartext is allowed only for `http://10.0.2.2` on the Android emulator. LiveKit camera publication requires server-issued camera permissions, which are enabled on the deployed PairDesk API. Camera starts off and requests permission only after the user presses Camera.
