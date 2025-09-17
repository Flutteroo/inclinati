
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


## 1.0.3, geolocated tachimeter refined, 2025-09-17 00:20:46, 691b46c
CHANGELOG.md
REVISION
lib/sensor_service.dart
pubspec.yaml.bak
