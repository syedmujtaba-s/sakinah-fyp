import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/daily_wisdom_service.dart';
import '../services/notification_service.dart';

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  // Reminder toggle states
  bool _journalReminder = false;
  bool _morningAdhkar = false;
  bool _eveningAdhkar = false;
  bool _habitCheckin = false;
  bool _loading = true;

  // Per-reminder user-configurable time. Seeded with the same defaults
  // the developer originally hardcoded (8 PM / 6 AM / 5 PM / 9 PM), but
  // any user customisation in users/{uid}/settings/reminders overrides
  // these in _loadSettings.
  TimeOfDay _journalTime = const TimeOfDay(hour: 20, minute: 0);
  TimeOfDay _morningTime = const TimeOfDay(hour: 6, minute: 0);
  TimeOfDay _eveningTime = const TimeOfDay(hour: 17, minute: 0);
  TimeOfDay _habitCheckinTime = const TimeOfDay(hour: 21, minute: 0);

  // Days each reminder fires on. ISO weekday convention: 1=Mon..7=Sun.
  // Default is all 7 (matches the daily behaviour from v1.0.4).
  Set<int> _journalDays = {1, 2, 3, 4, 5, 6, 7};
  Set<int> _morningDays = {1, 2, 3, 4, 5, 6, 7};
  Set<int> _eveningDays = {1, 2, 3, 4, 5, 6, 7};
  Set<int> _habitCheckinDays = {1, 2, 3, 4, 5, 6, 7};

  // Daily wisdom data
  Map<String, dynamic>? _wisdom;

  // Whether user has journaled / completed habits today
  bool _hasJournaledToday = false;
  int _habitsCompleted = 0;
  int _habitsTotal = 0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadWisdom();
    _loadTodayStatus();
  }

  Future<void> _loadSettings() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('settings')
          .doc('reminders')
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        if (!mounted) return;
        setState(() {
          _journalReminder = data['journalReminder'] ?? false;
          _morningAdhkar = data['morningAdhkar'] ?? false;
          _eveningAdhkar = data['eveningAdhkar'] ?? false;
          _habitCheckin = data['habitCheckin'] ?? false;

          // Per-reminder custom time + days. Missing fields fall back to
          // the developer defaults (the previously-hardcoded times).
          _journalTime = TimeOfDay(
            hour: (data['journalHour'] as int?) ?? 20,
            minute: (data['journalMinute'] as int?) ?? 0,
          );
          _journalDays = ((data['journalDays'] as List?)
                  ?.map((e) => (e as num).toInt())
                  .toSet()) ??
              {1, 2, 3, 4, 5, 6, 7};

          _morningTime = TimeOfDay(
            hour: (data['morningHour'] as int?) ?? 6,
            minute: (data['morningMinute'] as int?) ?? 0,
          );
          _morningDays = ((data['morningDays'] as List?)
                  ?.map((e) => (e as num).toInt())
                  .toSet()) ??
              {1, 2, 3, 4, 5, 6, 7};

          _eveningTime = TimeOfDay(
            hour: (data['eveningHour'] as int?) ?? 17,
            minute: (data['eveningMinute'] as int?) ?? 0,
          );
          _eveningDays = ((data['eveningDays'] as List?)
                  ?.map((e) => (e as num).toInt())
                  .toSet()) ??
              {1, 2, 3, 4, 5, 6, 7};

          _habitCheckinTime = TimeOfDay(
            hour: (data['habitCheckinHour'] as int?) ?? 21,
            minute: (data['habitCheckinMinute'] as int?) ?? 0,
          );
          _habitCheckinDays = ((data['habitCheckinDays'] as List?)
                  ?.map((e) => (e as num).toInt())
                  .toSet()) ??
              {1, 2, 3, 4, 5, 6, 7};

          _loading = false;
        });
        // Sync notifications to match Firestore state. Wrapped + awaited
        // (was fire-and-forget previously) so a thrown exception bubbles
        // to the user as a snackbar rather than disappearing into the
        // void. Also requires notification permission before scheduling.
        try {
          // Quietly check the existing permission state — we don't pop
          // the request dialog here because the user hasn't tapped
          // anything yet. If permission is missing we just leave the
          // toggles visible and let the per-toggle handler trigger the
          // prompt at the moment the user opts in.
          final permitted = await Permission.notification.status;
          if (permitted.isGranted) {
            await _syncNotifications();
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to sync reminders: $e')),
            );
          }
        }
      } else {
        if (mounted) setState(() => _loading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load reminder settings: $e')),
        );
      }
    }
  }

  /// Re-schedule or cancel notifications to match current toggle states.
  /// Each reminder is per-day-of-week now, so the cancel path uses
  /// cancelReminderAllDays() to clear all 7 day-slots in one go.
  /// Returns true if all schedule/cancel operations succeeded.
  Future<bool> _syncNotifications() async {
    final ns = NotificationService.instance;
    bool allOk = true;
    if (_journalReminder) {
      allOk &= await ns.scheduleJournalReminder(
        hour: _journalTime.hour,
        minute: _journalTime.minute,
        days: _journalDays.toList()..sort(),
      );
    } else {
      await ns.cancelReminderAllDays(NotificationService.journalReminderBase);
    }
    if (_morningAdhkar) {
      allOk &= await ns.scheduleMorningAdhkar(
        hour: _morningTime.hour,
        minute: _morningTime.minute,
        days: _morningDays.toList()..sort(),
      );
    } else {
      await ns.cancelReminderAllDays(NotificationService.morningAdhkarBase);
    }
    if (_eveningAdhkar) {
      allOk &= await ns.scheduleEveningAdhkar(
        hour: _eveningTime.hour,
        minute: _eveningTime.minute,
        days: _eveningDays.toList()..sort(),
      );
    } else {
      await ns.cancelReminderAllDays(NotificationService.eveningAdhkarBase);
    }
    if (_habitCheckin) {
      allOk &= await ns.scheduleHabitCheckin(
        hour: _habitCheckinTime.hour,
        minute: _habitCheckinTime.minute,
        days: _habitCheckinDays.toList()..sort(),
      );
    } else {
      await ns.cancelReminderAllDays(NotificationService.habitCheckinBase);
    }
    return allOk;
  }

  /// Request notification permission; show snackbar if denied.
  Future<bool> _ensureNotificationPermission() async {
    final granted = await NotificationService.instance.requestPermission();
    if (!granted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enable notifications in device settings to receive reminders.'),
          backgroundColor: Color(0xFFD97706),
        ),
      );
    }
    return granted;
  }

  /// Toggle handler. Order matters: we only flip the UI switch ON after
  /// scheduling succeeds, and OFF after cancel returns. If anything fails
  /// the toggle stays in its previous position and we show an explicit
  /// snackbar — no more "switch says ON but no notification ever fires".
  ///
  /// [reminderBase] is the per-day-base ID (e.g. journalReminderBase).
  /// Cancel path wipes all 7 day-slots in one call.
  Future<void> _handleToggle({
    required bool newValue,
    required Future<bool> Function() schedule,
    required int reminderBase,
    required void Function(bool) updateState,
  }) async {
    if (newValue) {
      final hasPermission = await _ensureNotificationPermission();
      if (!hasPermission) return; // toggle stays OFF
      final scheduled = await schedule();
      if (!mounted) return;
      if (!scheduled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not schedule reminder. Check "Alarms & reminders" permission in app settings.',
            ),
            backgroundColor: Color(0xFFDC2626),
            duration: Duration(seconds: 6),
          ),
        );
        return; // toggle stays OFF on failure
      }
      setState(() => updateState(true));
    } else {
      await NotificationService.instance.cancelReminderAllDays(reminderBase);
      if (!mounted) return;
      setState(() => updateState(false));
    }
    await _saveSettings();
  }

  /// Open the native time picker, save the new time, and reschedule all
  /// enabled days at the new time if the reminder is currently ON.
  Future<void> _pickTime({
    required TimeOfDay current,
    required ValueChanged<TimeOfDay> onPicked,
    required bool reminderEnabled,
    required Future<bool> Function() reschedule,
    required int reminderBase,
  }) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: current,
    );
    if (picked == null || !mounted) return;
    setState(() => onPicked(picked));
    await _saveSettings();
    if (reminderEnabled) {
      // Cancel-then-reschedule. The schedule method already cancels-all
      // internally as a defensive first step, but we cancel explicitly
      // here so any half-replaced state from a previous failure is gone.
      await NotificationService.instance.cancelReminderAllDays(reminderBase);
      final ok = await reschedule();
      if (!mounted) return;
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not reschedule reminder.'),
            backgroundColor: Color(0xFFDC2626),
          ),
        );
        return;
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Reminder updated to ${picked.format(context)}'),
        backgroundColor: const Color(0xFF15803D),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Toggle a single weekday in the set, persist, and reschedule. Refuses
  /// to disable the last enabled day — the user must always have at least
  /// one day selected (otherwise the reminder is effectively orphaned).
  Future<void> _toggleDay({
    required Set<int> days,
    required int weekday, // 1..7
    required ValueChanged<Set<int>> onUpdated,
    required bool reminderEnabled,
    required Future<bool> Function() reschedule,
    required int reminderBase,
  }) async {
    final next = Set<int>.from(days);
    if (next.contains(weekday)) {
      if (next.length == 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pick at least one day.')),
        );
        return;
      }
      next.remove(weekday);
    } else {
      next.add(weekday);
    }
    setState(() => onUpdated(next));
    await _saveSettings();
    if (reminderEnabled) {
      await NotificationService.instance.cancelReminderAllDays(reminderBase);
      await reschedule();
    }
  }

  /// Persist toggle state to Firestore. Surfaces save errors via snackbar
  /// rather than swallowing them so notification state and stored state
  /// don't diverge silently.
  Future<void> _saveSettings() async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('settings')
          .doc('reminders')
          .set({
        // Toggles
        'journalReminder': _journalReminder,
        'morningAdhkar': _morningAdhkar,
        'eveningAdhkar': _eveningAdhkar,
        'habitCheckin': _habitCheckin,
        // Times
        'journalHour': _journalTime.hour,
        'journalMinute': _journalTime.minute,
        'morningHour': _morningTime.hour,
        'morningMinute': _morningTime.minute,
        'eveningHour': _eveningTime.hour,
        'eveningMinute': _eveningTime.minute,
        'habitCheckinHour': _habitCheckinTime.hour,
        'habitCheckinMinute': _habitCheckinTime.minute,
        // Days (sorted for predictable Firestore storage order)
        'journalDays': _journalDays.toList()..sort(),
        'morningDays': _morningDays.toList()..sort(),
        'eveningDays': _eveningDays.toList()..sort(),
        'habitCheckinDays': _habitCheckinDays.toList()..sort(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save settings: $e')),
        );
      }
    }
  }

  /// Fires a notification right now so the user can verify the full stack
  /// (permission + channel + icon) works without waiting for a scheduled
  /// time. Shows success/failure feedback so it's obvious what state we
  /// ended up in.
  Future<void> _handleSendTest() async {
    final hasPermission = await _ensureNotificationPermission();
    if (!hasPermission) return;
    final ok = await NotificationService.instance.sendTestNotification();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Sent. Pull down your status bar to see it.'
              : 'Could not send test notification — check device notification settings.',
        ),
        backgroundColor: ok ? const Color(0xFF15803D) : const Color(0xFFDC2626),
      ),
    );
  }

  Future<void> _loadWisdom() async {
    final wisdom = await DailyWisdomService.getDailyWisdom();
    if (mounted) setState(() => _wisdom = wisdom);
  }

  Future<void> _loadTodayStatus() async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    // Check if journaled today
    final journalSnap = await FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .collection('journals')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
        .limit(1)
        .get();
    final hasJournaled = journalSnap.docs.isNotEmpty;

    // Check habits
    final habitsSnap = await FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .collection('habits')
        .where('isActive', isEqualTo: true)
        .get();
    final total = habitsSnap.docs.length;

    final logsSnap = await FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .collection('habitLogs')
        .where('date', isEqualTo: todayStr)
        .get();
    final completed = logsSnap.docs.where((d) => (d.data())['completed'] == true).length;

    if (mounted) {
      setState(() {
        _hasJournaledToday = hasJournaled;
        _habitsTotal = total;
        _habitsCompleted = completed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        title: const Text(
          'Reminders',
          style: TextStyle(color: Color(0xFF15803D), fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        surfaceTintColor: Colors.white,
        iconTheme: const IconThemeData(color: Color(0xFF15803D)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF15803D)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ─── Seerah Nudge Cards ───
                  if (!_hasJournaledToday)
                    _buildNudgeCard(
                      icon: Icons.edit_note_rounded,
                      text: 'The Prophet (PBUH) found solace in reflection — take a moment to write today.',
                      color: const Color(0xFF15803D),
                    ),
                  if (_habitsTotal > 0 && _habitsCompleted < _habitsTotal)
                    _buildNudgeCard(
                      icon: Icons.task_alt_rounded,
                      text: 'Small consistent deeds are most beloved to Allah. You have ${_habitsTotal - _habitsCompleted} habits remaining today.',
                      color: const Color(0xFF2563EB),
                    ),
                  if (_hasJournaledToday && _habitsCompleted == _habitsTotal && _habitsTotal > 0)
                    _buildNudgeCard(
                      icon: Icons.star_rounded,
                      text: 'MashaAllah! You\'ve journaled and completed all habits today. May Allah bless your consistency.',
                      color: const Color(0xFFD97706),
                    ),

                  const SizedBox(height: 24),

                  // ─── Seerah Anecdote of the Day ───
                  const Text(
                    'Seerah Reflection',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1F2937)),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.mosque_rounded, color: Color(0xFF15803D), size: 28),
                        const SizedBox(height: 12),
                        Text(
                          _wisdom?['summary'] ?? _wisdom?['lesson'] ?? '',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF374151),
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _wisdom?['story_title'] ?? '',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade500,
                          ),
                        ),
                        if ((_wisdom?['story_period'] ?? '').isNotEmpty)
                          Text(
                            _wisdom!['story_period'],
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  // ─── Daily Reminders Toggles ───
                  const Text(
                    'Daily Reminders',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1F2937)),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Set reminders to stay consistent with your spiritual journey.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
                  ),
                  const SizedBox(height: 16),

                  _buildReminderTile(
                    icon: Icons.edit_note_rounded,
                    title: 'Journal Reflection',
                    subtitle: 'Daily reminder to reflect and write',
                    value: _journalReminder,
                    time: _journalTime,
                    days: _journalDays,
                    onChanged: (v) => _handleToggle(
                      newValue: v,
                      schedule: () => NotificationService.instance.scheduleJournalReminder(
                        hour: _journalTime.hour,
                        minute: _journalTime.minute,
                        days: _journalDays.toList()..sort(),
                      ),
                      reminderBase: NotificationService.journalReminderBase,
                      updateState: (val) => _journalReminder = val,
                    ),
                    onTimeTap: () => _pickTime(
                      current: _journalTime,
                      onPicked: (t) => _journalTime = t,
                      reminderEnabled: _journalReminder,
                      reschedule: () => NotificationService.instance.scheduleJournalReminder(
                        hour: _journalTime.hour,
                        minute: _journalTime.minute,
                        days: _journalDays.toList()..sort(),
                      ),
                      reminderBase: NotificationService.journalReminderBase,
                    ),
                    onDayTap: (weekday) => _toggleDay(
                      days: _journalDays,
                      weekday: weekday,
                      onUpdated: (s) => _journalDays = s,
                      reminderEnabled: _journalReminder,
                      reschedule: () => NotificationService.instance.scheduleJournalReminder(
                        hour: _journalTime.hour,
                        minute: _journalTime.minute,
                        days: _journalDays.toList()..sort(),
                      ),
                      reminderBase: NotificationService.journalReminderBase,
                    ),
                  ),
                  _buildReminderTile(
                    icon: Icons.wb_sunny_rounded,
                    title: 'Morning Adhkar',
                    subtitle: 'After Fajr — start your day with remembrance',
                    value: _morningAdhkar,
                    time: _morningTime,
                    days: _morningDays,
                    onChanged: (v) => _handleToggle(
                      newValue: v,
                      schedule: () => NotificationService.instance.scheduleMorningAdhkar(
                        hour: _morningTime.hour,
                        minute: _morningTime.minute,
                        days: _morningDays.toList()..sort(),
                      ),
                      reminderBase: NotificationService.morningAdhkarBase,
                      updateState: (val) => _morningAdhkar = val,
                    ),
                    onTimeTap: () => _pickTime(
                      current: _morningTime,
                      onPicked: (t) => _morningTime = t,
                      reminderEnabled: _morningAdhkar,
                      reschedule: () => NotificationService.instance.scheduleMorningAdhkar(
                        hour: _morningTime.hour,
                        minute: _morningTime.minute,
                        days: _morningDays.toList()..sort(),
                      ),
                      reminderBase: NotificationService.morningAdhkarBase,
                    ),
                    onDayTap: (weekday) => _toggleDay(
                      days: _morningDays,
                      weekday: weekday,
                      onUpdated: (s) => _morningDays = s,
                      reminderEnabled: _morningAdhkar,
                      reschedule: () => NotificationService.instance.scheduleMorningAdhkar(
                        hour: _morningTime.hour,
                        minute: _morningTime.minute,
                        days: _morningDays.toList()..sort(),
                      ),
                      reminderBase: NotificationService.morningAdhkarBase,
                    ),
                  ),
                  _buildReminderTile(
                    icon: Icons.nights_stay_rounded,
                    title: 'Evening Adhkar',
                    subtitle: 'After Asr — wind down with gratitude',
                    value: _eveningAdhkar,
                    time: _eveningTime,
                    days: _eveningDays,
                    onChanged: (v) => _handleToggle(
                      newValue: v,
                      schedule: () => NotificationService.instance.scheduleEveningAdhkar(
                        hour: _eveningTime.hour,
                        minute: _eveningTime.minute,
                        days: _eveningDays.toList()..sort(),
                      ),
                      reminderBase: NotificationService.eveningAdhkarBase,
                      updateState: (val) => _eveningAdhkar = val,
                    ),
                    onTimeTap: () => _pickTime(
                      current: _eveningTime,
                      onPicked: (t) => _eveningTime = t,
                      reminderEnabled: _eveningAdhkar,
                      reschedule: () => NotificationService.instance.scheduleEveningAdhkar(
                        hour: _eveningTime.hour,
                        minute: _eveningTime.minute,
                        days: _eveningDays.toList()..sort(),
                      ),
                      reminderBase: NotificationService.eveningAdhkarBase,
                    ),
                    onDayTap: (weekday) => _toggleDay(
                      days: _eveningDays,
                      weekday: weekday,
                      onUpdated: (s) => _eveningDays = s,
                      reminderEnabled: _eveningAdhkar,
                      reschedule: () => NotificationService.instance.scheduleEveningAdhkar(
                        hour: _eveningTime.hour,
                        minute: _eveningTime.minute,
                        days: _eveningDays.toList()..sort(),
                      ),
                      reminderBase: NotificationService.eveningAdhkarBase,
                    ),
                  ),
                  _buildReminderTile(
                    icon: Icons.task_alt_rounded,
                    title: 'Habit Check-in',
                    subtitle: 'Evening reminder to complete your habits',
                    value: _habitCheckin,
                    time: _habitCheckinTime,
                    days: _habitCheckinDays,
                    onChanged: (v) => _handleToggle(
                      newValue: v,
                      schedule: () => NotificationService.instance.scheduleHabitCheckin(
                        hour: _habitCheckinTime.hour,
                        minute: _habitCheckinTime.minute,
                        days: _habitCheckinDays.toList()..sort(),
                      ),
                      reminderBase: NotificationService.habitCheckinBase,
                      updateState: (val) => _habitCheckin = val,
                    ),
                    onTimeTap: () => _pickTime(
                      current: _habitCheckinTime,
                      onPicked: (t) => _habitCheckinTime = t,
                      reminderEnabled: _habitCheckin,
                      reschedule: () => NotificationService.instance.scheduleHabitCheckin(
                        hour: _habitCheckinTime.hour,
                        minute: _habitCheckinTime.minute,
                        days: _habitCheckinDays.toList()..sort(),
                      ),
                      reminderBase: NotificationService.habitCheckinBase,
                    ),
                    onDayTap: (weekday) => _toggleDay(
                      days: _habitCheckinDays,
                      weekday: weekday,
                      onUpdated: (s) => _habitCheckinDays = s,
                      reminderEnabled: _habitCheckin,
                      reschedule: () => NotificationService.instance.scheduleHabitCheckin(
                        hour: _habitCheckinTime.hour,
                        minute: _habitCheckinTime.minute,
                        days: _habitCheckinDays.toList()..sort(),
                      ),
                      reminderBase: NotificationService.habitCheckinBase,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Test button — fires a notification right now so the
                  // user (or a viva examiner) can verify the whole
                  // notification stack works without waiting for 8 PM.
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _handleSendTest,
                      icon: const Icon(Icons.notifications_active_rounded, size: 18),
                      label: const Text('Send test notification now'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF15803D),
                        side: const BorderSide(color: Color(0xFF15803D)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }

  Widget _buildNudgeCard({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: color, height: 1.4, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReminderTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required TimeOfDay time,
    required Set<int> days,
    required VoidCallback onTimeTap,
    required ValueChanged<int> onDayTap, // weekday 1..7
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: icon + title + master toggle
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: const Color(0xFF15803D), size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: value,
                onChanged: onChanged,
                activeColor: const Color(0xFF15803D),
              ),
            ],
          ),

          // Row 2: time chip. Tappable regardless of toggle state so the
          // user can pre-configure their time before enabling.
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 54, right: 4),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onTimeTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.alarm_rounded,
                      size: 16,
                      color: Color(0xFF15803D),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      time.format(context),
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF1F2937),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.edit_rounded,
                      size: 12,
                      color: Color(0xFF9CA3AF),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Row 3: 7 day-of-week chips
          Padding(
            padding: const EdgeInsets.only(top: 10, left: 54, right: 4),
            child: Wrap(
              spacing: 6,
              children: [
                for (int wd = 1; wd <= 7; wd++)
                  _DayChip(
                    label: const ['M', 'T', 'W', 'T', 'F', 'S', 'S'][wd - 1],
                    selected: days.contains(wd),
                    onTap: () => onDayTap(wd),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact 28×28 circle chip representing one day of the week in the
/// reminder tiles. Filled green when the day is enabled, hollow grey when
/// not. Used by [_RemindersScreenState._buildReminderTile].
class _DayChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _DayChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? const Color(0xFF15803D) : Colors.white,
          border: Border.all(
            color: selected
                ? const Color(0xFF15803D)
                : const Color(0xFFD1D5DB),
            width: 1.2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : const Color(0xFF6B7280),
          ),
        ),
      ),
    );
  }
}
