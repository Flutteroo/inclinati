import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'constants.dart';
import 'inclinometer_data.dart';
import 'sensor_service.dart';
import 'digital_inclinometer_screen.dart';

void main() {
  // Lock orientation to landscape
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => InclinometerData(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: appName,
        theme: ThemeData(
          brightness: Brightness.dark,
          primarySwatch: primarySwatch,
          scaffoldBackgroundColor: themeColor,
          textTheme: TextTheme(
            bodyLarge: mainMetricStyle,
            bodyMedium: secondaryMetricStyle,
            bodySmall: smallTextStyle,
          ),
        ),
        home: const InclinometerPage(),
      ),
    );
  }
}

class InclinometerPage extends StatefulWidget {
  const InclinometerPage({super.key});

  @override
  State<InclinometerPage> createState() => _InclinometerPageState();
}

class _InclinometerPageState extends State<InclinometerPage> {
  late SensorService _sensorService;

  @override
  void initState() {
    super.initState();
    final inclinometerData = Provider.of<InclinometerData>(
      context,
      listen: false,
    );
    _sensorService = SensorService(inclinometerData);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<InclinometerData>(
        builder: (context, data, child) {
          return DigitalInclinometerScreen(
            data: data,
            sensorService: _sensorService,
          );
        },
      ),
    );
  }
}
