import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'constants.dart';
import 'inclinometer_data.dart';
import 'sensor_service.dart';

class DigitalInclinometerScreen extends StatelessWidget {
  final InclinometerData data;
  final SensorService sensorService;

  const DigitalInclinometerScreen({
    super.key,
    required this.data,
    required this.sensorService,
  });

  @override
  Widget build(BuildContext context) {
    final List<Widget> gridItems = [
      // Row 1
      _buildMetric(
        'Pitch',
        '${data.pitch.toStringAsFixed(0)}°',
        null,
        Alignment.centerLeft,
      ),
      _buildSpeedMetric(context),
      _buildMetric(
        'Heading',
        '${data.heading.toStringAsFixed(0)}° ${_getCardinalDirection(data.heading)}',
        null,
        Alignment.centerRight,
      ),
      // Row 2
      _buildMetric(
        'Roll',
        '${data.roll.toStringAsFixed(0)}°',
        null,
        Alignment.centerLeft,
      ),
      _buildOdometer(context),
      _buildMetric(
        'Altitude',
        data.isMetric
            ? '${data.altitude.toStringAsFixed(1)}m'
            : '${(data.altitude * 3.28084).toStringAsFixed(0)}ft',
        null,
        Alignment.centerRight,
      ),
      // Row 3
      _buildMetric(
        'Acceleration',
        '${data.gForce.toStringAsFixed(1)}G',
        null,
        Alignment.centerLeft,
      ),
      _buildCalibrationButtons(context),
      _buildGps(Alignment.centerRight),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: GridView.count(
          crossAxisCount: 3,
          childAspectRatio: 2.2, // Adjust for better spacing
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          children: gridItems,
        ),
      ),
    );
  }

  Widget _buildMetric(
    String label,
    String value, [
    String? unit,
    Alignment alignment = Alignment.center,
  ]) {
    return Align(
      alignment: alignment,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: alignment == Alignment.centerLeft
            ? CrossAxisAlignment.start
            : (alignment == Alignment.centerRight
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.center),
        children: [
          Text(
            label.toUpperCase(),
            style: smallTextStyle.copyWith(color: Colors.grey[400]),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: mainMetricStyle.copyWith(fontSize: 42)),
              if (unit != null) ...[
                const SizedBox(width: 8),
                Text(unit, style: secondaryMetricStyle.copyWith(fontSize: 20)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedMetric(BuildContext context) {
    return GestureDetector(
      onTap: () =>
          Provider.of<InclinometerData>(context, listen: false).toggleUnits(),
      child: _buildMetric(
        'Speed',
        data.isMetric
            ? data.speed.toStringAsFixed(1)
            : (data.speed * 0.621371).toStringAsFixed(1),
        data.isMetric ? 'km/h' : 'mph',
        Alignment.center,
      ),
    );
  }

  Widget _buildOdometer(BuildContext context) {
    return GestureDetector(
      onLongPress: () => sensorService.resetOdometer(),
      onTap: () =>
          Provider.of<InclinometerData>(context, listen: false).toggleUnits(),
      child: Align(
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'ODOMETER',
              style: smallTextStyle.copyWith(color: Colors.grey[400]),
            ),
            const SizedBox(height: 8),
            Text(
              data.isMetric
                  ? '${data.odometerKm.toStringAsFixed(2)} km'
                  : '${(data.odometerKm * 0.621371).toStringAsFixed(2)} mi',
              style: mainMetricStyle.copyWith(fontSize: 36),
            ),
            const SizedBox(height: 4),
            Text(
              'long press to reset',
              style: smallTextStyle.copyWith(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGps(Alignment alignment) {
    return Align(
      alignment: alignment,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('GPS', style: smallTextStyle.copyWith(color: Colors.grey[400])),
          const SizedBox(height: 8),
          data.latitude == 0.0 && data.longitude == 0.0
              ? Text(
                  'Acquiring...',
                  style: secondaryMetricStyle.copyWith(fontSize: 18),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      data.latitude.toStringAsFixed(6),
                      style: mainMetricStyle.copyWith(fontSize: 22),
                    ),
                    Text(
                      data.longitude.toStringAsFixed(6),
                      style: mainMetricStyle.copyWith(fontSize: 22),
                    ),
                  ],
                ),
        ],
      ),
    );
  }

  Widget _buildCalibrationButtons(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ElevatedButton(
            onPressed: () => sensorService.calibrate(),
            style: _buttonStyle(),
            child: const Text('CAL INCL', style: TextStyle(fontSize: 16)),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: () => _showCompassCalibrationDialog(context),
            style: _buttonStyle(),
            child: const Text('CAL COMP', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }

  ButtonStyle _buttonStyle() {
    return ElevatedButton.styleFrom(
      backgroundColor: themeColor.withValues(alpha: 0.5),
      foregroundColor: Colors.white,
      side: const BorderSide(color: Colors.white, width: 1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      textStyle: buttonTextStyle.copyWith(fontSize: 14),
    );
  }

  String _getCardinalDirection(double degrees) {
    const directions = [
      'N',
      'N/NE',
      'NE',
      'E/NE',
      'E',
      'E/SE',
      'SE',
      'S/SE',
      'S',
      'S/SW',
      'SW',
      'W/SW',
      'W',
      'W/NW',
      'NW',
      'N/NW',
    ];
    int index = ((degrees + 11.25) / 22.5).round() % 16;
    return directions[index];
  }

  void _showCompassCalibrationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: themeColor,
          title: Text('Compass Calibration', style: mainMetricStyle),
          content: Text(
            'Point device towards magnetic North and press Calibrate, or rotate for Quick Cal.',
            style: secondaryMetricStyle,
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            OutlinedButton(
              child: const Text('Quick Cal'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                sensorService.startQuickCalibration();
                Future.delayed(const Duration(seconds: 10), () {
                  sensorService.finishQuickCalibration();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Quick Calibration Complete'),
                      ),
                    );
                  }
                });
              },
            ),
            ElevatedButton(
              child: const Text('Calibrate North'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                sensorService.performNorthCalibration();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Compass Calibrated to North'),
                    ),
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }
}
