# Android internal test build

- Artifact: `app/build/outputs/apk/debug/app-debug.apk`
- Package/version: `ai.futurepath.pairdesk` / `0.1.0` (versionCode 1)
- Size: 80 MB
- SHA-256: `853803ff1e51814936746998c0a5276f093d2a3d7243d4cbede54eab2722f4ec`
- Signature: Android debug key; `apksigner verify --print-certs` succeeded. Certificate SHA-256: `0aa97d14f8391e107d797fe0b2e600b10db609811b401785562dda301f99183d`.
- Validation: `./gradlew testDebugUnitTest assembleDebug` succeeded; 3 unit tests passed.
- Device validation: no Android device or emulator was attached during this build.

This is an installable debug APK for internal sideload testing. Android may require allowing installation from the app used to open the APK. Do not treat the debug signing certificate as a production identity.
