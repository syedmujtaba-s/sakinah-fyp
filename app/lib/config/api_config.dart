import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;

class ApiConfig {
  ApiConfig._();

  /// Set to true when testing on a physical device.
  /// Then change [_physicalDeviceIp] to your PC's local WiFi IP.
  static const bool usePhysicalDevice = false;
  static const String _physicalDeviceIp = '192.168.1.100';

  /// Returns the correct backend base URL for the current platform.
  static String get baseUrl {
    if (usePhysicalDevice) return 'http://$_physicalDeviceIp:8000';
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
