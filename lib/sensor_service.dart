import 'dart:async';
import 'dart:math';

import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'inclinometer_data.dart';

class SensorService {
  final InclinometerData _data;
  // Gravity estimate used to separate linear acceleration from gravity.
  // We maintain a low-pass filtered gravity vector and compute pitch/roll
  // from that vector instead of raw accelerometer samples. This reduces
  // apparent tilt changes caused by lateral/centripetal accelerations
  // when the vehicle turns.
  double _gravX = 0.0;
  double _gravY = 0.0;
  double _gravZ = 0.0;
  double _userLinearAccelMag = 0.0;
  // Gravity low-pass alpha in [0..1]. Higher -> smoother/slower gravity.
  final double _gravityAlpha = 0.84;
  // Linear acceleration threshold (m/s^2) above which we consider the
  // vehicle to be undergoing significant turn/brake/accel and therefore
  // we should make pitch/roll smoothing more aggressive.
  final double _linearAccelThreshold = 1.96; // ~0.2 g
  // Non-linear tilt response tuning:
  // - tiny errors are treated as noise ("viscous" feel),
  // - persistent larger errors speed up response quickly.
  final double _tiltDeadbandDeg = 0.15;
  final double _tiltBoostRangeDeg = 4.0;
  final double _tiltResponseGamma = 1.35;
  final double _tiltParabolicRangeDeg = 50.0;
  final double _tiltAlphaScale = 2.0;
  // buffer for recent heading values (degrees) to compute a circular mean
  final List<double> _headingBuffer = [];
  final int _headingBufferSize = 10;
  static const double _vectorEpsilon = 1e-6;
  bool _hasGravitySample = false;
  bool _gravityInitialized = false;
  bool _hasTiltBaseline = false;
  bool _emaInitialized = false;
  double? _latestAbsoluteHeading;
  DateTime? _latestAbsoluteHeadingAt;
  _Vec3 _currentDown = const _Vec3(0, 0, 1);
  _Vec3 _baselineForward = const _Vec3(1, 0, 0);
  _Vec3 _baselineRight = const _Vec3(0, 1, 0);
  _Vec3 _baselineDown = const _Vec3(0, 0, 1);
  double _pitchIntent = 0.0;
  double _rollIntent = 0.0;
  double _lastPitchError = 0.0;
  double _lastRollError = 0.0;

  SensorService(this._data) {
    _initialize();
  }

  Future<void> _initialize() async {
    await _loadOdometerData();
    _initializeSensors();
    _initializeGPS();
  }

  Future<void> _loadOdometerData() async {
    final prefs = await SharedPreferences.getInstance();
    _data.updateData(() {
      _data.odometerKm = prefs.getDouble('odometer_km') ?? 0.0;
    });
  }

  Future<void> _saveOdometerData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('odometer_km', _data.odometerKm);
  }

  void _initializeSensors() {
    accelerometerEventStream().listen((AccelerometerEvent event) {
      _data.updateData(() {
        // Update a low-pass filtered gravity estimate. Bootstrap from the
        // first sample to avoid slow startup/transient settling.
        if (!_gravityInitialized) {
          _gravX = event.x;
          _gravY = event.y;
          _gravZ = event.z;
          _gravityInitialized = true;
        } else {
          _gravX = _gravityAlpha * _gravX + (1 - _gravityAlpha) * event.x;
          _gravY = _gravityAlpha * _gravY + (1 - _gravityAlpha) * event.y;
          _gravZ = _gravityAlpha * _gravZ + (1 - _gravityAlpha) * event.z;
        }

        // Use userAccelerometer magnitude (gravity-removed by platform) as
        // the primary linear-acceleration signal for damping. This avoids
        // treating orientation changes themselves as "bumps".
        double linMag = _userLinearAccelMag;
        if (linMag <= 0.0) {
          // Fallback before user-accelerometer stream has warmed up.
          final linX = event.x - _gravX;
          final linY = event.y - _gravY;
          final linZ = event.z - _gravZ;
          linMag = sqrt(linX * linX + linY * linY + linZ * linZ);
        }

        final normalizedDown = _normalizeOrNull(_Vec3(_gravX, _gravY, _gravZ));
        if (normalizedDown != null) {
          _hasGravitySample = true;
          _currentDown = normalizedDown;
          if (!_hasTiltBaseline) {
            _setTiltBaselineFromDown(_currentDown);
          }
          _computeRawTiltFromDown(_currentDown);
        }

        // The raw tilt angles are already baseline-relative; no per-axis
        // offset subtraction is required and avoids cross-axis coupling.
        double pitchUnfiltered = _data.rawPitch;
        double rollUnfiltered = _data.rawRoll;

        // Initialize EMA state on first reading to avoid startup bias
        if (!_emaInitialized) {
          _data.emaPitch = pitchUnfiltered;
          _data.emaRoll = rollUnfiltered;
          _pitchIntent = 0.0;
          _rollIntent = 0.0;
          _lastPitchError = 0.0;
          _lastRollError = 0.0;
          _emaInitialized = true;
        }

        // Non-linear adaptive smoothing:
        // - bumps/noise => high friction (small alpha)
        // - sustained slope changes => lower friction (larger alpha)
        final pitchError = pitchUnfiltered - _data.emaPitch;
        final rollError = rollUnfiltered - _data.emaRoll;
        _pitchIntent = _updateTiltIntent(
          currentIntent: _pitchIntent,
          error: pitchError,
          previousError: _lastPitchError,
          linearAccelMagnitude: linMag,
        );
        _rollIntent = _updateTiltIntent(
          currentIntent: _rollIntent,
          error: rollError,
          previousError: _lastRollError,
          linearAccelMagnitude: linMag,
        );

        final aPitch = _computeAdaptiveTiltAlpha(
          baseAlpha: _data.emaPitchAlpha.clamp(0.0, 1.0),
          error: pitchError,
          intent: _pitchIntent,
          linearAccelMagnitude: linMag,
        );
        final aRoll = _computeAdaptiveTiltAlpha(
          baseAlpha: _data.emaRollAlpha.clamp(0.0, 1.0),
          error: rollError,
          intent: _rollIntent,
          linearAccelMagnitude: linMag,
        );

        _data.emaPitch =
            aPitch * pitchUnfiltered + (1 - aPitch) * _data.emaPitch;
        _data.emaRoll = aRoll * rollUnfiltered + (1 - aRoll) * _data.emaRoll;
        _lastPitchError = pitchError;
        _lastRollError = rollError;

        _data.pitch = _data.emaPitch;
        _data.roll = _data.emaRoll;
      });
    });

    userAccelerometerEventStream().listen((UserAccelerometerEvent event) {
      _data.updateData(() {
        final linearMag = sqrt(
          event.x * event.x + event.y * event.y + event.z * event.z,
        );
        _userLinearAccelMag = linearMag;
        _data.gForce = linearMag / 9.81;
      });
    });

    magnetometerEventStream().listen((MagnetometerEvent event) {
      _data.updateData(() {
        // Read raw magnetometer
        _data.magX = event.x;
        _data.magY = event.y;
        _data.magZ = event.z;

        if (_data.isCalibrating) {
          _data.calibrationReadingsX.add(_data.magX);
          _data.calibrationReadingsY.add(_data.magY);
          _data.calibrationReadingsZ.add(_data.magZ);
        }

        // Apply hard-iron offsets from calibration
        double calX = _data.magX - _data.magOffsetX;
        double calY = _data.magY - _data.magOffsetY;
        double calZ = _data.magZ - _data.magOffsetZ;

        // Compute tilt-compensated heading using gravity + baseline frame.
        final computedHeading = _calculateTiltCompensatedHeadingWithData(
          calX,
          calY,
          calZ,
        );
        if (computedHeading == null) {
          return;
        }
        _latestAbsoluteHeading = computedHeading;
        _latestAbsoluteHeadingAt = DateTime.now();

        // Apply heading offset (set when user performs a North calibration)
        final adjusted = _normalizeDegrees(
          computedHeading - _data.headingOffset,
        );

        // Add to circular buffer
        if (_headingBuffer.length >= _headingBufferSize) {
          _headingBuffer.removeAt(0);
        }
        _headingBuffer.add(adjusted);

        // Compute circular mean of headings in buffer
        double sumX = 0.0;
        double sumY = 0.0;
        for (double h in _headingBuffer) {
          double rad = h * pi / 180.0;
          sumX += cos(rad);
          sumY += sin(rad);
        }
        if (_headingBuffer.isEmpty) {
          _data.heading = adjusted;
        } else {
          final avgRad = atan2(
            sumY / _headingBuffer.length,
            sumX / _headingBuffer.length,
          );
          _data.heading = _normalizeDegrees(avgRad * 180.0 / pi);
        }
      });
    });
  }

  Future<void> _initializeGPS() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return;
    }

    try {
      Position position = await Geolocator.getCurrentPosition();
      _data.updateData(() {
        _data.latitude = position.latitude;
        _data.longitude = position.longitude;
        _data.altitude = position.altitude;
        _data.speed = position.speed * 3.6;
        _data.lastLatitude = position.latitude;
        _data.lastLongitude = position.longitude;
        _data.lastPositionTime = position.timestamp;
      });
    } catch (e) {
      // Handle error
    }

    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((Position position) {
      _data.updateData(() {
        _data.latitude = position.latitude;
        _data.longitude = position.longitude;
        _data.altitude = position.altitude;
        // Primary source: device-reported speed (m/s -> km/h)
        double gpsSpeedKmh = (position.speed.isFinite)
            ? position.speed * 3.6
            : 0.0;

        // Fallback: compute speed from distance / time between last and current position
        double derivedSpeedKmh = 0.0;
        if (_data.lastLatitude != null &&
            _data.lastLongitude != null &&
            _data.lastPositionTime != null) {
          double distance = _calculateDistance(
            _data.lastLatitude!,
            _data.lastLongitude!,
            position.latitude,
            position.longitude,
          );
          double deltaSeconds =
              position.timestamp
                  .difference(_data.lastPositionTime!)
                  .inMilliseconds /
              1000.0;

          if (deltaSeconds > 0.5) {
            // distance is meters -> m/s, convert to km/h via *3.6
            derivedSpeedKmh = (distance / deltaSeconds) * 3.6;
          }
        }

        // Choose the more conservative (higher) estimate.
        double finalSpeedKmh = gpsSpeedKmh;
        if (derivedSpeedKmh.isFinite && derivedSpeedKmh > finalSpeedKmh) {
          finalSpeedKmh = derivedSpeedKmh;
        }

        // Stop-detection guard: if consecutive GPS fixes show negligible
        // displacement (here <0.5 m) over a reasonable time window (>2s), and
        // accelerometer indicates near-1g (no linear acceleration), treat as
        // stationary to avoid "stuck" non-zero speeds.
        if (_data.lastLatitude != null &&
            _data.lastLongitude != null &&
            _data.lastPositionTime != null) {
          double smallDistance = _calculateDistance(
            _data.lastLatitude!,
            _data.lastLongitude!,
            position.latitude,
            position.longitude,
          );
          double dt =
              position.timestamp
                  .difference(_data.lastPositionTime!)
                  .inMilliseconds /
              1000.0;
          if (dt > 2.0 && smallDistance < 0.5 && _data.gForce < 1.05) {
            finalSpeedKmh = 0.0;
          }
        }

        // Noise threshold: anything below 1.0 km/h is considered stopped.
        if (finalSpeedKmh < 1.0) {
          finalSpeedKmh = 0.0;
        }

        _data.speed = finalSpeedKmh;

        if (_data.lastLatitude != null &&
            _data.lastLongitude != null &&
            _data.speed > 2.0) {
          // Only update if speed is > 2 km/h
          double distance = _calculateDistance(
            _data.lastLatitude!,
            _data.lastLongitude!,
            position.latitude,
            position.longitude,
          );

          if (distance > 0.001 && distance < 100) {
            // 1m to 100m
            _data.odometerKm += distance / 1000.0;
            _saveOdometerData();
          }
        }

        _data.lastLatitude = position.latitude;
        _data.lastLongitude = position.longitude;
        _data.lastPositionTime = position.timestamp;
      });
    });
  }

  double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadius = 6371000;

    double dLat = (lat2 - lat1) * pi / 180.0;
    double dLon = (lon2 - lon1) * pi / 180.0;

    double a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180.0) *
            cos(lat2 * pi / 180.0) *
            sin(dLon / 2) *
            sin(dLon / 2);

    double c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c;
  }

  _Vec3 get _mountForwardAxis =>
      _data.deviceIsLandscape ? const _Vec3(1, 0, 0) : const _Vec3(0, 1, 0);

  _Vec3 get _mountRightAxis =>
      _data.deviceIsLandscape ? const _Vec3(0, 1, 0) : const _Vec3(1, 0, 0);

  _Vec3? _normalizeOrNull(_Vec3 vector) {
    final length = vector.length;
    if (length < _vectorEpsilon) {
      return null;
    }
    return vector / length;
  }

  _Vec3 _projectOnPlane(_Vec3 vector, _Vec3 planeNormal) {
    return vector - planeNormal * vector.dot(planeNormal);
  }

  double _normalizeDegrees(double degrees) {
    final wrapped = degrees % 360.0;
    return wrapped < 0 ? wrapped + 360.0 : wrapped;
  }

  double _updateTiltIntent({
    required double currentIntent,
    required double error,
    required double previousError,
    required double linearAccelMagnitude,
  }) {
    final absError = error.abs();
    final sameDirection = error * previousError > 0.0;
    final errorNorm = ((absError - _tiltDeadbandDeg) / _tiltBoostRangeDeg)
        .clamp(0.0, 1.0);

    // Intent rises when error is persistent in one direction (e.g. climbing
    // or descending a hill), but still reacts to large one-shot changes.
    double targetIntent = sameDirection ? errorNorm : errorNorm * 0.5;

    if (linearAccelMagnitude > _linearAccelThreshold) {
      // Extra damping during high linear acceleration to reject shocks.
      targetIntent *= 0.35;
    }

    const rise = 0.35;
    const fall = 0.3;
    final blend = targetIntent > currentIntent ? rise : fall;
    return currentIntent + (targetIntent - currentIntent) * blend;
  }

  double _computeAdaptiveTiltAlpha({
    required double baseAlpha,
    required double error,
    required double intent,
    required double linearAccelMagnitude,
  }) {
    final absError = error.abs();
    final errorNorm = ((absError - _tiltDeadbandDeg) / _tiltBoostRangeDeg)
        .clamp(0.0, 1.0);
    final nonlinear = pow(errorNorm, _tiltResponseGamma).toDouble();
    final parabolicNorm =
        ((absError - _tiltDeadbandDeg) / _tiltParabolicRangeDeg).clamp(
          0.0,
          1.0,
        );
    final parabolicCurve = (2 * parabolicNorm - parabolicNorm * parabolicNorm)
        .clamp(0.0, 1.0);

    final minAlpha = (baseAlpha * 0.35).clamp(0.03, 0.42);
    final maxAlpha = (baseAlpha + 0.5).clamp(baseAlpha, 0.92);
    final blend =
        (0.18 * errorNorm + 0.32 * nonlinear * intent + 0.5 * parabolicCurve)
            .clamp(0.0, 1.0);
    double alpha = minAlpha + (maxAlpha - minAlpha) * blend;

    if (linearAccelMagnitude > _linearAccelThreshold) {
      final over =
          ((linearAccelMagnitude - _linearAccelThreshold) /
                  _linearAccelThreshold)
              .clamp(0.0, 2.0);
      final baseDamp = (0.58 - 0.2 * over).clamp(0.22, 0.58);
      // Keep bump rejection for small errors, but avoid over-damping when
      // the user intentionally moves to a large angle.
      final dampFactor = baseDamp + (1.0 - baseDamp) * parabolicCurve;
      alpha *= dampFactor;
    }

    return (alpha * _tiltAlphaScale).clamp(0.01, 0.98);
  }

  void _setTiltBaselineFromDown(_Vec3 down, {bool force = false}) {
    if (_hasTiltBaseline && !force) {
      return;
    }

    final downNorm = _normalizeOrNull(down);
    if (downNorm == null) {
      return;
    }

    final forwardCandidate = _mountForwardAxis;
    final rightCandidate = _mountRightAxis;

    var forward = _normalizeOrNull(_projectOnPlane(forwardCandidate, downNorm));
    if (forward == null) {
      // Fallback if the preferred mount axis is too aligned with gravity.
      final fallbackCandidate = _data.deviceIsLandscape
          ? const _Vec3(0, 1, 0)
          : const _Vec3(1, 0, 0);
      forward = _normalizeOrNull(_projectOnPlane(fallbackCandidate, downNorm));
      if (forward == null) {
        return;
      }
    }

    final rightA = _normalizeOrNull(downNorm.cross(forward));
    final rightB = _normalizeOrNull(forward.cross(downNorm));
    if (rightA == null || rightB == null) {
      return;
    }

    final right = rightA.dot(rightCandidate) >= rightB.dot(rightCandidate)
        ? rightA
        : rightB;

    _baselineForward = forward;
    _baselineRight = right;
    _baselineDown = downNorm;
    _hasTiltBaseline = true;
    _latestAbsoluteHeading = null;
    _latestAbsoluteHeadingAt = null;
    _headingBuffer.clear();
  }

  void _computeRawTiltFromDown(_Vec3 downNorm) {
    if (!_hasTiltBaseline) {
      return;
    }

    final dForward = downNorm.dot(_baselineForward);
    final dRight = downNorm.dot(_baselineRight);
    final dDown = downNorm.dot(_baselineDown);
    final dDownPlane = sqrt(dForward * dForward + dDown * dDown);

    _data.rawPitch = atan2(-dForward, dDown) * 180 / pi;
    _data.rawRoll = atan2(dRight, dDownPlane) * 180 / pi;
  }

  double? _calculateTiltCompensatedHeadingWithData(
    double calX,
    double calY,
    double calZ,
  ) {
    if (!_hasTiltBaseline) {
      return null;
    }

    final mag = _Vec3(calX, calY, calZ);
    final magHorizontal = mag - _currentDown * mag.dot(_currentDown);
    final horizontalNorm = _normalizeOrNull(magHorizontal);
    if (horizontalNorm == null) {
      return null;
    }

    final forwardComponent = horizontalNorm.dot(_baselineForward);
    final rightComponent = horizontalNorm.dot(_baselineRight);
    final headingDeg = atan2(rightComponent, forwardComponent) * 180.0 / pi;
    return _normalizeDegrees(headingDeg);
  }

  void calibrate() {
    if (!_hasGravitySample) {
      _data.addLogEntry('Inclinometer zero failed: gravity data unavailable');
      return;
    }

    _setTiltBaselineFromDown(_currentDown, force: true);
    _emaInitialized = true;
    _pitchIntent = 0.0;
    _rollIntent = 0.0;
    _lastPitchError = 0.0;
    _lastRollError = 0.0;

    _data.updateWithLog(() {
      _data.offsetPitch = 0.0;
      _data.offsetRoll = 0.0;
      _data.rawPitch = 0.0;
      _data.rawRoll = 0.0;
      _data.emaPitch = 0.0;
      _data.emaRoll = 0.0;
      _data.isZeroing = false;
      _data.pitch = 0.0;
      _data.roll = 0.0;
    }, 'Inclinometer zeroed (baseline frame reset)');
  }

  void startQuickCalibration() {
    _data.updateWithLog(() {
      _data.isCalibrating = true;
      _data.calibrationReadingsX.clear();
      _data.calibrationReadingsY.clear();
      _data.calibrationReadingsZ.clear();
    }, 'Compass calibration started');
  }

  void finishQuickCalibration() {
    if (_data.calibrationReadingsX.length < 10) {
      _data.addLogEntry(
        'Compass calibration aborted: collected ${_data.calibrationReadingsX.length} samples',
      );
      return;
    }

    final minX = _data.calibrationReadingsX.reduce(min);
    final maxX = _data.calibrationReadingsX.reduce(max);
    final minY = _data.calibrationReadingsY.reduce(min);
    final maxY = _data.calibrationReadingsY.reduce(max);
    final minZ = _data.calibrationReadingsZ.reduce(min);
    final maxZ = _data.calibrationReadingsZ.reduce(max);

    final offsetX = (maxX + minX) / 2.0;
    final offsetY = (maxY + minY) / 2.0;
    final offsetZ = (maxZ + minZ) / 2.0;

    final samples = _data.calibrationReadingsX.length;
    _data.updateWithLog(() {
      _data.isCalibrating = false;
      _data.magOffsetX = offsetX;
      _data.magOffsetY = offsetY;
      _data.magOffsetZ = offsetZ;
      _latestAbsoluteHeading = null;
      _latestAbsoluteHeadingAt = null;
      _headingBuffer.clear();
    }, 'Compass calibration finished ($samples samples)');
  }

  void performNorthCalibration() {
    final absoluteHeading = _latestAbsoluteHeading;
    final headingAge = _latestAbsoluteHeadingAt == null
        ? null
        : DateTime.now().difference(_latestAbsoluteHeadingAt!);
    if (absoluteHeading == null ||
        headingAge == null ||
        headingAge > const Duration(seconds: 2)) {
      _data.addLogEntry('North calibration aborted: heading not available yet');
      return;
    }

    _data.updateWithLog(() {
      // Keep hard-iron offsets untouched. North calibration only sets
      // the display baseline (forward direction = 0°).
      _data.headingOffset = absoluteHeading;
      _data.heading = 0.0;
      _headingBuffer.clear();
    }, 'Heading baseline captured (${absoluteHeading.toStringAsFixed(0)}°)');
  }

  void resetOdometer() {
    _data.resetOdometer();
    _saveOdometerData();
  }
}

class _Vec3 {
  final double x;
  final double y;
  final double z;

  const _Vec3(this.x, this.y, this.z);

  double get length => sqrt(x * x + y * y + z * z);

  double dot(_Vec3 other) => x * other.x + y * other.y + z * other.z;

  _Vec3 cross(_Vec3 other) => _Vec3(
    y * other.z - z * other.y,
    z * other.x - x * other.z,
    x * other.y - y * other.x,
  );

  _Vec3 operator +(_Vec3 other) => _Vec3(x + other.x, y + other.y, z + other.z);

  _Vec3 operator -(_Vec3 other) => _Vec3(x - other.x, y - other.y, z - other.z);

  _Vec3 operator *(double scalar) => _Vec3(x * scalar, y * scalar, z * scalar);

  _Vec3 operator /(double scalar) => _Vec3(x / scalar, y / scalar, z / scalar);
}
