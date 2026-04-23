import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../widgets/progress_ring.dart';
import '../../widgets/habit_card.dart';
import '../journaling_screen.dart';
import 'add_habit_screen.dart';
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

String dateStr(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class HabitTrackerScreen extends StatefulWidget {
  const HabitTrackerScreen({super.key});

  @override
  State<HabitTrackerScreen> createState() => _HabitTrackerScreenState();
}

class _HabitTrackerScreenState extends State<HabitTrackerScreen> {
  String _selectedCategory = 'All';
  bool _seeding = false;

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
  Future<void> _markFeedback(String habitId, String status) async {
    final uid = _uidOrNull;
    if (uid == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('habits')
          .doc(habitId)
          .update({
        'feedbackStatus': status,
        'feedbackAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(status == 'success'
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
    await _markFeedback(habitId, 'struggled');

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

  // ───── Get Weekly Status for a Habit ─────
  Future<List<bool>> _getWeeklyStatus(String habitId) async {
    final now = DateTime.now();
    final results = <bool>[];

    for (int i = 6; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      final logId = '${dateStr(date)}_$habitId';
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('habitLogs')
          .doc(logId)
          .get();
      results.add(doc.exists && (doc.data()?['completed'] == true));
    }
    return results;
  }

  // ───── Calculate Streak ─────
  Future<int> _calculateStreak(String habitId) async {
    int streak = 0;
    final now = DateTime.now();

    for (int i = 0; i < 365; i++) {
      final date = now.subtract(Duration(days: i));
      final logId = '${dateStr(date)}_$habitId';
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('habitLogs')
          .doc(logId)
          .get();

      if (doc.exists && (doc.data()?['completed'] == true)) {
        streak++;
      } else {
        // If today is not done yet, skip it and keep counting from yesterday
        if (i == 0) continue;
        break;
      }
    }
    return streak;
  }

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
        centerTitle: true,
        automaticallyImplyLeading: false,
        actions: uid == null
            ? null
            : [
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, color: Color(0xFF6B7280)),
                  onSelected: (value) {
                    if (value == 'cleanup') _cleanUpDuplicates();
                  },
                  itemBuilder: (_) => const [
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

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(uid)
                .collection('habitLogs')
                .where('date', isEqualTo: _todayStr)
                .snapshots(),
            builder: (context, logsSnap) {
              // Log failures degrade gracefully — habits still render, just with no
              // "completed today" state. Far better than blocking the entire screen.
              final todayLogs = <String>{};
              if (logsSnap.hasData) {
                for (final doc in logsSnap.data!.docs) {
                  final data = doc.data() as Map<String, dynamic>;
                  if (data['completed'] == true) {
                    todayLogs.add(data['habitId'] as String);
                  }
                }
              }

              final completedCount = habits.where((h) => todayLogs.contains(h.id)).length;

              // Sort: incomplete first, then completed
              final sortedFiltered = List<QueryDocumentSnapshot>.from(filtered);
              sortedFiltered.sort((a, b) {
                final aDone = todayLogs.contains(a.id) ? 1 : 0;
                final bDone = todayLogs.contains(b.id) ? 1 : 0;
                return aDone.compareTo(bDone);
              });

              return SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    // Progress Ring
                    ProgressRing(completed: completedCount, total: habits.length),
                    const SizedBox(height: 8),
                    Text(
                      completedCount == habits.length
                          ? 'MashaAllah! All done today!'
                          : 'Keep going, you\'re doing great!',
                      style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                    ),
                    const SizedBox(height: 20),

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

                    // Habit cards
                    ...sortedFiltered.map((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final habitId = doc.id;
                      final isDone = todayLogs.contains(habitId);

                      return FutureBuilder<List<dynamic>>(
                        future: Future.wait([
                          _getWeeklyStatus(habitId),
                          _calculateStreak(habitId),
                        ]),
                        builder: (context, snap) {
                          final weekly = (snap.data?[0] as List<bool>?) ?? List.filled(7, false);
                          final streak = (snap.data?[1] as int?) ?? 0;

                          // Show the feedback strip if this habit came from a guidance
                          // recommendation, is at least 3 days old, and hasn't been rated yet.
                          final hasSource = (data['sourceAdvice']?.toString().isNotEmpty ?? false);
                          final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
                          final ageDays = createdAt == null
                              ? 0
                              : DateTime.now().difference(createdAt).inDays;
                          final unrated = data['feedbackStatus'] == null;
                          final showFeedback = hasSource && ageDays >= 3 && unrated;

                          return HabitCard(
                            title: data['title'] ?? '',
                            category: data['category'] ?? 'custom',
                            icon: getHabitIcon(data['icon'] ?? ''),
                            color: getHabitColor(data['color'] ?? '#15803D'),
                            streak: streak,
                            completedToday: isDone,
                            weeklyStatus: weekly,
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
                            onFeedbackSuccess: () => _markFeedback(habitId, 'success'),
                            onFeedbackStruggled: () => _handleStruggled(habitId, data),
                          );
                        },
                      );
                    }),

                    if (sortedFiltered.isEmpty && _selectedCategory != 'All')
                      Padding(
                        padding: const EdgeInsets.only(top: 40),
                        child: Column(
                          children: [
                            Icon(Icons.filter_list_off, size: 48, color: Colors.grey.shade300),
                            const SizedBox(height: 12),
                            Text(
                              'No $_selectedCategory habits yet',
                              style: const TextStyle(color: Color(0xFF9CA3AF)),
                            ),
                          ],
                        ),
                      ),

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
