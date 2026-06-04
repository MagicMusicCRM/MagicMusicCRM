# Android Release Signing

Release builds must not use the Android debug key.

## Current release status

- Final app name: `Magic Music CRM`
- Final Android application ID / package name: `magic.crm`
- Upload keystore: `android/upload-keystore.jks`
- Signing properties: `android/key.properties`
- Both local signing files are ignored by git.
- Verified release bundle: `build/app/outputs/bundle/release/app-release.aab`
- Verified command: `flutter build appbundle --release`

`flutter doctor` still reports that some local Android SDK licenses are not accepted. This is a local toolchain warning; the release AAB build itself passes after installing Android SDK cmdline-tools.

## Rebuild

1. Create an upload keystore outside version control.
2. Copy `android/key.properties.example` to `android/key.properties`.
3. Fill in:
   - `storeFile`: keystore path relative to `android/` or absolute path.
   - `storePassword`
   - `keyAlias`
   - `keyPassword`
4. Build with `flutter build appbundle --release`.

`android/key.properties`, `*.jks` and `*.keystore` are ignored by git. If `key.properties` is missing, release Gradle tasks fail instead of falling back to debug signing.
