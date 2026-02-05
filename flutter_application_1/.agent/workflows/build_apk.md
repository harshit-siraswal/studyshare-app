---
description: Build the Android APK for the Flutter application
---

This workflow documents the steps to build the Android APK.

1.  **Clean the project** to remove cached build artifacts:
    // turbo
    flutter clean

2.  **Get dependencies** to ensure all packages are up to date:
    // turbo
    flutter pub get

3.  **Build the APK**:
    *   For **Release** (optimized, signed if configured):
        `flutter build apk --release`
    *   For **Debug** (with debugging support):
        `flutter build apk --debug`
    *   For **Profile** (performance analysis):
        `flutter build apk --profile`

    *Command to run (defaulting to debug for development iteration):*
    flutter build apk --debug
