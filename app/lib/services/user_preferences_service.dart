import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Lightweight reads for the user's per-account preferences stored on
/// `users/{uid}` in Firestore.
///
/// Kept separate from the screens that *write* preferences (e.g. ProfileScreen)
/// so other screens can read without pulling the whole profile flow in.
class UserPreferencesService {
  UserPreferencesService._();

  /// Whether camera-based emotion detection is enabled. Defaults to `true`
  /// (the field is missing for users who signed up before the feature
  /// shipped — we want them to see the new flow).
  ///
  /// Returns `true` on any error (offline, doc missing, parse failure)
  /// because falling back to the camera path is safer than blocking the
  /// user from check-in entirely. The check-in screen still has a manual
  /// fallback button regardless.
  static Future<bool> cameraEmotionEnabled() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return true;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (!doc.exists) return true;
      final v = doc.data()?['cameraEmotionEnabled'];
      return v is bool ? v : true;
    } catch (_) {
      return true;
    }
  }
}
