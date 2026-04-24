import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  // Stable IDs for each reminder type
  static const int journalReminderId = 1001;
  static const int morningAdhkarId = 1002;
  static const int eveningAdhkarId = 1003;
  static const int habitCheckinId = 1004;

  /// Initialize the notification plugin. Call once in main().
  Future<void> init() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Karachi'));

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(initSettings);
    _initialized = true;
  }

  /// Request notification permission (Android 13+ / iOS).
  Future<bool> requestPermission() async {
    if (kIsWeb) return false;
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  /// Schedule a daily repeating notification at the given hour:minute.
  Future<void> scheduleDailyNotification({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
  }) async {
    final now = tz.TZDateTime.now(tz.local);
    var scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }

    const androidDetails = AndroidNotificationDetails(
      'sakinah_reminders',
      'Daily Reminders',
      channelDescription: 'Seerah-themed daily spiritual reminders',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

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
  }

  /// Cancel a specific notification by ID.
  Future<void> cancelNotification(int id) async {
    await _plugin.cancel(id);
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

  Future<void> scheduleJournalReminder() async {
    await scheduleDailyNotification(
      id: journalReminderId,
      title: 'Journal Reflection',
      body: _rotatingMessage(_journalMessages),
      hour: 20,
      minute: 0,
    );
  }

  Future<void> scheduleMorningAdhkar() async {
    await scheduleDailyNotification(
      id: morningAdhkarId,
      title: 'Morning Adhkar',
      body: _rotatingMessage(_morningAdhkarMessages),
      hour: 6,
      minute: 0,
    );
  }

  Future<void> scheduleEveningAdhkar() async {
    await scheduleDailyNotification(
      id: eveningAdhkarId,
      title: 'Evening Adhkar',
      body: _rotatingMessage(_eveningAdhkarMessages),
      hour: 17,
      minute: 0,
    );
  }

  Future<void> scheduleHabitCheckin() async {
    await scheduleDailyNotification(
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
  /// the general reminders (1000-1004).
  int _habitNotifId(String habitId) {
    // Simple stable hash — deterministic across runs.
    var h = 0;
    for (final code in habitId.codeUnits) {
      h = (h * 31 + code) & 0x3FFFFFFF;
    }
    return _perHabitBase + h % 900000000;
  }

  Future<void> scheduleHabitReminder({
    required String habitId,
    required String habitTitle,
    required int hour,
    required int minute,
  }) async {
    await scheduleDailyNotification(
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
