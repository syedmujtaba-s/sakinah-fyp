import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .collection('settings')
        .doc('reminders')
        .get();

    if (doc.exists) {
      final data = doc.data()!;
      if (mounted) {
        setState(() {
          _journalReminder = data['journalReminder'] ?? false;
          _morningAdhkar = data['morningAdhkar'] ?? false;
          _eveningAdhkar = data['eveningAdhkar'] ?? false;
          _habitCheckin = data['habitCheckin'] ?? false;
          _loading = false;
        });
        _syncNotifications();
      }
    } else {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Re-schedule or cancel notifications to match current toggle states.
  Future<void> _syncNotifications() async {
    final ns = NotificationService.instance;
    if (_journalReminder) {
      await ns.scheduleJournalReminder();
    } else {
      await ns.cancelNotification(NotificationService.journalReminderId);
    }
    if (_morningAdhkar) {
      await ns.scheduleMorningAdhkar();
    } else {
      await ns.cancelNotification(NotificationService.morningAdhkarId);
    }
    if (_eveningAdhkar) {
      await ns.scheduleEveningAdhkar();
    } else {
      await ns.cancelNotification(NotificationService.eveningAdhkarId);
    }
    if (_habitCheckin) {
      await ns.scheduleHabitCheckin();
    } else {
      await ns.cancelNotification(NotificationService.habitCheckinId);
    }
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

  /// Toggle handler: checks permission, schedules/cancels, saves to Firestore.
  Future<void> _handleToggle({
    required bool newValue,
    required Future<void> Function() schedule,
    required int notificationId,
    required void Function(bool) updateState,
  }) async {
    if (newValue) {
      final hasPermission = await _ensureNotificationPermission();
      if (!hasPermission) return;
      setState(() => updateState(newValue));
      await schedule();
    } else {
      setState(() => updateState(newValue));
      await NotificationService.instance.cancelNotification(notificationId);
    }
    _saveSettings();
  }

  Future<void> _saveSettings() async {
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
