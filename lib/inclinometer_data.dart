import 'package:flutter/foundation.dart';

class ActivityLogEntry {
  final DateTime timestamp;
  final String message;

  const ActivityLogEntry(this.timestamp, this.message);
}

/// A data model class that holds all the state for the inclinometer.
/// This will allow us to separate the data logic from the UI.
class InclinometerData extends ChangeNotifier {
  static const int _maxLogEntries = 200;
  double pitch = 0.0;
  double roll = 0.0;
  double rawPitch = 0.0;
  double rawRoll = 0.0;
  double offsetPitch = 0.0;
  double offsetRoll = 0.0;
  // Device mount orientation: if true, the device is mounted in landscape
  // (screen rotated 90°). This flag lets the sensor service adjust axis
  // mapping and calibration flows when needed. Default is `true` because
  // this app targets dashboard mounting in landscape by default.
  bool deviceIsLandscape = true;
  // When true, small debug logs will be shown near widgets in the UI.
  // This is toggled by the LOG button in the main screen and is intended
  // for short-lived diagnostics while tuning the sensor behavior.
  bool debugMode = false;
  final List<ActivityLogEntry> _activityLog = [];

  List<ActivityLogEntry> get activityLog => List.unmodifiable(_activityLog);

  void toggleDebugMode() {
    updateData(() {
      debugMode = !debugMode;
      _pushLog('Debug overlay ${debugMode ? 'enabled' : 'disabled'}');
    });
  }

  int precision = 0;
  double speed = 0.0;
  double gForce = 0.0;
  double heading = 0.0;
  double latitude = 0.0;
  double longitude = 0.0;
  double altitude = 0.0;
  double odometerKm = 0.0;
  double? lastLatitude;
  double? lastLongitude;
  DateTime? lastPositionTime;
  double magX = 0.0;
  double magY = 0.0;
  double magZ = 0.0;
  double magOffsetX = 0.0;
  double magOffsetY = 0.0;
  double magOffsetZ = 0.0;
  List<double> calibrationReadingsX = [];
  List<double> calibrationReadingsY = [];
  List<double> calibrationReadingsZ = [];
  bool isCalibrating = false;
  bool isMetric = true;
  // Heading offset recorded during a "North" calibration.
  // When set, all computed headings will subtract this baseline so
  // the displayed heading is relative to the calibrated forward direction.
  double headingOffset = 0.0;

  // EMA smoothing parameters for pitch/roll (alpha in [0..1]).
  // Higher alpha -> more responsive; lower alpha -> smoother.
  double emaPitchAlpha = 0.4; // ~ moderate smoothing
  double emaRollAlpha = 0.4;

  // Internal EMA state (private-ish but exposed for simplicity)
  double emaPitch = 0.0;
  double emaRoll = 0.0;
  // Indicates we just performed a zero/calibrate action and are waiting for
  // the EMA-filtered pitch/roll to settle near zero. UI can show a transient
  // "ZEROING..." state while this is true.
  bool isZeroing = false;

  void updateData(VoidCallback updater) {
    updater();
    notifyListeners();
  }

  void toggleUnits() {
    updateData(() {
      isMetric = !isMetric;
      _pushLog('Units set to ${isMetric ? 'metric (km/h)' : 'imperial (mph)'}');
    });
  }

  void resetOdometer() {
    updateData(() {
      odometerKm = 0.0;
      lastLatitude = null;
      lastLongitude = null;
      lastPositionTime = null;
      _pushLog('Odometer reset');
    });
  }

  void addLogEntry(String message) {
    _pushLog(message);
    notifyListeners();
  }

  void clearActivityLog() {
    updateData(() {
      _activityLog.clear();
    });
  }

  void updateWithLog(VoidCallback updater, String logMessage) {
    updateData(() {
      updater();
      _pushLog(logMessage);
    });
  }

  void _pushLog(String message) {
    _activityLog.add(ActivityLogEntry(DateTime.now(), message));
    if (_activityLog.length > _maxLogEntries) {
      _activityLog.removeAt(0);
    }
  }
}
