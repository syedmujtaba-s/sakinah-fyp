import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;

class ApiConfig {
  ApiConfig._();

  /// Build-time override: pass `--dart-define=SAKINAH_API_URL=https://...` to
  /// `flutter run` / `flutter build` to point the app at a deployed backend
  /// (Render, Railway, AWS, etc.) without code changes. When empty, the
  /// platform defaults below are used — keeping local dev frictionless.
  static const String _envBaseUrl = String.fromEnvironment(
    'SAKINAH_API_URL',
    defaultValue: '',
  );

  /// Set to true when testing on a physical device over USB with
  /// `adb reverse tcp:8000 tcp:8000` active. The phone then reaches the PC's
  /// backend through the cable regardless of WiFi network/subnet.
  ///
  /// Ignored when [_envBaseUrl] is set.
  static const bool usePhysicalDevice = true;

  /// Returns the correct backend base URL for the current platform.
  ///
  /// Resolution order:
  ///   1. `--dart-define=SAKINAH_API_URL=https://...` (production / cloud)
  ///   2. adb-reverse localhost when [usePhysicalDevice] is on
  ///   3. Android emulator (10.0.2.2) / iOS simulator (localhost) fallback
  static String get baseUrl {
    if (_envBaseUrl.isNotEmpty) return _envBaseUrl;

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
