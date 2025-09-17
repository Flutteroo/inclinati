import 'package:flutter/material.dart';

// Essential colors for the car inclinometer
// const Color themeColor = Color.fromARGB(
//   255,
//   11,
//   20,
//   40,
// ); // Dark blue background
const Color themeColor = Color.fromARGB(255, 0, 0, 0); // Dark blue background
const Color accentColor = Color.fromARGB(255, 115, 115, 115); // Grey accent
const Color alertColor = Color.fromARGB(255, 217, 71, 27); // Orange alert
const MaterialColor primarySwatch = Colors.green;

// Essential text styles using the nerd font
const TextStyle mainMetricStyle = TextStyle(
  fontSize: 25.0,
  fontFamily: '3270NerdFont',
  fontWeight: FontWeight.bold,
  color: alertColor,
);

const TextStyle secondaryMetricStyle = TextStyle(
  fontSize: 25.0,
  fontFamily: '3270NerdFont',
  fontWeight: FontWeight.normal,
  color: Colors.white70,
);

const TextStyle smallTextStyle = TextStyle(
  fontSize: 16.0,
  fontFamily: '3270NerdFont',
  fontWeight: FontWeight.normal,
  color: Colors.grey,
);

const TextStyle buttonTextStyle = TextStyle(
  fontSize: 16,
  fontFamily: '3270NerdFont',
  fontWeight: FontWeight.bold,
);

const String appName = 'INKLINATI';
