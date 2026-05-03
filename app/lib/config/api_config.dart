import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;

class ApiConfig {
  ApiConfig._();

  // ───────────────────────────────────────────────────────────────────
  //  ⚡ THE ONE FLAG YOU FLIP
  // ───────────────────────────────────────────────────────────────────
  // true  -> point the app at the deployed Hugging Face backend.
  //          No need to run uvicorn locally; works on any phone with
  //          internet, no adb tunnel needed.
  // false -> talk to the local backend on your laptop (uvicorn + adb
  //          reverse tcp:8000 tcp:8000). Faster iteration when you're
  //          editing backend code.
  static const bool useDeployedBackend = true;

  /// The deployed backend URL on Hugging Face Spaces. Sakinah's Space
  /// is public so we can hardcode this without leaking secrets — the
  /// secrets sit in the Space's env vars, not in the URL.
  static const String _deployedUrl =
      'https://sakinah-guidance-sakinah-backend.hf.space';

  // ───────────────────────────────────────────────────────────────────
  //  Build-time override: `--dart-define=SAKINAH_API_URL=https://...`
  //  always wins, regardless of [useDeployedBackend]. Useful for CI or
  //  for pointing at a staging Space without editing code.
  // ───────────────────────────────────────────────────────────────────
  static const String _envBaseUrl = String.fromEnvironment(
    'SAKINAH_API_URL',
    defaultValue: '',
  );

  /// When [useDeployedBackend] is false, set this to `true` if you're on
  /// a physical device over USB with `adb reverse tcp:8000 tcp:8000`
  /// active. The phone then reaches the laptop's backend through the
  /// cable regardless of Wi-Fi.
  static const bool usePhysicalDevice = true;

  /// Returns the correct backend base URL for the current platform.
  ///
  /// Resolution order:
  ///   1. `--dart-define=SAKINAH_API_URL=...` (CI / staging override)
  ///   2. [useDeployedBackend] flag → HF Space URL
  ///   3. Local: adb-reverse localhost / emulator fallback
  static String get baseUrl {
    if (_envBaseUrl.isNotEmpty) return _envBaseUrl;
    if (useDeployedBackend) return _deployedUrl;

    // ---- Local-dev paths ----
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
