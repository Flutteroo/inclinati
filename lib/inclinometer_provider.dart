import 'package:flutter/foundation.dart';

/// A data model class that holds all the state for the inclinometer.
/// This will allow us to separate the data logic from the UI.
class InclinometerData extends ChangeNotifier {
  double pitch = 0.0;
  double roll = 0.0;
  double rawPitch = 0.0;
  double rawRoll = 0.0;
  double offsetPitch = 0.0;
  double offsetRoll = 0.0;
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

  void updateData(VoidCallback updater) {
    updater();
    notifyListeners();
  }

  void resetOdometer() {
    odometerKm = 0.0;
    lastLatitude = null;
    lastLongitude = null;
    lastPositionTime = null;
    notifyListeners();
  }
}
