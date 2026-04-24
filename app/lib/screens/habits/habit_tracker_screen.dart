import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../widgets/progress_ring.dart';
import '../../widgets/habit_card.dart';
import '../../models/habit_feedback_status.dart';
import '../journaling_screen.dart';
import 'add_habit_screen.dart';
import 'archived_habits_screen.dart';
import 'habit_detail_screen.dart';

// Shared icon map used by habit tracker and add habit screens
const Map<String, IconData> habitIconMap = {
  'mosque': Icons.mosque_rounded,
  'menu_book': Icons.menu_book_rounded,
  'wb_sunny': Icons.wb_sunny_rounded,
  'nights_stay': Icons.nights_stay_rounded,
  'favorite': Icons.favorite_rounded,
  'volunteer_activism': Icons.volunteer_activism_rounded,
  'self_improvement': Icons.self_improvement_rounded,
  'fitness_center': Icons.fitness_center_rounded,
  'water_drop': Icons.water_drop_rounded,
  'school': Icons.school_rounded,
  'family_restroom': Icons.family_restroom_rounded,
  'handshake': Icons.handshake_rounded,
  'local_hospital': Icons.local_hospital_rounded,
  'bedtime': Icons.bedtime_rounded,
  'emoji_food_beverage': Icons.emoji_food_beverage_rounded,
  'directions_walk': Icons.directions_walk_rounded,
  'psychology': Icons.psychology_rounded,
  'spa': Icons.spa_rounded,
  'star': Icons.star_rounded,
  'lightbulb': Icons.lightbulb_rounded,
};

IconData getHabitIcon(String key) => habitIconMap[key] ?? Icons.check_circle_rounded;

Color getHabitColor(String hex) {
  try {
    return Color(int.parse(hex.replaceFirst('#', '0xFF')));
  } catch (_) {
    return const Color(0xFF15803D);
  }
}

// All date keys are the user's LOCAL calendar date (YYYY-MM-DD).
// Any UTC DateTime (e.g. from Firestore server timestamps) is normalized to
// the device's local zone first so cross-timezone use doesn't shift the day.
String dateStr(DateTime d) {
  final local = d.isUtc ? d.toLocal() : d;
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
}

// Calendar-day distance (not millisecond distance). Needed because
// "createdAt minus now" in inDays can read 0 across an actual midnight
// crossing, which makes age-based thresholds behave inconsistently.
int calendarDaysBetween(DateTime from, DateTime to) {
  final a = DateTime((from.isUtc ? from.toLocal() : from).year,
      (from.isUtc ? from.toLocal() : from).month,
      (from.isUtc ? from.toLocal() : from).day);
  final b = DateTime((to.isUtc ? to.toLocal() : to).year,
      (to.isUtc ? to.toLocal() : to).month,
      (to.isUtc ? to.toLocal() : to).day);
  return b.difference(a).inDays;
}

class HabitTrackerScreen extends StatefulWidget {
  const HabitTrackerScreen({super.key});

  @override
  State<HabitTrackerScreen> createState() => _HabitTrackerScreenState();
}

class _HabitTrackerScreenState extends State<HabitTrackerScreen> {
  String _selectedCategory = 'All';
  bool _seeding = false;
  // Top-level toggle between the two habit sources.
  bool _showRecommended = false;
  // Category group keys the user has collapsed in this session.
  final Set<String> _collapsedGroups = {};

  final _categories = ['All', 'Prayer', 'Quran', 'Dhikr', 'Wellness', 'Custom'];

  String? get _uidOrNull => FirebaseAuth.instance.currentUser?.uid;
  String get _uid => FirebaseAuth.instance.currentUser!.uid;
  String get _todayStr => dateStr(DateTime.now());

  // Deterministic doc ID from a habit title — keeps re-seeding idempotent.
  String _slug(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');

  // ───── Seed Default Habits ─────
  Future<void> _seedDefaultHabits() async {
    setState(() => _seeding = true);

    try {
      final batch = FirebaseFirestore.instance.batch();
      final habitsRef = FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('habits');

      final defaults = [
        {'title': 'Fajr Prayer', 'category': 'prayer', 'icon': 'mosque', 'color': '#15803D'},
        {'title': 'Dhuhr Prayer', 'category': 'prayer', 'icon': 'mosque', 'color': '#15803D'},
        {'title': 'Asr Prayer', 'category': 'prayer', 'icon': 'mosque', 'color': '#15803D'},
        {'title': 'Maghrib Prayer', 'category': 'prayer', 'icon': 'mosque', 'color': '#15803D'},
        {'title': 'Isha Prayer', 'category': 'prayer', 'icon': 'mosque', 'color': '#15803D'},
        {'title': 'Quran Reading', 'category': 'quran', 'icon': 'menu_book', 'color': '#2563EB'},
        {'title': 'Morning Adhkar', 'category': 'dhikr', 'icon': 'wb_sunny', 'color': '#D97706'},
        {'title': 'Evening Adhkar', 'category': 'dhikr', 'icon': 'nights_stay', 'color': '#4F46E5'},
        {'title': 'Dhikr / Tasbeeh', 'category': 'dhikr', 'icon': 'favorite', 'color': '#7C3AED'},
        {'title': 'Charity / Sadaqah', 'category': 'wellness', 'icon': 'volunteer_activism', 'color': '#0D9488'},
      ];

      for (final h in defaults) {
        final docId = 'default_${_slug(h['title']!)}';
        final doc = habitsRef.doc(docId);
        batch.set(doc, {
          ...h,
          'frequency': 'daily',
          'isActive': true,
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      await batch.commit();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Starter Islamic habits added.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not add starter habits: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _seeding = false);
      }
    }
  }

  // ───── Clean Up Duplicate Habits ─────
  Future<void> _cleanUpDuplicates() async {
    final uid = _uidOrNull;
    if (uid == null) return;

    final habitsRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('habits');

    final snap = await habitsRef.get();

    // Group by normalized title
    final groups = <String, List<QueryDocumentSnapshot>>{};
    for (final doc in snap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final key = (data['title']?.toString() ?? '').trim().toLowerCase();
      if (key.isEmpty) continue;
      groups.putIfAbsent(key, () => []).add(doc);
    }

    // Decide which doc per group to keep: prefer a `default_*` ID, else the oldest createdAt.
    final toDelete = <QueryDocumentSnapshot>[];
    for (final entry in groups.entries) {
      if (entry.value.length < 2) continue;
      final docs = entry.value.toList();
      docs.sort((a, b) {
        final aDefault = a.id.startsWith('default_') ? 0 : 1;
        final bDefault = b.id.startsWith('default_') ? 0 : 1;
        if (aDefault != bDefault) return aDefault.compareTo(bDefault);
        final aTs = (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
        final bTs = (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
        if (aTs == null && bTs == null) return 0;
        if (aTs == null) return 1;
        if (bTs == null) return -1;
        return aTs.compareTo(bTs);
      });
      // Keep docs[0], delete the rest
      toDelete.addAll(docs.skip(1));
    }

    if (toDelete.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No duplicates found.'), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    // Confirm with the user before destructive action
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clean up duplicates?'),
        content: Text(
          'Found ${toDelete.length} duplicate habit(s) across ${groups.entries.where((e) => e.value.length > 1).length} title(s).\n\n'
          'The oldest entry for each title is kept. Completion logs tied to removed duplicates will also be deleted.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete duplicates'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final db = FirebaseFirestore.instance;
      final deletedIds = toDelete.map((d) => d.id).toList();

      // Delete habit docs (batched, chunks of 500)
      for (var i = 0; i < toDelete.length; i += 500) {
        final batch = db.batch();
        for (final doc in toDelete.skip(i).take(500)) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }

      // Delete orphan habitLogs pointing to deleted habit IDs (whereIn capped at 30 per query)
      final logsRef = db.collection('users').doc(uid).collection('habitLogs');
      for (var i = 0; i < deletedIds.length; i += 30) {
        final chunk = deletedIds.skip(i).take(30).toList();
        final logsSnap = await logsRef.where('habitId', whereIn: chunk).get();
        for (var j = 0; j < logsSnap.docs.length; j += 500) {
          final batch = db.batch();
          for (final logDoc in logsSnap.docs.skip(j).take(500)) {
            batch.delete(logDoc.reference);
          }
          await batch.commit();
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cleaned up ${toDelete.length} duplicate(s).'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cleanup failed: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ───── Feedback Loop: mark applied advice as Success / Struggled ─────
  Future<void> _markFeedback(String habitId, HabitFeedbackStatus status) async {
    final uid = _uidOrNull;
    if (uid == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('habits')
          .doc(habitId)
          .update({
        'feedbackStatus': status.wire,
        'feedbackAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(status == HabitFeedbackStatus.success
              ? 'MashaAllah — keep going.'
              : 'Thanks for the feedback.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save feedback: $e')),
      );
    }
  }

  Future<void> _handleStruggled(
    String habitId,
    Map<String, dynamic> habitData,
  ) async {
    // Record the feedback so the strip disappears regardless of what happens next.
    await _markFeedback(habitId, HabitFeedbackStatus.struggled);

    if (!mounted) return;

    final sourceEmotion = habitData['sourceEmotion']?.toString() ?? '';
    final sourceStoryId = habitData['sourceStoryId']?.toString() ?? '';
    if (sourceEmotion.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => JournalingScreen(
          mood: sourceEmotion,
          excludeStoryIds: sourceStoryId.isNotEmpty ? [sourceStoryId] : const [],
        ),
      ),
    );
  }

  // ───── Toggle Habit Completion ─────
  Future<void> _toggleHabit(String habitId, bool currentlyCompleted) async {
    final logId = '${_todayStr}_$habitId';
    final logRef = FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .collection('habitLogs')
        .doc(logId);

    if (currentlyCompleted) {
      await logRef.delete();
    } else {
      await logRef.set({
        'habitId': habitId,
        'date': _todayStr,
        'completed': true,
        'completedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  // Streak / weekly helpers live inline in build() and read from a single
  // 365-day habitLogs stream, so no per-card Firestore round-trips here.

  @override
  Widget build(BuildContext context) {
    final uid = _uidOrNull;
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        title: const Text(
          'Habit Tracker',
          style: TextStyle(color: Color(0xFF15803D), fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        surfaceTintColor: Colors.white,
        centerTitle: true,
        automaticallyImplyLeading: false,
        actions: uid == null
            ? null
            : [
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Color(0xFF6B7280)),
                  onSelected: (value) {
                    if (value == 'cleanup') _cleanUpDuplicates();
                    if (value == 'archived') {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ArchivedHabitsScreen()),
                      );
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'archived',
                      child: Row(
                        children: [
                          Icon(Icons.archive_outlined, size: 20, color: Color(0xFF6B7280)),
                          SizedBox(width: 12),
                          Text('Archived habits'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'cleanup',
                      child: Row(
                        children: [
                          Icon(Icons.cleaning_services_outlined, size: 20, color: Color(0xFF6B7280)),
                          SizedBox(width: 12),
                          Text('Clean up duplicates'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
      ),
      floatingActionButton: uid == null
          ? null
          : FloatingActionButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddHabitScreen()),
                );
              },
              backgroundColor: const Color(0xFF15803D),
              child: const Icon(Icons.add, color: Colors.white),
            ),
      body: uid == null
          ? _buildSignInRequired()
          : StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('habits')
            .where('isActive', isEqualTo: true)
            .snapshots(),
        builder: (context, habitsSnap) {
          if (habitsSnap.hasError) {
            return _buildErrorState(habitsSnap.error);
          }
          if (habitsSnap.connectionState == ConnectionState.waiting &&
              !habitsSnap.hasData) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF15803D)));
          }

          // Client-side sort by createdAt (removes need for a composite Firestore index)
          final habits = List<QueryDocumentSnapshot>.from(habitsSnap.data?.docs ?? []);
          habits.sort((a, b) {
            final aTs = (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
            final bTs = (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
            if (aTs == null && bTs == null) return 0;
            if (aTs == null) return 1;
            if (bTs == null) return -1;
            return aTs.compareTo(bTs);
          });

          // Empty state
          if (habits.isEmpty) {
            return _buildEmptyState();
          }

          // Filter by category
          final filtered = _selectedCategory == 'All'
              ? habits
              : habits.where((h) {
                  final cat = (h.data() as Map<String, dynamic>)['category'] ?? '';
                  return cat.toString().toLowerCase() == _selectedCategory.toLowerCase();
                }).toList();

          // One 365-day habitLogs stream feeds all per-habit calculations
          // (today, weekly dots, streak). Replaces the previous per-card
          // FutureBuilder that was doing N*365 doc.get()s on every rebuild.
          final now = DateTime.now();
          final todayKey = dateStr(now);
          final cutoffKey = dateStr(now.subtract(const Duration(days: 365)));

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .collection('habitLogs')
                .where('date', isGreaterThanOrEqualTo: cutoffKey)
                .snapshots(),
            builder: (context, logsSnap) {
              // habitId -> set of YYYY-MM-DD strings where it was completed.
              // Log failures degrade gracefully — habits still render.
              final Map<String, Set<String>> doneDates = {};
              if (logsSnap.hasData) {
                for (final doc in logsSnap.data!.docs) {
                  final data = doc.data() as Map<String, dynamic>;
                  if (data['completed'] != true) continue;
                  final hid = data['habitId']?.toString() ?? '';
                  final d = data['date']?.toString() ?? '';
                  if (hid.isEmpty || d.isEmpty) continue;
                  (doneDates[hid] ??= <String>{}).add(d);
                }
              }

              bool isDoneToday(String habitId) =>
                  (doneDates[habitId] ?? const <String>{}).contains(todayKey);

              List<bool> weeklyOf(String habitId) {
                final dates = doneDates[habitId] ?? const <String>{};
                return List<bool>.generate(7, (i) {
                  final d = now.subtract(Duration(days: 6 - i));
                  return dates.contains(dateStr(DateTime(d.year, d.month, d.day)));
                });
              }

              int dailyStreakOf(String habitId) {
                final dates = doneDates[habitId] ?? const <String>{};
                if (dates.isEmpty) return 0;
                int streak = 0;
                var cursor = DateTime(now.year, now.month, now.day);
                if (!dates.contains(dateStr(cursor))) {
                  // Today not done yet — count from yesterday.
                  cursor = cursor.subtract(const Duration(days: 1));
                }
                while (dates.contains(dateStr(cursor))) {
                  streak++;
                  cursor = cursor.subtract(const Duration(days: 1));
                  if (streak > 365) break;
                }
                return streak;
              }

              // Start of the user's local week (Monday 00:00)
              DateTime startOfWeek(DateTime d) {
                final local = d.isUtc ? d.toLocal() : d;
                final daysFromMonday = (local.weekday - DateTime.monday) % 7;
                return DateTime(local.year, local.month, local.day)
                    .subtract(Duration(days: daysFromMonday));
              }

              int weeklyDoneCount(String habitId, DateTime weekStart) {
                final dates = doneDates[habitId] ?? const <String>{};
                int count = 0;
                for (int i = 0; i < 7; i++) {
                  final d = weekStart.add(Duration(days: i));
                  if (dates.contains(dateStr(d))) count++;
                }
                return count;
              }

              // Counts consecutive past weeks (Mon-Sun) where weeklyDone >= target.
              // The current week is skipped if the target isn't hit yet (matches
              // daily-streak semantics: "don't punish me for today not being over").
              int weeklyStreakOf(String habitId, int target) {
                if (target <= 0) return 0;
                int streak = 0;
                var weekStart = startOfWeek(now);
                if (weeklyDoneCount(habitId, weekStart) < target) {
                  weekStart = weekStart.subtract(const Duration(days: 7));
                }
                while (weeklyDoneCount(habitId, weekStart) >= target) {
                  streak++;
                  weekStart = weekStart.subtract(const Duration(days: 7));
                  if (streak > 104) break; // two years of weeks — enough
                }
                return streak;
              }

              final completedCount =
                  habits.where((h) => isDoneToday(h.id)).length;

              // Partition: Recommended (guidance-sourced) vs My Habits.
              final List<QueryDocumentSnapshot> recommendations = [];
              final List<QueryDocumentSnapshot> myHabits = [];
              for (final doc in filtered) {
                final data = doc.data() as Map<String, dynamic>;
                final hasSource =
                    (data['sourceAdvice']?.toString().isNotEmpty ?? false);
                if (hasSource) {
                  recommendations.add(doc);
                } else {
                  myHabits.add(doc);
                }
              }

              int sortByDone(QueryDocumentSnapshot a, QueryDocumentSnapshot b) {
                final aDone = isDoneToday(a.id) ? 1 : 0;
                final bDone = isDoneToday(b.id) ? 1 : 0;
                return aDone.compareTo(bDone);
              }
              myHabits.sort(sortByDone);
              recommendations.sort(sortByDone);

              Widget buildCard(QueryDocumentSnapshot doc) {
                final data = doc.data() as Map<String, dynamic>;
                final habitId = doc.id;
                final isDone = isDoneToday(habitId);

                final hasSource =
                    (data['sourceAdvice']?.toString().isNotEmpty ?? false);
                final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
                final ageDays = createdAt == null
                    ? 0
                    : calendarDaysBetween(createdAt, DateTime.now());
                final feedback = HabitFeedbackStatus.fromWire(data['feedbackStatus']);
                final showFeedback =
                    hasSource && ageDays >= 3 && feedback == HabitFeedbackStatus.none;

                // Frequency-aware streak and progress
                final isWeekly = (data['frequency']?.toString() ?? 'daily') == 'weekly';
                final rawTarget = data['targetPerWeek'];
                final target = (isWeekly && rawTarget is int) ? rawTarget : 0;
                final streak = isWeekly
                    ? weeklyStreakOf(habitId, target)
                    : dailyStreakOf(habitId);
                final weeklyDone = isWeekly
                    ? weeklyDoneCount(habitId, startOfWeek(now))
                    : 0;

                return HabitCard(
                  title: data['title'] ?? '',
                  category: data['category'] ?? 'custom',
                  icon: getHabitIcon(data['icon'] ?? ''),
                  color: getHabitColor(data['color'] ?? '#15803D'),
                  streak: streak,
                  completedToday: isDone,
                  weeklyStatus: weeklyOf(habitId),
                  weeklyTarget: target,
                  weeklyDone: weeklyDone,
                  onToggle: () => _toggleHabit(habitId, isDone),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => HabitDetailScreen(
                          habitId: habitId,
                          habitData: data,
                        ),
                      ),
                    );
                  },
                  showFeedbackPrompt: showFeedback,
                  onFeedbackSuccess: () => _markFeedback(habitId, HabitFeedbackStatus.success),
                  onFeedbackStruggled: () => _handleStruggled(habitId, data),
                );
              }

              final activeList = _showRecommended ? recommendations : myHabits;

              return SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Center(
                      child: ProgressRing(
                        completed: completedCount,
                        total: habits.length,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      completedCount == habits.length
                          ? 'MashaAllah! All done today!'
                          : 'Keep going, you\'re doing great!',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                    ),
                    const SizedBox(height: 20),

                    // Segmented toggle: My Habits  |  Recommended
                    _buildSegmentedToggle(
                      myCount: myHabits.length,
                      recCount: recommendations.length,
                    ),
                    const SizedBox(height: 16),

                    // Category filter chips
                    SizedBox(
                      height: 38,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _categories.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, i) {
                          final cat = _categories[i];
                          final selected = _selectedCategory == cat;
                          return ChoiceChip(
                            label: Text(cat),
                            selected: selected,
                            onSelected: (_) => setState(() => _selectedCategory = cat),
                            selectedColor: const Color(0xFFDCFCE7),
                            backgroundColor: Colors.white,
                            labelStyle: TextStyle(
                              color: selected ? const Color(0xFF15803D) : const Color(0xFF6B7280),
                              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                              fontSize: 13,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: BorderSide(
                                color: selected ? const Color(0xFF15803D) : Colors.grey.shade300,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 20),

                    if (activeList.isEmpty)
                      _buildSectionEmpty(
                        _showRecommended
                            ? 'When you reflect and receive guidance, tap “Track” on any practical advice to see it here.'
                            : (_selectedCategory == 'All'
                                ? 'No personal habits yet. Tap + to add one.'
                                : 'No $_selectedCategory habits in this view.'),
                      )
                    else
                      ..._buildGroupedHabits(activeList, buildCard),

                    // All-done-today footer — shown when every habit is checked off
                    if (habits.isNotEmpty &&
                        completedCount == habits.length &&
                        activeList.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFBBF7D0)),
                        ),
                        child: Row(
                          children: const [
                            Text('🌙', style: TextStyle(fontSize: 20)),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'See you tomorrow, insha\'Allah.',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF166534),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 80), // FAB clearance
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  // Group the active habits by category and render each group with a
  // collapsible header. Keeps the compact list from turning into one long
  // scroll when users have 10+ seeded habits.
  List<Widget> _buildGroupedHabits(
    List<QueryDocumentSnapshot> habits,
    Widget Function(QueryDocumentSnapshot) buildCard,
  ) {
    // Preserve original ordering within a group. Category keys are normalized.
    final groups = <String, List<QueryDocumentSnapshot>>{};
    for (final doc in habits) {
      final data = doc.data() as Map<String, dynamic>;
      final rawCat = (data['category']?.toString() ?? 'custom').trim();
      final key = rawCat.isEmpty ? 'custom' : rawCat.toLowerCase();
      (groups[key] ??= []).add(doc);
    }

    // Fixed order first, then any unknown categories after in insertion order.
    const priority = ['prayer', 'quran', 'dhikr', 'wellness', 'custom', 'guidance'];
    final ordered = <String>[
      ...priority.where(groups.containsKey),
      ...groups.keys.where((k) => !priority.contains(k)),
    ];

    // If only a single group ends up rendering (user is filtering to Prayer
    // etc.), skip the headers entirely — they'd just add noise.
    if (ordered.length <= 1) {
      return habits.map(buildCard).toList();
    }

    final widgets = <Widget>[];
    for (final key in ordered) {
      final list = groups[key]!;
      final collapsed = _collapsedGroups.contains(key);
      final label = key[0].toUpperCase() + key.substring(1);

      widgets.add(_buildCategoryGroupHeader(
        label: label,
        count: list.length,
        collapsed: collapsed,
        onTap: () => setState(() {
          if (collapsed) {
            _collapsedGroups.remove(key);
          } else {
            _collapsedGroups.add(key);
          }
        }),
      ));
      if (!collapsed) {
        widgets.addAll(list.map(buildCard));
      }
      widgets.add(const SizedBox(height: 6));
    }
    return widgets;
  }

  Widget _buildCategoryGroupHeader({
    required String label,
    required int count,
    required bool collapsed,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          children: [
            AnimatedRotation(
              turns: collapsed ? -0.25 : 0,
              duration: const Duration(milliseconds: 150),
              child: const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 20,
                color: Color(0xFF6B7280),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF374151),
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B7280),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSegmentedToggle({
    required int myCount,
    required int recCount,
  }) {
    Widget segment({
      required String label,
      required int count,
      required IconData icon,
      required bool selected,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(
              color: selected ? const Color(0xFF15803D) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: selected ? Colors.white : const Color(0xFF6B7280),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : const Color(0xFF6B7280),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.white.withOpacity(0.25)
                        : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : const Color(0xFF6B7280),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          segment(
            label: 'My Habits',
            count: myCount,
            icon: Icons.check_circle_outline_rounded,
            selected: !_showRecommended,
            onTap: () => setState(() => _showRecommended = false),
          ),
          segment(
            label: 'Recommended',
            count: recCount,
            icon: Icons.auto_awesome,
            selected: _showRecommended,
            onTap: () => setState(() => _showRecommended = true),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionEmpty(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280), height: 1.4),
      ),
    );
  }

  Widget _buildSignInRequired() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(Icons.lock_outline_rounded, size: 48, color: Color(0xFF15803D)),
            ),
            const SizedBox(height: 24),
            const Text(
              'Sign in to track habits',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF064E3B)),
            ),
            const SizedBox(height: 12),
            const Text(
              'Your habits and streaks are stored with your account.\nSign in from the Profile tab to get started.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Color(0xFF6B7280), height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(Object? err) {
    final msg = err?.toString() ?? 'Unknown error';
    final isIndexError = msg.toLowerCase().contains('requires an index');
    final indexUrl = isIndexError ? _extractUrl(msg) : null;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(Icons.cloud_off_rounded, size: 48, color: Color(0xFFDC2626)),
            ),
            const SizedBox(height: 24),
            const Text(
              'Could not load habits',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF064E3B)),
            ),
            const SizedBox(height: 12),
            Text(
              msg,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280), height: 1.4),
            ),
            if (indexUrl != null) ...[
              const SizedBox(height: 12),
              SelectableText(
                indexUrl,
                style: const TextStyle(fontSize: 11, color: Color(0xFF2563EB)),
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => setState(() {}),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF15803D),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _extractUrl(String text) {
    final match = RegExp(r'https?://[^\s]+').firstMatch(text);
    return match?.group(0);
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(Icons.task_alt_rounded, size: 48, color: Color(0xFF15803D)),
            ),
            const SizedBox(height: 24),
            const Text(
              'Start Your Journey',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF064E3B),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Build consistent Islamic habits.\nTrack your Salah, Quran, Dhikr and more.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Color(0xFF6B7280), height: 1.5),
            ),
            const SizedBox(height: 8),
            const Text(
              'This adds a starter set directly to your tracker.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _seeding ? null : _seedDefaultHabits,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: const Color(0xFF15803D),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _seeding
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text(
                        'Add Starter Islamic Habits',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddHabitScreen()),
                );
              },
              child: const Text(
                'Or create a custom habit',
                style: TextStyle(color: Color(0xFF15803D)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
