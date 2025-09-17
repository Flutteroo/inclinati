import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'constants.dart';
import 'inclinometer_data.dart';
import 'sensor_service.dart';

class DigitalInclinometerScreen extends StatefulWidget {
  final InclinometerData data;
  final SensorService sensorService;

  const DigitalInclinometerScreen({
    super.key,
    required this.data,
    required this.sensorService,
  });

  @override
  State<DigitalInclinometerScreen> createState() =>
      _DigitalInclinometerScreenState();
}

class _DigitalInclinometerScreenState extends State<DigitalInclinometerScreen> {
  bool _showHoldBanner = false;
  double _holdProgress = 0.0;
  String _holdMessage = 'Hold to confirm';

  @override
  Widget build(BuildContext context) {
    final List<Widget> gridItems = [
      _buildMetric(
        'Pitch',
        '${_formatAngleZeroFix(widget.data.pitch)}°',
        null,
        Alignment.centerLeft,
        'raw:${widget.data.rawPitch.toStringAsFixed(1)}°',
      ),
      _buildSpeedMetric(context),
      _buildMetric(
        'Heading',
        '${widget.data.heading.toStringAsFixed(0)}° ${_getCardinalDirection(widget.data.heading)}',
        null,
        Alignment.centerRight,
        'mag:${widget.data.magX.toStringAsFixed(1)},${widget.data.magY.toStringAsFixed(1)}',
      ),
      _buildMetric(
        'Roll',
        '${_formatAngleZeroFix(widget.data.roll)}°',
        null,
        Alignment.centerLeft,
        'raw:${widget.data.rawRoll.toStringAsFixed(1)}°',
      ),
      _buildOdometer(context),
      _buildMetric(
        'Altitude',
        widget.data.isMetric
            ? '${widget.data.altitude.toStringAsFixed(1)}m'
            : '${(widget.data.altitude * 3.28084).toStringAsFixed(0)}ft',
        null,
        Alignment.centerRight,
      ),
      _buildMetric(
        'Acceleration',
        '${widget.data.gForce.toStringAsFixed(1)}G',
        null,
        Alignment.centerLeft,
        'mag:${(widget.data.gForce * 9.81).toStringAsFixed(2)}m/s²',
      ),
      const SizedBox.shrink(),
      _buildGps(Alignment.centerRight),
    ];

    return SafeArea(
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(32.0),
            child: GridView.count(
              crossAxisCount: 3,
              childAspectRatio: 2.2,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              children: gridItems,
            ),
          ),

          if (_showHoldBanner)
            Center(
              child: AnimatedOpacity(
                opacity: _showHoldBanner ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 150),
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.8,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: themeColor.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: alertColor.withValues(alpha: 0.75),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _holdMessage,
                        style: const TextStyle(color: Colors.white),
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: _holdProgress,
                        color: Colors.white,
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          Positioned(
            left: 0,
            right: 0,
            bottom: 16,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: themeColor.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: alertColor.withValues(alpha: 0.75)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HoldToConfirmButton(
                      onConfirmed: () {
                        widget.sensorService.calibrate();
                        _showFloatingSnackBar(
                          context,
                          'The Calibration of the Inclinometer is Completed',
                        );
                      },
                      duration: const Duration(seconds: 2),
                      style: _buttonStyle(),
                      message:
                          'Keep holding to calibrate the inclinometer (PITCH/ROLL 0°)',
                      onStart: (msg) {
                        setState(() {
                          _holdMessage = msg ?? 'Hold to confirm';
                          _showHoldBanner = true;
                        });
                      },
                      onCancel: () {
                        setState(() {
                          _showHoldBanner = false;
                          _holdProgress = 0.0;
                        });
                      },
                      onProgress: (p) {
                        setState(() {
                          _holdProgress = p;
                        });
                      },
                      child: const Text(
                        'CAL INCL',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: () => _showCompassCalibrationDialog(context),
                      style: _buttonStyle(),
                      child: const Text('CAL COMP'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        Provider.of<InclinometerData>(
                          context,
                          listen: false,
                        ).toggleDebugMode();
                      },
                      style: _buttonStyle().copyWith(
                        padding: WidgetStateProperty.resolveWith(
                          (_) => const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        textStyle: WidgetStateProperty.resolveWith(
                          (_) => buttonTextStyle.copyWith(fontSize: 12),
                        ),
                      ),
                      child: const Text('LOG'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatAngleZeroFix(double angle) {
    // Round to nearest integer but avoid '-0'
    final rounded = angle.round();
    if (rounded == 0) return '0';
    return rounded.toString();
  }

  Widget _buildMetric(
    String label,
    String value, [
    String? unit,
    Alignment alignment = Alignment.center,
    String? debugText,
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
          // If debugText is provided and debugMode is active, append it to the title
          Text(
            widget.data.debugMode && debugText != null
                ? '$label — $debugText'.toUpperCase()
                : label.toUpperCase(),
            style: smallTextStyle.copyWith(color: Colors.grey[400]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (ctx, constraints) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: constraints.maxWidth * 0.9,
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            value,
                            style: mainMetricStyle.copyWith(fontSize: 42),
                          ),
                        ),
                      ),
                      if (unit != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          unit,
                          style: secondaryMetricStyle.copyWith(fontSize: 20),
                        ),
                      ],
                    ],
                  ),
                  // debug info appended to title above; no separate debug line here
                ],
              );
            },
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
        widget.data.isMetric
            ? widget.data.speed.toStringAsFixed(1)
            : (widget.data.speed * 0.621371).toStringAsFixed(1),
        widget.data.isMetric ? 'km/h' : 'mph',
        Alignment.center,
      ),
    );
  }

  Widget _buildOdometer(BuildContext context) {
    return GestureDetector(
      onLongPress: () => widget.sensorService.resetOdometer(),
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
              widget.data.isMetric
                  ? '${widget.data.odometerKm.toStringAsFixed(2)} km'
                  : '${(widget.data.odometerKm * 0.621371).toStringAsFixed(2)} mi',
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
          widget.data.latitude == 0.0 && widget.data.longitude == 0.0
              ? Text(
                  'Acquiring...',
                  style: secondaryMetricStyle.copyWith(fontSize: 18),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      widget.data.latitude.toStringAsFixed(6),
                      style: mainMetricStyle.copyWith(fontSize: 22),
                    ),
                    Text(
                      widget.data.longitude.toStringAsFixed(6),
                      style: mainMetricStyle.copyWith(fontSize: 22),
                    ),
                  ],
                ),
        ],
      ),
    );
  }

  static ButtonStyle _buttonStyle() {
    return ElevatedButton.styleFrom(
      backgroundColor: alertColor.withValues(alpha: 0.35),
      foregroundColor: Colors.white,
      side: BorderSide(color: Colors.white, width: 1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      textStyle: buttonTextStyle.copyWith(fontSize: 16),
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

  void _showFloatingSnackBar(
    BuildContext ctx,
    String text, {
    TextStyle? style,
  }) {
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: alertColor.withValues(alpha: 0.75),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
        content: Text(
          text,
          style:
              style ??
              mainMetricStyle.copyWith(
                color: const Color.fromARGB(255, 217, 144, 27),
              ),
        ),
      ),
    );
  }

  void _showCompassCalibrationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: themeColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10.0),
            side: BorderSide(color: alertColor.withValues(alpha: 0.75)),
          ),
          title: Text('Compass Calibration', style: mainMetricStyle),
          content: Text(
            'Point device towards magnetic North and press NORTH CALIBRATE, or press GPS CALIBRATE and rotate the device for 10 seconds.',
            style: secondaryMetricStyle,
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            OutlinedButton(
              style: _buttonStyle(),
              child: const Text('GPS CALIBRATE'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                widget.sensorService.startQuickCalibration();
                Future.delayed(const Duration(seconds: 10), () {
                  widget.sensorService.finishQuickCalibration();
                  if (context.mounted) {
                    _showFloatingSnackBar(
                      context,
                      'The GPS Calibration of the Compass is Completed',
                    );
                  }
                });
              },
            ),
            ElevatedButton(
              style: _buttonStyle(),
              child: const Text('NORTH CALIBRATE'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                widget.sensorService.performNorthCalibration();
                if (context.mounted) {
                  _showFloatingSnackBar(
                    context,
                    'The NORTH Calibration of the Compass is Completed',
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

/// A button that requires the user to press-and-hold for [duration] to confirm.
/// Shows a progress fill while held and reports progress via callbacks.
class HoldToConfirmButton extends StatefulWidget {
  final Widget child;
  final ButtonStyle style;
  final Duration duration;
  final VoidCallback onConfirmed;
  final ValueChanged<String?>? onStart;
  final String? message;
  final VoidCallback? onCancel;
  final ValueChanged<double>? onProgress;

  const HoldToConfirmButton({
    super.key,
    required this.child,
    required this.onConfirmed,
    required this.style,
    this.duration = const Duration(seconds: 2),
    this.onStart,
    this.message,
    this.onCancel,
    this.onProgress,
  });

  @override
  State<HoldToConfirmButton> createState() => _HoldToConfirmButtonState();
}

class _HoldToConfirmButtonState extends State<HoldToConfirmButton> {
  Timer? _timer;
  double _progress = 0.0; // 0..1
  bool _active = false;

  void _start() {
    _timer?.cancel();
    const int tickMs = 50;
    int elapsed = 0;
    setState(() {
      _active = true;
    });
    widget.onStart?.call(widget.message);
    _timer = Timer.periodic(const Duration(milliseconds: tickMs), (t) {
      elapsed += tickMs;
      setState(() {
        _progress = (elapsed / widget.duration.inMilliseconds).clamp(0.0, 1.0);
      });
      widget.onProgress?.call(_progress);
      if (_progress >= 1.0) {
        widget.onConfirmed();
        _cancel();
      }
    });
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
    setState(() {
      _progress = 0.0;
      _active = false;
    });
    widget.onCancel?.call();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() {
        _active = true;
      }),
      onTapUp: (_) => setState(() {
        _active = false;
      }),
      onLongPressStart: (_) => _start(),
      onLongPressEnd: (_) => _cancel(),
      onLongPressCancel: _cancel,
      child: Stack(
        alignment: Alignment.center,
        children: [
          ElevatedButton(
            onPressed: () {},
            style: widget.style,
            child: widget.child,
          ),
          if (_active)
            Positioned.fill(
              top: 8,
              bottom: 8,
              left: 4,
              right: 4,
              child: Opacity(
                opacity: 0.25,
                child: Container(
                  decoration: BoxDecoration(
                    color: alertColor,
                    borderRadius: BorderRadius.circular(5.0),
                  ),
                ),
              ),
            ),
          if (_active)
            Positioned(
              bottom: 6,
              left: 6,
              right: 6,
              child: LinearProgressIndicator(
                value: _progress,
                color: Colors.white,
                backgroundColor: Colors.white.withValues(alpha: 0.15),
                minHeight: 4,
              ),
            ),
        ],
      ),
    );
  }
}
