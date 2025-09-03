# Car Inclinometer

A Flutter application that measures and displays the inclination of a device using its built-in accelerometer sensors. This app is designed as a car inclinometer to show pitch (front/back tilt) and roll (side-to-side tilt) angles.

## Features

- Real-time pitch and roll angle measurement
- Simple and intuitive UI
- Uses device accelerometer for accurate readings

## Getting Started

### Prerequisites

- Flutter SDK installed
- A device with accelerometer sensors (most modern smartphones)

### Installation

1. Clone or download the project
2. Navigate to the project directory
3. Run `flutter pub get` to install dependencies
4. Run `flutter run` to launch the app on a connected device or emulator

### Permissions

The app requires access to motion sensors:
- **Android**: BODY_SENSORS permission is requested
- **iOS**: Motion usage description is provided

## Usage

1. Launch the app
2. Place your device in the desired orientation
3. The app will display real-time pitch and roll angles in degrees

## Development

This app uses the `sensors_plus` package to access accelerometer data and calculates angles using trigonometric functions.

For help with Flutter development, see the [online documentation](https://docs.flutter.dev/).
