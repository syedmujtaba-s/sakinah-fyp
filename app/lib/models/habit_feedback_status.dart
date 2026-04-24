/// Feedback a user can give on a guidance-sourced habit after using it
/// for a few days. Stored on the habit doc as `feedbackStatus: <string>`.
///
/// Using an enum here (instead of raw strings scattered across three files)
/// avoids typos like 'succes' vs 'success' and gives us one place to rename
/// or extend the vocabulary.
enum HabitFeedbackStatus {
  /// No feedback given yet. Persisted as `null` in Firestore.
  none,

  /// The advice is working — habit stays, strip disappears.
  success,

  /// The advice isn't landing. Triggers the "need alternative" flow that
  /// re-queries guidance with the original story excluded.
  struggled;

  /// Wire value stored in Firestore. `none` is persisted as `null`.
  String? get wire {
    switch (this) {
      case HabitFeedbackStatus.none:
        return null;
      case HabitFeedbackStatus.success:
        return 'success';
      case HabitFeedbackStatus.struggled:
        return 'struggled';
    }
  }

  static HabitFeedbackStatus fromWire(Object? value) {
    switch (value) {
      case 'success':
        return HabitFeedbackStatus.success;
      case 'struggled':
        return HabitFeedbackStatus.struggled;
      default:
        return HabitFeedbackStatus.none;
    }
  }
}
