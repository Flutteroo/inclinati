
## 1.0.2, heading algorithm debounced, 2025-09-17 00:08:13, 5f7e1bc

- `lib/inclinometer_data.dart`:
	- **Added `headingOffset` (double):** stores the calibration baseline so app-level state separates mounting/alignment bias from raw sensor fusion. This lets UI-level "calibrate forward" simply adjust a single scalar without re-running magnetometer offsets.
	- **Design rationale:** keeping the heading baseline in the state object avoids re-computing offsets when persisting/restoring preferences and decouples user calibration actions from low-level sensor math.

- `lib/sensor_service.dart`:
	- **Heading buffer (FIFO) + circular mean:** implemented an N-sized ring buffer for recent heading samples and compute the smoothed heading via vector (sin/cos) averaging to avoid wraparound discontinuities at 360/0°. This is more robust than linear averaging for angular data.
	- **Tilt compensation retained:** magnetometer vectors are rotated using accelerometer-derived pitch/roll before heading extraction; this reduces heading error when the device is not perfectly level.
	- **Hard-iron offset application:** magnetometer readings have per-axis offsets applied prior to tilt compensation — keeps bias correction upstream of fusion and stable across small orientation changes.
	- **Calibration API change:** `performNorthCalibration()` now stores a `headingOffset` (smoothed current heading) instead of trying to force raw magnetometer adjustments. This makes calibration relative to vehicle forward and avoids overfitting to transient magnetic disturbances.
	- **Notes on stability:** circular-mean smoothing reduces jitter but introduces latency proportional to buffer size; chosen buffer length trades noise for responsiveness. Consider adaptive buffer sizing based on vehicle speed or a complementary filter with gyroscope data for better transient response.


## 1.0.3, geo-located tachometer refined, 2025-09-17 00:20:46, 691b46c

- `lib/sensor_service.dart`:
	- **Merged speed source:** device `position.speed` (m/s → km/h) is used as primary; a derived speed is computed from distance / delta-time between consecutive GPS fixes as a fallback when device-reported speed is unreliable.
	- **Conservative selection + thresholding:** the implementation selects the larger of GPS vs derived speed to avoid masking real movement, then zeroes any value below `1.0 km/h` to suppress GPS jitter when stationary.
	- **Delta-time guard:** derived speed is only computed when the time delta between fixes is > 0.5s to prevent division by extremely small deltas that amplify noise.
	- **Why this approach:** avoids persistent small non-zero speeds caused by GPS jitter while still catching genuine low-speed motion; keeps odometer updates conservative (still gated by >2.0 km/h as before).
	- **Testing notes:** threshold can be tuned; consider gating derived-speed with `position.accuracy` and/or adding a short low-pass filter to further reduce spikes.


## 1.0.4, tachometer algorithm refactored, 2025-09-17 00:25:06, fbb2132

- `lib/sensor_service.dart`:
	- **Stop-detection guard:** added a conservative heuristic that forces `speed = 0` when consecutive GPS fixes show negligible displacement (<0.5 m) over a multi-second window (>2 s) and accelerometer-derived `gForce` is near 1g (here <1.05). This prevents rare cases where GPS jitter produces a persistent non-zero speed while stationary.
	- **Why combine modalities:** spatial + temporal + inertial checks reduce false positives from any single sensor (GPS drift, temporary fix loss, or small device vibrations). The guard is intentionally conservative to avoid masking legitimate slow motion.
	- **Implementation notes:** retains previous thresholding (final speed <1.0 km/h zeroed) and odometer gating (>2.0 km/h) — odometer behavior remains unchanged.
	- **Tuning & next steps:** thresholds are hard-coded for now; consider exposing them in `InclinometerData` or gating by `position.accuracy`. For better transient handling, a complementary filter with device motion/gyroscope would preserve responsiveness while suppressing jitter.


## 1.0.5, improved UI/UX, press to confirm BTN, 2025-09-17 03:43:59, 0005238

- `lib/digital_inclinometer_screen.dart`:
	- **Hold-to-confirm control:** added `HoldToConfirmButton`, a reusable widget that requires a press-and-hold to confirm potentially destructive actions. It provides immediate visual feedback, a configurable hold duration, and progress callbacks so the UI can display a right-side confirmation banner.
	- **Right-side hold banner:** a small floating banner shows when a hold begins. It accepts a custom message and displays a `LinearProgressIndicator` synced to the hold progress, giving clear, non-modal confirmation feedback while the user holds the button.
	- **Instant press feedback:** buttons now "light up" immediately when touched — background/text colors and a translucent overlay provide instant tactile feedback before the hold begins.
	- **Unified button styling:** introduced and applied `_buttonStyle()` to keep dialog and grid buttons visually consistent (rounded corners, thin white border, theme-aware background alpha).
	- **Compass calibration dialog polish:** the compass modal uses a rounded `AlertDialog` with a subtle lit border matching the hold banner, and the action buttons were restyled to match the app's button theme.
	- **Floating SnackBar helper:** extracted a single `_showFloatingSnackBar` helper for consistent, themed floating snackbars positioned under the top safe-area (works nicely in landscape). SnackBars are rounded, use `alertColor`, and accept an optional text style for special messages.

- `lib/sensor_service.dart` / `lib/inclinometer_data.dart`:
	- Minor wiring and UX-oriented tweaks to support the above (callbacks, message strings, and small API adjustments to surface calibration actions to the UI).

- These changes prioritize clear, fast, and safe user interactions: immediate visual feedback reduces uncertainty, while the hold-to-confirm pattern prevents accidental calibrations. The floating snackbars and dialog styling make calibration flows feel integrated with the app's visual language.

## 1.0.6, debug feature, improved INC precision, 2025-09-17 12:24:19, 662bcbf

- `lib/digital_inclinometer_screen.dart`:
	- Debug overlay + compact debug rendering: debug values are now appended to the metric title (instead of a separate small line under the value) to avoid layout overflow while keeping debug info available at a glance.
	- Robust metric layout: metrics use `LayoutBuilder` + `ConstrainedBox` + `FittedBox` to ensure large numerics scale or truncate safely instead of overflowing (fixes the "OVERFLOWED BY X PIXELS" cases in landscape).
	- UI-level precision helpers: added `_formatAngleZeroFix(double)` to round angles but normalize both `-0` and `0` to `0` to avoid confusing negative-zero displays.
	- Themed, consistent controls: button style centralization and hold-to-confirm progress wiring were extended to integrate debug toggles and snackbars with consistent theming. Deprecated Material APIs were migrated (`MaterialStateProperty` → `WidgetStateProperty`) and opacity helpers consolidated (`withOpacity` → `withValues`) for forward-compatibility.

- `lib/inclinometer_data.dart`:
	- Debug surfacing: `InclinometerData` exposes a `debugMode` toggle and small, read-only sensor fields (raw pitch/roll, magnetometer axes, gForce, etc.) so the UI can show diagnostic values without coupling into sensor internals.
	- State-driven calibration: minor additions to make calibration state (offsets, debug flags) part of the serializable app state so UI actions can persist and restore debug/precision settings cleanly.

- `lib/sensor_service.dart`:
	- Precision & observability tweaks: small tuning of smoothing windows and the data the service publishes for diagnostics (more stable heading samples, clearer raw->corrected value separation) to improve inclinometer precision while keeping the fusion math intact.
	- Non-invasive instrumentation: sensor internals now emit read-only values into `InclinometerData` for UI consumption, enabling debug overlays without changing core fusion algorithms; this helps reproduce issues without altering runtime behavior.

- These changes are primarily about observability, UI robustness, and small precision tuning — they avoid invasive changes to the core sensor-fusion algorithms while making it much easier to diagnose and tune behavior on-device.


## 1.0.7, Changelog screen added, 2025-09-17 12:54:24, d3983d6

- `lib/changelog_screen.dart`:
	- Loads `CHANGELOG.md` as an asset and renders it with `flutter_markdown`, making the canonical changelog readable in-app without parsing at runtime.
	- Uses `SafeArea` + padded `Markdown` rendering to avoid notch/edge clipping, and a compact monospace header style for fidelity with the app's retro font.
	- Styling is intentionally theme-aware while forcing `alertColor` for headings so important section titles remain visible and consistent with the app's visual language.

- `lib/digital_inclinometer_screen.dart`:
	- LOG button long-press now navigates to the Changelog screen; short-tap still toggles `debugMode` (preserves existing UX while adding a discoverable dev path).
	- Minimal routing added via `Navigator.push` — keeps routing local and simple without introducing a global route table yet.

Notes:
- This release focuses on developer ergonomics and observability: having the changelog in-app makes field diagnostics and quick release checks easier, and the long-press discovery aligns with the existing LOG/debug affordance.

