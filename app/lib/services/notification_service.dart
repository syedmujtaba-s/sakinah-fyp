import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:permission_handler/permission_handler.dart';

/// Wraps flutter_local_notifications with a few defensive behaviours that
/// our reminder UX depends on:
///
/// - **Self-bootstrapping.** Every public method calls [_ensureInit] first.
///   main.dart still tries to init at app startup (with a timeout), but if
///   that fails or is skipped the first reminder-schedule call here will
///   still initialise correctly. No more "toggle ON but silently does
///   nothing because init never ran" failures.
/// - **Explicit channel creation.** Android 8+ needs a channel registered
///   before notifications fire; we create it here on first init rather
///   than relying on implicit creation when the first notification posts
///   (which was unreliable on Samsung One UI).
/// - **Exact alarms with graceful fallback.** We prefer
///   [AndroidScheduleMode.exactAllowWhileIdle] so reminders fire on time
///   even during Doze. If exact-alarm permission has been denied on
///   Android 12+, we fall back to inexact mode rather than throwing.
/// - **White monochrome small-icon.** The launcher icon was previously
///   used, which Android renders as a featureless white square because
///   notification icons MUST be monochrome silhouettes. We now reference
///   `@drawable/ic_stat_notify`, a white heart vector.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _initFailed = false;
  String? _lastInitError;
  Future<void>? _initFuture;

  // Sakinah brand green — used as the channel accent on lockscreens
  // and inside the notification's small-icon background tint.
  static const Color _brandColor = Color(0xFF15803D);

  // Channel constants — kept in one place so AndroidNotificationDetails
  // can't drift out of sync with createNotificationChannel().
  static const String _channelId = 'sakinah_reminders';
  static const String _channelName = 'Daily Reminders';
  static const String _channelDescription =
      'Seerah-themed daily spiritual reminders';

  // Stable IDs for each reminder type.
  //
  // Each of the four built-in reminders owns 7 consecutive IDs (one per
  // ISO weekday: 1=Mon..7=Sun). We need separate alarm IDs per day so
  // the user can disable e.g. Saturday without cancelling Sunday too.
  // Base + isoWeekday gives the actual ID. Ranges below are reserved:
  //   Journal:       1011..1017
  //   Morning Adhkar: 1021..1027
  //   Evening Adhkar: 1031..1037
  //   Habit Check-in: 1041..1047
  // These ranges sit comfortably between the legacy single IDs (1001..1004,
  // cancelled at init for v1.0.4 upgraders) and the per-habit hashed range
  // (10000+).
  static const int journalReminderBase = 1010;
  static const int morningAdhkarBase = 1020;
  static const int eveningAdhkarBase = 1030;
  static const int habitCheckinBase = 1040;

  // Legacy single-shot IDs from v1.0.4 — kept here only so init() can
  // cancel them defensively when a user upgrades, preventing duplicate
  // notifications (old daily alarm + new weekly alarms firing together).
  static const int _legacyJournalId = 1001;
  static const int _legacyMorningId = 1002;
  static const int _legacyEveningId = 1003;
  static const int _legacyHabitCheckinId = 1004;

  // Reserved range start for the "Send test notification now" button
  // so it never collides with a real reminder ID.
  static const int testNotificationId = 999;

  int _idForDay(int base, int isoWeekday) => base + isoWeekday; // 1..7

  bool get isInitialized => _initialized;
  bool get initFailed => _initFailed;
  String? get lastInitError => _lastInitError;

  /// Initialise the plugin, register the notification channel, and request
  /// scheduling permissions. Safe to call multiple times — the work runs
  /// exactly once and concurrent callers await the same Future.
  Future<void> init() => _initFuture ??= _doInit();

  Future<void> _doInit() async {
    if (_initialized) return;
    try {
      tz_data.initializeTimeZones();
      try {
        tz.setLocalLocation(tz.getLocation('Asia/Karachi'));
      } catch (e) {
        // Bad tz data is rare but recoverable — default tz is UTC.
        debugPrint('[NotificationService] tz.setLocalLocation failed: $e');
      }

      const androidSettings =
          AndroidInitializationSettings('@drawable/ic_stat_notify');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      // Tapping the notification just opens the app. We don't deep-link
      // anywhere for v1 — the user is on the home screen which has the
      // Journal / Habits entry points clearly visible. Callback below
      // exists so the plugin records taps; absence wasn't broken, but
      // having it makes future deep-linking a one-line change.
      await _plugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (_) {
          // No-op — the OS already brings the app to foreground.
        },
      );

      // Explicitly create the Android channel BEFORE the first notification
      // fires. Implicit creation on first-fire was producing low-importance
      // channels on Samsung devices, which then required the user to dig
      // into Settings → Notifications → channels to fix.
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl != null) {
        await androidImpl.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDescription,
            importance: Importance.high,
            playSound: true,
            enableVibration: true,
          ),
        );
      }

      _initialized = true;

      // Defensive cleanup for users upgrading from v1.0.4 or earlier. Their
      // device still has scheduled alarms under the legacy single IDs; if
      // we don't cancel them, those alarms continue to fire AND the new
      // per-day weekly alarms fire — user gets two notifications per
      // reminder. Cheap to run (just calls cancel for 4 IDs that may or
      // may not exist).
      try {
        await _cancelLegacyReminders();
      } catch (e) {
        debugPrint('[NotificationService] legacy cleanup failed (non-fatal): $e');
      }
    } catch (e, st) {
      _initFailed = true;
      _lastInitError = e.toString();
      debugPrint('[NotificationService] init failed: $e\n$st');
      // Don't rethrow — callers downstream check isInitialized.
    }
  }

  /// Internal: ensure init has been attempted before any schedule/cancel
  /// call. Returns false if init has failed so callers can short-circuit.
  Future<bool> _ensureInit() async {
    await init();
    return _initialized;
  }

  /// Ask the OS for POST_NOTIFICATIONS (Android 13+ / iOS). On Android 12+
  /// also kick off the separate "Alarms & reminders" prompt for exact
  /// alarms (USE_EXACT_ALARM is in the manifest but Samsung One UI still
  /// requires the user to explicitly enable it for scheduled fires).
  Future<bool> requestPermission() async {
    if (kIsWeb) return false;
    if (!await _ensureInit()) return false;

    final status = await Permission.notification.request();
    if (!status.isGranted) return false;

    // Best-effort exact-alarm grant. If denied, scheduleDailyNotification
    // falls back to inexact mode rather than failing.
    try {
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.requestExactAlarmsPermission();
    } catch (_) {
      // Older Android (<12) doesn't expose this; safe to ignore.
    }

    return true;
  }

  /// Schedule a notification that repeats daily at the given hour:minute.
  /// Returns true on success, false if init or scheduling failed.
  Future<bool> scheduleDailyNotification({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
  }) async {
    if (!await _ensureInit()) return false;

    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/ic_stat_notify',
      color: _brandColor,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    // Try exact mode first — fires on the dot even in Doze. If the user
    // has revoked SCHEDULE_EXACT_ALARM (Samsung Android 12+ default), the
    // plugin throws a PlatformException; we catch and fall back to inexact
    // so reminders still fire approximately rather than not at all.
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        scheduledDate,
        details,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      return true;
    } catch (e) {
      debugPrint(
          '[NotificationService] exact schedule failed ($e), retrying inexact');
      try {
        await _plugin.zonedSchedule(
          id,
          title,
          body,
          scheduledDate,
          details,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.time,
        );
        return true;
      } catch (e2) {
        debugPrint('[NotificationService] inexact schedule also failed: $e2');
        return false;
      }
    }
  }

  /// Fire a notification immediately — used by the "Send test notification
  /// now" button on the Reminders screen so the user can verify the whole
  /// stack works without waiting for the scheduled time.
  Future<bool> sendTestNotification() async {
    if (!await _ensureInit()) return false;
    try {
      const androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        icon: '@drawable/ic_stat_notify',
        color: _brandColor,
      );
      const details = NotificationDetails(
        android: androidDetails,
        iOS: DarwinNotificationDetails(),
      );
      await _plugin.show(
        testNotificationId,
        'Sakinah test',
        'If you see this, notifications are working — your daily reminders will fire too.',
        details,
      );
      return true;
    } catch (e) {
      debugPrint('[NotificationService] test notification failed: $e');
      return false;
    }
  }

  /// Cancel a specific notification by ID.
  Future<void> cancelNotification(int id) async {
    if (!await _ensureInit()) return;
    try {
      await _plugin.cancel(id);
    } catch (e) {
      debugPrint('[NotificationService] cancel($id) failed: $e');
    }
  }

  // ─── Seerah-themed rotating messages ───

  static const List<String> _journalMessages = [
    'The Prophet (PBUH) found solace in reflection. Take a moment to write tonight.',
    'Reflection is a light for the heart. Open your journal and express what you feel.',
    '"Whoever knows himself, knows his Lord." — Write your thoughts tonight.',
  ];

  static const List<String> _morningAdhkarMessages = [
    'Begin your day as the Prophet (PBUH) did — with remembrance of Allah.',
    'The morning adhkar are a shield for your day. Start with bismillah.',
    '"O Allah, by You we enter the morning..." — Time for your morning remembrance.',
  ];

  static const List<String> _eveningAdhkarMessages = [
    'The sun is setting. Time for your evening remembrance, as the Prophet (PBUH) taught.',
    '"O Allah, by You we enter the evening..." — Pause and remember Him.',
    'Evening adhkar bring tranquility. Take a moment for dhikr.',
  ];

  static const List<String> _habitMessages = [
    'Small consistent deeds are most beloved to Allah. Check in on your habits.',
    'The Prophet (PBUH) loved consistency. Have you completed your habits today?',
    'A moment of discipline now builds a lifetime of barakah. Check your habits.',
  ];

  String _rotatingMessage(List<String> messages) {
    final dayOfYear =
        DateTime.now().difference(DateTime(DateTime.now().year, 1, 1)).inDays;
    return messages[dayOfYear % messages.length];
  }

  /// Schedule a built-in reminder on each enabled day at the given time.
  ///
  /// Cancels all 7 day-slots first so that removed days don't keep firing,
  /// then schedules a weekly-repeat alarm for each day in [days]. Returns
  /// true only if EVERY day-slot scheduled successfully.
  Future<bool> _scheduleBuiltInReminder({
    required int base,
    required String title,
    required String body,
    required int hour,
    required int minute,
    required List<int> days,
  }) async {
    if (!await _ensureInit()) return false;
    await cancelReminderAllDays(base);
    bool allOk = true;
    for (final d in days) {
      if (d < 1 || d > 7) continue;
      allOk &= await _scheduleWeeklyDay(
        id: _idForDay(base, d),
        title: title,
        body: body,
        hour: hour,
        minute: minute,
        isoWeekday: d,
      );
    }
    return allOk;
  }

  /// Schedule one notification that repeats weekly on a single weekday at
  /// the given hour:minute. Mirrors [scheduleDailyNotification] but uses
  /// [DateTimeComponents.dayOfWeekAndTime] for weekly repeats.
  Future<bool> _scheduleWeeklyDay({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    required int isoWeekday, // 1..7 (Mon..Sun) — Dart's DateTime.weekday
  }) async {
    if (!await _ensureInit()) return false;

    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    // Roll forward day by day until we hit the target weekday AND the
    // computed time is in the future. Worst case 7 iterations.
    while (scheduled.weekday != isoWeekday || scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/ic_stat_notify',
      color: _brandColor,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    // Exact first, fall back to inexact if exact-alarm permission denied.
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        scheduled,
        details,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
      return true;
    } catch (e) {
      debugPrint(
          '[NotificationService] weekly exact failed ($e), retrying inexact');
      try {
        await _plugin.zonedSchedule(
          id,
          title,
          body,
          scheduled,
          details,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        );
        return true;
      } catch (e2) {
        debugPrint(
            '[NotificationService] weekly inexact also failed: $e2');
        return false;
      }
    }
  }

  /// Cancel every day-slot for one of the built-in reminders. Used by the
  /// Reminders screen when the user changes the time (cancel-all then
  /// reschedule-enabled) or toggles the reminder off.
  Future<void> cancelReminderAllDays(int base) async {
    if (!await _ensureInit()) return;
    for (int d = 1; d <= 7; d++) {
      try {
        await _plugin.cancel(_idForDay(base, d));
      } catch (e) {
        debugPrint(
            '[NotificationService] cancel ${_idForDay(base, d)} failed: $e');
      }
    }
  }

  /// One-time cleanup of v1.0.4-era single-shot alarm IDs. Called from
  /// init() so a user upgrading from v1.0.4 doesn't get duplicate
  /// notifications (old daily alarm + new weekly alarms firing together).
  Future<void> _cancelLegacyReminders() async {
    for (final id in const [
      _legacyJournalId,
      _legacyMorningId,
      _legacyEveningId,
      _legacyHabitCheckinId,
    ]) {
      try {
        await _plugin.cancel(id);
      } catch (_) {/* nothing to cancel = success */}
    }
  }

  Future<bool> scheduleJournalReminder({
    int hour = 20,
    int minute = 0,
    List<int> days = const [1, 2, 3, 4, 5, 6, 7],
  }) async {
    return _scheduleBuiltInReminder(
      base: journalReminderBase,
      title: 'Journal Reflection',
      body: _rotatingMessage(_journalMessages),
      hour: hour,
      minute: minute,
      days: days,
    );
  }

  Future<bool> scheduleMorningAdhkar({
    int hour = 6,
    int minute = 0,
    List<int> days = const [1, 2, 3, 4, 5, 6, 7],
  }) async {
    return _scheduleBuiltInReminder(
      base: morningAdhkarBase,
      title: 'Morning Adhkar',
      body: _rotatingMessage(_morningAdhkarMessages),
      hour: hour,
      minute: minute,
      days: days,
    );
  }

  Future<bool> scheduleEveningAdhkar({
    int hour = 17,
    int minute = 0,
    List<int> days = const [1, 2, 3, 4, 5, 6, 7],
  }) async {
    return _scheduleBuiltInReminder(
      base: eveningAdhkarBase,
      title: 'Evening Adhkar',
      body: _rotatingMessage(_eveningAdhkarMessages),
      hour: hour,
      minute: minute,
      days: days,
    );
  }

  Future<bool> scheduleHabitCheckin({
    int hour = 21,
    int minute = 0,
    List<int> days = const [1, 2, 3, 4, 5, 6, 7],
  }) async {
    return _scheduleBuiltInReminder(
      base: habitCheckinBase,
      title: 'Habit Check-in',
      body: _rotatingMessage(_habitMessages),
      hour: hour,
      minute: minute,
      days: days,
    );
  }

  // ─── Per-habit reminders ───
  //
  // Each habit maps to a stable notification ID derived from its Firestore
  // doc id. Hashing keeps us under Android's 32-bit signed int limit and
  // well clear of the general reminder IDs above.

  static const int _perHabitBase = 10000;

  /// Derive a stable notification ID from a habit doc id. Range:
  /// [_perHabitBase, _perHabitBase + 900_000_000), so it never collides with
  /// the general reminders (1000-1004) or the test slot (999).
  int _habitNotifId(String habitId) {
    var h = 0;
    for (final code in habitId.codeUnits) {
      h = (h * 31 + code) & 0x3FFFFFFF;
    }
    return _perHabitBase + h % 900000000;
  }

  Future<bool> scheduleHabitReminder({
    required String habitId,
    required String habitTitle,
    required int hour,
    required int minute,
  }) async {
    return scheduleDailyNotification(
      id: _habitNotifId(habitId),
      title: habitTitle,
      body: 'Time for $habitTitle — small, consistent steps.',
      hour: hour,
      minute: minute,
    );
  }

  Future<void> cancelHabitReminder(String habitId) async {
    await cancelNotification(_habitNotifId(habitId));
  }
}
