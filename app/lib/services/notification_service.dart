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

  // Stable IDs for each reminder type
  static const int journalReminderId = 1001;
  static const int morningAdhkarId = 1002;
  static const int eveningAdhkarId = 1003;
  static const int habitCheckinId = 1004;
  // Reserved range start for the "Send test notification now" button
  // so it never collides with a real reminder ID.
  static const int testNotificationId = 999;

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

  Future<bool> scheduleJournalReminder() async {
    return scheduleDailyNotification(
      id: journalReminderId,
      title: 'Journal Reflection',
      body: _rotatingMessage(_journalMessages),
      hour: 20,
      minute: 0,
    );
  }

  Future<bool> scheduleMorningAdhkar() async {
    return scheduleDailyNotification(
      id: morningAdhkarId,
      title: 'Morning Adhkar',
      body: _rotatingMessage(_morningAdhkarMessages),
      hour: 6,
      minute: 0,
    );
  }

  Future<bool> scheduleEveningAdhkar() async {
    return scheduleDailyNotification(
      id: eveningAdhkarId,
      title: 'Evening Adhkar',
      body: _rotatingMessage(_eveningAdhkarMessages),
      hour: 17,
      minute: 0,
    );
  }

  Future<bool> scheduleHabitCheckin() async {
    return scheduleDailyNotification(
      id: habitCheckinId,
      title: 'Habit Check-in',
      body: _rotatingMessage(_habitMessages),
      hour: 21,
      minute: 0,
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
