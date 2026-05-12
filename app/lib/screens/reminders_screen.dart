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
  /// Returns true if all schedule/cancel operations succeeded.
  Future<bool> _syncNotifications() async {
    final ns = NotificationService.instance;
    bool allOk = true;
    if (_journalReminder) {
      allOk &= await ns.scheduleJournalReminder();
    } else {
      await ns.cancelNotification(NotificationService.journalReminderId);
    }
    if (_morningAdhkar) {
      allOk &= await ns.scheduleMorningAdhkar();
    } else {
      await ns.cancelNotification(NotificationService.morningAdhkarId);
    }
    if (_eveningAdhkar) {
      allOk &= await ns.scheduleEveningAdhkar();
    } else {
      await ns.cancelNotification(NotificationService.eveningAdhkarId);
    }
    if (_habitCheckin) {
      allOk &= await ns.scheduleHabitCheckin();
    } else {
      await ns.cancelNotification(NotificationService.habitCheckinId);
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
  Future<void> _handleToggle({
    required bool newValue,
    required Future<bool> Function() schedule,
    required int notificationId,
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
      await NotificationService.instance.cancelNotification(notificationId);
      if (!mounted) return;
      setState(() => updateState(false));
    }
    await _saveSettings();
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
        'journalReminder': _journalReminder,
        'morningAdhkar': _morningAdhkar,
        'eveningAdhkar': _eveningAdhkar,
        'habitCheckin': _habitCheckin,
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
                    subtitle: 'Daily reminder to reflect and write (8:00 PM)',
                    value: _journalReminder,
                    onChanged: (v) => _handleToggle(
                      newValue: v,
                      schedule: NotificationService.instance.scheduleJournalReminder,
                      notificationId: NotificationService.journalReminderId,
                      updateState: (val) => _journalReminder = val,
                    ),
                  ),
                  _buildReminderTile(
                    icon: Icons.wb_sunny_rounded,
                    title: 'Morning Adhkar',
                    subtitle: 'After Fajr — start your day with remembrance (6:00 AM)',
                    value: _morningAdhkar,
                    onChanged: (v) => _handleToggle(
                      newValue: v,
                      schedule: NotificationService.instance.scheduleMorningAdhkar,
                      notificationId: NotificationService.morningAdhkarId,
                      updateState: (val) => _morningAdhkar = val,
                    ),
                  ),
                  _buildReminderTile(
                    icon: Icons.nights_stay_rounded,
                    title: 'Evening Adhkar',
                    subtitle: 'After Asr — wind down with gratitude (5:00 PM)',
                    value: _eveningAdhkar,
                    onChanged: (v) => _handleToggle(
                      newValue: v,
                      schedule: NotificationService.instance.scheduleEveningAdhkar,
                      notificationId: NotificationService.eveningAdhkarId,
                      updateState: (val) => _eveningAdhkar = val,
                    ),
                  ),
                  _buildReminderTile(
                    icon: Icons.task_alt_rounded,
                    title: 'Habit Check-in',
                    subtitle: 'Evening reminder to complete your habits (9:00 PM)',
                    value: _habitCheckin,
                    onChanged: (v) => _handleToggle(
                      newValue: v,
                      schedule: NotificationService.instance.scheduleHabitCheckin,
                      notificationId: NotificationService.habitCheckinId,
                      updateState: (val) => _habitCheckin = val,
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
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
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
                Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1F2937))),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
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
    );
  }
}
