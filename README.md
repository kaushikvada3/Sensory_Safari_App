# Sensory Safari Flutter

Sensory Safari offers guided sensory experiences with audio feedback, progress tracking, and Firebase-backed authentication.

## Prerequisites

- Flutter 3.24+ with Dart 3.5 SDK
- Android Studio or the Android command-line tools
- Firebase project configured with the included `google-services.json`

Run `flutter doctor` to confirm your environment is ready.

## Local Development

1. Install dependencies: `flutter pub get`
2. Run static checks: `flutter analyze`
3. Execute widget tests: `flutter test`
4. Launch the app on a device or emulator: `flutter run`

## Android Release Workflow

1. Generate an upload keystore (run from the `android/` directory):
   ```
   keytool -genkey -v -keystore app/upload-keystore.jks -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias YOUR_KEY_ALIAS
   ```
2. Copy `android/key.properties.template` to `android/key.properties` and update the passwords, alias, and keystore path to match your keystore.
3. Bump the `version` in `pubspec.yaml` (e.g., `1.1.0+2`) before each Play Store submission.
4. Build a release bundle: `flutter build appbundle`
5. The signed bundle is generated at `build/app/outputs/bundle/release/app-release.aab`. Upload this file to the Google Play Console.

> Keep the keystore and `android/key.properties` private—never commit them to source control.

## iOS Release (Quick Reference)

1. Run `flutter build ipa` once you have configured certificates and provisioning profiles.
2. Distribute the generated archive via Xcode Organizer or Transporter.

## Troubleshooting

- Clear the build cache if you see stale artifacts: `flutter clean`
- Update Firebase settings if you add new services: see `lib/firebase_options.dart`
