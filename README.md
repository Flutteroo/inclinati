# Car Inclinometer

A Flutter application that measures and displays the inclination of a device using its built-in accelerometer sensors. This app is designed as a car inclinometer to show pitch (front/back tilt) and roll (side-to-side tilt) angles.

## Features

- Real-time pitch and roll angle measurement
- Simple and intuitive UI
- Uses device accelerometer for accurate readings

## Getting Started

### Prerequisites

- Flutter SDK installed
- A device with accelerometer sensors (most modern smartphones)

# Inclinati — Car Inclinometer (Flutter)

Inclinati is a mobile Flutter application built to measure and display a vehicle's inclination using the device's motion sensors. It focuses on real-world usability in automotive contexts with features for calibration, smoothing, and persistent readings.

---

## What the App Does (Now)

- Measures and displays pitch (front/back tilt) and roll (side-to-side tilt) in degrees, in real time.
- Calculates and displays heading (compass) with smoothing and optional baseline calibration relative to the vehicle's forward direction.
- Provides a hold-to-confirm calibration flow to establish a stable "forward" heading and an inclinometer zero baseline.
- Applies smoothing filters: FIFO/circular mean for heading and an exponential moving average (EMA) for pitch/roll to reduce jitter.
- Persists calibration and odometer values using local storage so settings survive app restarts.
- The UI includes a modern dashboard and an optional retro/minimal view, plus a themed, floating top SnackBar for unobtrusive feedback.

## What the App Is Doing (Current Improvements)

- Centralizing feedback: floating SnackBar helper extracted to a single utility for consistent messaging.
- Dialog/button styling: calibration dialogs now match the hold-banner look and include a lit rounded border for clarity.
- UX polish: hold-to-confirm button provides instantaneous visual feedback and an optional customizable message in the confirmation banner.

## Planned / Will Do

- Add optional inclinometer data logging and CSV export for post-drive analysis.
- Support for multiple vehicle profiles and per-vehicle calibration presets.
- Improve accessibility (larger targets, VoiceOver/TalkBack guidance) and RTL support.
- Add automated screenshot assets generation and an in-app help tour for first-run users.

---

## Screenshots

Drop screenshots into the project at `assets/screenshots/` and update `pubspec.yaml` if you add files. Recommended image sizes: 1280×720 (landscape) and 1080×1920 (portrait). Use these filenames to let the README show them automatically:

- `assets/screenshots/overview.png` — Main dashboard overview
- `assets/screenshots/calibration_banner.png` — Hold-to-confirm calibration banner
- `assets/screenshots/compass_dialog.png` — Compass calibration dialog
- `assets/screenshots/night_mode.png` — Night mode / themed view

Example markdown to include images (already referenced above):

```
![Overview](assets/screenshots/overview.png)
![Calibration Banner](assets/screenshots/calibration_banner.png)
![Compass Dialog](assets/screenshots/compass_dialog.png)
```

If you want, I can insert actual screenshots into `assets/screenshots/` for you — just upload them or point me to image files.

---

## Quick Start — Installation & Run

Prerequisites:

- Flutter SDK (stable) installed and accessible on your `PATH`.
- A physical device is recommended for accurate sensor readings (accelerometer, magnetometer).

Install and run:

```bash
cd `./`
flutter pub get
flutter run
```

Notes:

- For iOS, ensure you opened the iOS project in Xcode at least once to resolve signing if required.
- On Android 12+ you may need to grant BODY_SENSORS or ACTIVITY_RECOGNITION depending on platform behavior.

---

## Permissions

- Android: may request `BODY_SENSORS` and `ACCESS_FINE_LOCATION` (if heading uses fused location/compass). See `android/app/src/main/AndroidManifest.xml`.
- iOS: motion usage description is provided in `Info.plist` (see `ios/Runner/Info.plist`).

---

## Architecture & Implementation Notes

- Language & Framework: Dart + Flutter.
- Sensor access: `sensors_plus` for accelerometer/gyroscope; optional `geolocator` for speed/heading.
- State management: `Provider` exposing `InclinometerData` and `SensorService`.
- Heading smoothing: FIFO/circular mean to reduce short-term jumps while preserving larger turns.
- Pitch/Roll smoothing: Exponential Moving Average (EMA) to reduce vibration-induced jitter.
- Calibration: Hold-to-confirm establishes a baseline heading (vehicle forward) and zero-incline reference. Calibration persists via `shared_preferences`.
- Feedback: Floating, themed SnackBar helper centralizes user messages; calibration uses a right-side hold banner for confirmation.

Key project files:

- `lib/main.dart` — App entry point.
- `lib/digital_inclinometer_screen.dart` — Main UI and calibration flows.
- `lib/sensor_service.dart` — Sensor processing, smoothing, and calibration logic.
- `lib/inclinometer_data.dart` — Provider model and persisted settings.

---

## Development Tips

- To capture reproducible behavior use a physical device and enable developer options to show sensor updates if useful.
- Use `flutter run --release` for the most representative sensor performance.
- When adding screenshots, run `flutter pub get` and ensure the `assets:` section in `pubspec.yaml` includes `assets/screenshots/`.

---

## Troubleshooting

- If angles appear noisy: enable "smoothing" in settings (EMA) or increase heading FIFO window size.
- If compass is unstable: perform a full compass recalibration via the app's "Calibrate North" flow and move away from magnetic interference.
- If you don't see motion data on an emulator: use a physical device. Emulators typically don't expose real sensor data.

---

## Contributing

Contributions are welcome. Please open issues for feature requests or bug reports. For code contributions, please send pull requests against the `main` branch and include a short description of the change.

---

## Changelog

See `CHANGELOG.md` for recent release notes and detailed user-facing changes.

---

## License

Include your preferred license here. If none chosen yet, add a `LICENSE` file to the repo and update this section.
