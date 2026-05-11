import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/splash_screen.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Resilient startup: if Firebase or the notification plugin throws
  // (e.g. offline first-launch, missing tz data on some Android
  // versions, Google Play Services not installed), we MUST still call
  // runApp — otherwise the user is stuck on a blank Android launch
  // screen forever and thinks the install is broken. Errors here get
  // logged but the app continues to boot.
  try {
    // Hard timeout: in release mode on a flaky network, Firebase init
    // can hang silently for 30+ seconds — the user sees pure white and
    // assumes the install is broken. 8s is plenty for the SDK to either
    // succeed or report a failure; if it hasn't responded by then, give
    // up and let the splash screen show.
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 8));
  } catch (e, st) {
    debugPrint('[main] Firebase init failed or timed out: $e\n$st');
  }

  try {
    await NotificationService.instance.init()
        .timeout(const Duration(seconds: 5));
  } catch (e, st) {
    debugPrint('[main] NotificationService init failed: $e\n$st');
  }

  runApp(const SakinahApp());
}

class SakinahApp extends StatelessWidget {
  const SakinahApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sakinah',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Sans',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF15803D),
        ),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}
