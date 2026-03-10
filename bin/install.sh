#!/usr/bin/env bash
set -euo pipefail

flutter clean
# flutter pub cache clean

cd android/ && ./gradlew clean && cd ..

rm -rf ~/Library/Developer/Xcode/DerivedData/*Runner*
rm -rf ios/Pods
rm -rf ios/Podfile.lock
rm -rf ios/.symlinks
rm -rf ios/build
rm -rf build

flutter pub get
cd ios && pod install --repo-update && cd ..

# flutter run --profile