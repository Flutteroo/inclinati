# Publishing Checklist — App Stores

This document is a practical, repo-aware checklist to get `inclinati` ready for submission to the iOS App Store and Google Play. It assumes you already have developer accounts and a macOS machine with Xcode, Android SDK, and Flutter installed.

Summary of what I'll cover:
- Quick repo audit (what I found in this repo)
- Required assets and exact commands to generate them
- iOS: signing, archive, TestFlight, App Store submission steps
- Android: keystore, app bundle, Play Console submission steps
- Metadata, screenshots, privacy, and release checklist
- Optional: CI/CD automation with Fastlane/GitHub Actions

---

**Repo snapshot (current, adjust before publishing)**
- `pubspec.yaml` version: `1.0.7` — no build number. Recommendation: use semantic `x.y.z+build` (example: `1.0.7+7`).
- Android `applicationId`: `com.example.inclinati` — change to your reverse-DNS id.
- Android release signing: currently using `debug` signing (no release keystore configured).
- Android adaptive icon: `android/app/src/main/res/mipmap-* /ic_launcher.png` exist (replace with production assets, consider adaptive icon xml).
- iOS `Info.plist` contains `NSLocationWhenInUseUsageDescription` and `NSMotionUsageDescription` — good (you must provide privacy policy and justification in store listings).
- iOS supported orientation: only `UIInterfaceOrientationLandscapeRight` — verify this is intended; stores may require screenshots matching orientation.
- `CHANGELOG.md` is bundled as an asset and there is an in-app viewer.

---

1) Prerequisites (local)

- macOS with latest Xcode, Android SDK, Flutter stable channel installed and working.
- Logged into App Store Connect and Google Play Console.
- Install helpful CLI tools (optional): `brew install fastlane` (optional), and ensure `keytool` is available (comes with JDK).

2) Versioning — important

- Update `pubspec.yaml` to include a build number, e.g.:

```yaml
version: 1.0.7+7
```

- The `+7` is the Android `versionCode` and iOS `CFBundleVersion` (build number). Increment this for each store upload.

3) Android — signing, bundle, Play Console

- Generate a release keystore (run once; keep the keystore and passwords safe):

```bash
cd .
keytool -genkey -v -keystore android/key.jks -alias inclinati_key -keyalg RSA -keysize 2048 -validity 10000
```

- Create `android/key.properties` (do NOT commit it to git; add to `.gitignore`):

```properties
storePassword=<your-store-password>
keyPassword=<your-key-password>
keyAlias=inclinati_key
storeFile=key.jks
```

- Update `android/app/build.gradle.kts` signing config: add a `signingConfigs` block that reads `key.properties` and uses the keystore for `release` builds (replace debug signing). If you want, I can patch this file for you.

- Update `pubspec.yaml` version (see step 2). Build the release app bundle:

```bash
flutter clean
flutter pub get
flutter build appbundle --release
```

- The result will be in `build/app/outputs/bundle/release/app-release.aab` — upload this to Google Play Console -> Production (or Internal Test) -> Create Release.

- Play Console notes:
  - Enroll in Play App Signing if you haven't already (recommended).
  - Provide a privacy policy URL (mandatory when using location, motion sensors, or storing user data).
  - Upload screenshots for phone/tablet and a `feature graphic` (1024x500 px recommended).
  - Minimum screenshot sizes: 1080 x 1920 (portrait) or 1920 x 1080 (landscape); provide at least 2 per device class.

4) iOS — bundle id, signing, archive, TestFlight

- Set bundle identifier (change the Xcode project rather than Info.plist directly) to your app id (e.g., `com.yourcompany.inclinati`).

- Open `ios/Runner.xcworkspace` in Xcode:
  - Select the `Runner` target -> `Signing & Capabilities` -> set your Team and ensure automatic signing is enabled (or configure provisioning profiles manually).
  - Verify `Bundle Identifier` matches App Store Connect app entry.

- Verify `Info.plist` privacy descriptions are correct (you have `NSLocationWhenInUseUsageDescription` and `NSMotionUsageDescription` already).

- Build an archive and upload:

Option A (recommended interactive):
  - In Xcode: Product -> Archive; then from Organizer Upload to App Store Connect (or export .ipa then upload via Transporter).

Option B (CLI):
  - Build ipa locally with Flutter and upload via `xcrun altool` or `Transporter`:

```bash
flutter build ipa --release
# Then use Xcode Organizer or Transporter app to upload the generated .ipa
```

- After upload, create a TestFlight build and add testers (Internal/External), provide release notes, and invite testers.

5) Assets — icons, adaptive icons, splash

- Use `flutter_launcher_icons` for app icons and `flutter_native_splash` for launch screens. Example `pubspec.yaml` snippets and commands:

Add to `dev_dependencies`:

```yaml
dev_dependencies:
  flutter_launcher_icons: ^0.10.0
  flutter_native_splash: ^2.2.19
```

Add `flutter_launcher_icons` config to `pubspec.yaml` and run:

```bash
flutter pub get
flutter pub run flutter_launcher_icons:main
```

Then configure and run `flutter_native_splash`:

```bash
flutter pub run flutter_native_splash:create
```

- iOS App Icon sizes (automated if using `flutter_launcher_icons`). For manual uploads to App Store, provide a 1024x1024 App Store icon.

- Android adaptive icon: include foreground (512x512) and background images and an `ic_launcher.xml`.

6) Screenshots & marketing assets

- App Store (Apple) required screenshots:
  - iPhone 6.5" (1242 x 2688) — primary
  - iPhone 5.5" (1242 x 2208) — optional
  - iPad Pro (2048 x 2732) — for iPad listings
  - Provide portrait or landscape depending on your app orientation. Since `inclinati` locks to landscape, you must provide landscape screenshots sized appropriately.

- Google Play required screenshots:
  - Phone (minimum 2) — typical 1080 x 1920 (portrait) or 1920x1080 (landscape)
  - 1024 x 500 feature graphic

- Create high-quality device-mocked screenshots showing the app in a car environment. Keep the top area free of system UI.

7) Metadata & store listing checklist

- App title (limited char count per store), short description, full description.
- Keywords (App Store specific), category, contact email, support URL.
- Privacy policy URL (required because of location and sensors).
- Promotional text and release notes for each build.
- Age rating / Content rating questionnaire completion.

8) Permissions and privacy

- Ensure `Info.plist` has clear usage descriptions (already present). For Play Store, provide the reason for location and sensors in the Play Console's permission declarations.
- Privacy policy must explain what data is collected (location and motion), retention, and third parties.

9) Testing & QA

- Run release builds on physical devices (iOS and Android) and confirm permissions dialogs, orientation behavior, and that sensors behave as expected.
- Verify app works with minimal device sensors and degrades gracefully when permissions denied.

10) Release flow recommendations

- Stage 1 — Internal testing: Upload to TestFlight and Play Console internal testing track.
- Stage 2 — Closed Beta: invite external testers to validate on a wider set of devices.
- Stage 3 — Production rollout: consider staged rollout (10% -> 25% -> 100%) on Play Store to catch regressions early.

11) CI/CD (optional but recommended)

- Use Fastlane or GitHub Actions to automate builds and uploads. Example fastlane lanes:

```ruby
lane :beta_ios do
  build_app(scheme: "Runner")
  upload_to_testflight
end

lane :beta_android do
  gradle(task: "bundle", build_type: "Release")
  upload_to_play_store(track: "internal")
end
```

12) Post-publish

- Monitor crashes and analytics, gather user feedback, and prepare follow-up patch releases with incremented build numbers.

---

Repository-specific TODOs (I can do these for you if you want):
- Set a production `applicationId` in `android/app/build.gradle.kts` (replace `com.example.inclinati`).
- Create Android `key.jks` and `android/key.properties`, update `android/app/build.gradle.kts` signing config.
- Update `pubspec.yaml` version string to `1.0.7+X` and commit/tag the release.
- Replace `mipmap` `ic_launcher.png` files with production icons and add adaptive icon XMLs.
- Verify `Info.plist` orientation and consider adding both landscape orientations if desired.
- Add `privacy_policy` and `support` URLs in repository `README.md` and store listings.

If you'd like, I can:
- Patch `android/app/build.gradle.kts` to read `key.properties` and set release signing.
- Generate a `keytool` command for a keystore and create a `.gitignore` entry for `android/key.properties`.
- Generate a `flutter_launcher_icons` config and `flutter_native_splash` config as a starting point.

---

Suggested next step: confirm whether you want me to (pick one or more):
- A) Patch `build.gradle.kts` to wire up `key.properties` signing (I will not create the keystore or commit secrets).
- B) Add `flutter_launcher_icons` and `flutter_native_splash` configs and a small assets placeholder.
- C) Create Fastlane lanes for automated uploads.

Tell me which actions to take and I will carry them out and update the todo list accordingly.
