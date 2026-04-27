import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'face_emotion_service.dart';

/// Logs every "the AI guessed X but the user picked Y" event into
/// `users/{uid}/emotion_corrections`. Three things use this corpus over
/// time:
///
/// 1. Diagnose systemic biases in the mapping table (e.g. AffectNet's
///    Neutral → 'rejected' over-fires for users with serious resting faces).
/// 2. Per-user personalization — after ~10 corrections we can bias the
///    fusion output toward labels this specific user actually picks.
/// 3. A/B test new model versions: any future swap can be validated
///    against the historical override rate.
///
/// Logging is fire-and-forget: it never blocks the UI and never throws.
/// If Firestore is down, we just lose that one correction.
class EmotionCorrectionLogger {
  EmotionCorrectionLogger._();

  /// Call when the user manually overrides an AI suggestion.
  ///
  /// [aiSuggestion] is the result the AI returned (may be null when the
  /// user opened the manual grid without seeing a suggestion first — those
  /// rows are still useful as a baseline for "users who skip the camera").
  /// [chosenLabel] is the Sakinah-15 label the user picked (e.g. "Sad").
  static void logOverride({
    required EmotionDetectionResult? aiSuggestion,
    required String chosenLabel,
  }) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return; // Anonymous flow — nothing to attribute.

    final doc = <String, dynamic>{
      'chosen': chosenLabel.toLowerCase(),
      'timestamp': FieldValue.serverTimestamp(),
      'app_version': 'v1',  // bump when the model/mapping changes
      'had_ai_suggestion': aiSuggestion != null,
    };

    if (aiSuggestion != null) {
      doc['predicted'] = aiSuggestion.predictedEmotion;
      doc['confidence'] = aiSuggestion.confidence;
      doc['fusion_strategy'] = aiSuggestion.fusionStrategy;
      doc['sources_used'] = aiSuggestion.sourcesUsed;
      doc['low_confidence'] = aiSuggestion.lowConfidence;
      doc['face_predicted'] = aiSuggestion.facePredicted;
      doc['face_confidence'] = aiSuggestion.faceConfidence;
      doc['text_predicted'] = aiSuggestion.textPredicted;
      doc['text_confidence'] = aiSuggestion.textConfidence;
      // Full 15-way scores — the most valuable column for retraining.
      doc['scores'] = aiSuggestion.scores;
    }

    // Fire-and-forget. Never await, never bubble errors.
    FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('emotion_corrections')
        .add(doc)
        .catchError((e, s) {
      debugPrint('[EmotionCorrection] log failed: $e');
      // Swallow — losing a single training row is acceptable.
      return FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('emotion_corrections')
          .doc('discarded');
    });
  }
}
