import 'dart:async';
import 'dart:math';

import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'inclinometer_data.dart';

class SensorService {
  final InclinometerData _data;

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
        _data.rawPitch = atan2(event.y, event.z) * 180 / pi;
        _data.rawRoll =
            atan2(-event.x, sqrt(event.y * event.y + event.z * event.z)) *
            180 /
            pi;
        _data.pitch = _data.rawPitch - _data.offsetPitch;
        _data.roll = _data.rawRoll - _data.offsetRoll;
      });
    });

    userAccelerometerEventStream().listen((UserAccelerometerEvent event) {
      _data.updateData(() {
        _data.gForce =
            sqrt(event.x * event.x + event.y * event.y + event.z * event.z) /
            9.81;
      });
    });

    magnetometerEventStream().listen((MagnetometerEvent event) {
      _data.updateData(() {
        _data.magX = event.x;
        _data.magY = event.y;
        _data.magZ = event.z;

        if (_data.isCalibrating) {
          _data.calibrationReadingsX.add(_data.magX);
          _data.calibrationReadingsY.add(_data.magY);
          _data.calibrationReadingsZ.add(_data.magZ);
        }

        double calX = _data.magX - _data.magOffsetX;
        double calY = _data.magY - _data.magOffsetY;
        double calZ = _data.magZ - _data.magOffsetZ;

        _data.heading = _calculateTiltCompensatedHeadingWithData(
          calX,
          calY,
          calZ,
        );
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
        _data.speed = position.speed * 3.6;

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

  double _calculateTiltCompensatedHeadingWithData(
    double calX,
    double calY,
    double calZ,
  ) {
    double pitchRad = _data.rawPitch * pi / 180.0;
    double rollRad = _data.rawRoll * pi / 180.0;

    double magXComp = calX * cos(pitchRad) + calZ * sin(pitchRad);
    double magYComp =
        calX * sin(rollRad) * sin(pitchRad) +
        calY * cos(rollRad) -
        calZ * sin(rollRad) * cos(pitchRad);

    double headingRad = atan2(magYComp, magXComp);
    double headingDeg = headingRad * 180.0 / pi;

    return (headingDeg + 360.0) % 360.0;
  }

  void calibrate() {
    _data.updateData(() {
      _data.offsetPitch = _data.rawPitch;
      _data.offsetRoll = _data.rawRoll;
    });
  }

  void startQuickCalibration() {
    _data.updateData(() {
      _data.isCalibrating = true;
      _data.calibrationReadingsX.clear();
      _data.calibrationReadingsY.clear();
      _data.calibrationReadingsZ.clear();
    });
  }

  void finishQuickCalibration() {
    if (_data.calibrationReadingsX.length < 10) {
      return;
    }

    double avgX =
        _data.calibrationReadingsX.reduce((a, b) => a + b) /
        _data.calibrationReadingsX.length;
    double avgY =
        _data.calibrationReadingsY.reduce((a, b) => a + b) /
        _data.calibrationReadingsY.length;
    double avgZ =
        _data.calibrationReadingsZ.reduce((a, b) => a + b) /
        _data.calibrationReadingsZ.length;

    _data.updateData(() {
      _data.isCalibrating = false;
      _data.magOffsetX = avgX;
      _data.magOffsetY = avgY;
      _data.magOffsetZ = avgZ;
    });
  }

  void performNorthCalibration() {
    _data.updateData(() {
      _data.magOffsetX = _data.magX;
      _data.magOffsetY = _data.magY;
      _data.magOffsetZ = _data.magZ;
    });
  }

  void resetOdometer() {
    _data.resetOdometer();
    _saveOdometerData();
  }
}
