import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;

class ApiConfig {
  ApiConfig._();

  /// Set to true when testing on a physical device over USB with
  /// `adb reverse tcp:8000 tcp:8000` active. The phone then reaches the PC's
  /// backend through the cable regardless of WiFi network/subnet.
  ///
  /// Fallback: if you prefer LAN WiFi routing, set this to false and replace
  /// the Android branch below with your PC's current LAN IP.
  static const bool usePhysicalDevice = true;

  /// Returns the correct backend base URL for the current platform.
  static String get baseUrl {
    // adb reverse tunnel — phone's localhost:8000 → PC's localhost:8000
    if (usePhysicalDevice) return 'http://localhost:8000';
    if (kIsWeb) return 'http://localhost:8000';

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'http://10.0.2.2:8000';
      case TargetPlatform.iOS:
        return 'http://localhost:8000';
      default:
        return 'http://localhost:8000';
    }
  }
}
