import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'emotion_checkin_screen.dart';
import 'journaling_screen.dart';
import 'reminders_screen.dart';
import 'journal_history_screen.dart';
import 'saved_screen.dart';
import 'habits/habit_tracker_screen.dart';
import '../services/daily_wisdom_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String? photoBase64;
  String? photoUrl;
  String displayName = "Seeker";

  // Daily wisdom
  Map<String, dynamic>? _dailyWisdom;
  bool _wisdomLoading = true;

  // Recent journal + streak
  Map<String, dynamic>? _recentJournal;
  int _journalStreak = 0;

  String get _uid => FirebaseAuth.instance.currentUser!.uid;
  String get _todayStr {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadDailyWisdom();
    _loadRecentJournal();
    _calculateJournalStreak();
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        setState(() {
          photoBase64 = data['photoBase64'] as String?;
          photoUrl = data['photoUrl'] as String?;
          displayName =
              data['firstName'] ??
              user.displayName?.split(' ').first ??
              "Seeker";
        });
      } else {
        setState(() {
          displayName = user.displayName?.split(' ').first ?? "Seeker";
        });
      }
    } catch (e) {
      setState(() {
        displayName =
            FirebaseAuth.instance.currentUser?.displayName?.split(' ').first ??
            "Seeker";
      });
    }
  }

  Future<void> _loadDailyWisdom() async {
    final wisdom = await DailyWisdomService.getDailyWisdom();
    if (mounted) {
      setState(() {
        _dailyWisdom = wisdom;
        _wisdomLoading = false;
      });
    }
  }

  Future<void> _loadRecentJournal() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('journals')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();

      if (snap.docs.isNotEmpty && mounted) {
        setState(() {
          _recentJournal = snap.docs.first.data();
        });
      }
    } catch (_) {}
  }

  Future<void> _calculateJournalStreak() async {
    int streak = 0;
    final now = DateTime.now();

    for (int i = 0; i < 365; i++) {
      final dayStart = DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
      final dayEnd = dayStart.add(const Duration(days: 1));

      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('journals')
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(dayStart))
          .where('createdAt', isLessThan: Timestamp.fromDate(dayEnd))
          .limit(1)
          .get();

      if (snap.docs.isNotEmpty) {
        streak++;
      } else {
        if (i == 0) continue; // Skip today if not journaled yet
        break;
      }
    }

    if (mounted) setState(() => _journalStreak = streak);
  }

  String _formatDate(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate();
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  static const _moodEmojis = {
    'happy': '😊', 'sad': '😔', 'anxious': '😰', 'angry': '😠',
    'confused': '🤔', 'grateful': '🤲', 'lonely': '😞', 'stressed': '😫',
    'fearful': '😨', 'guilty': '😣', 'hopeless': '😶', 'overwhelmed': '🥺',
    'rejected': '💔', 'embarrassed': '😳', 'lost': '🌫️',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      // CustomScrollView lets the AppBar collapse smoothly as content passes
      // under it — greeting reads as content when at the top, becomes a compact
      // chrome bar when scrolled. Same pattern Apple Health / News / Instagram
      // use so the header never feels disconnected from the content.
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            elevation: 0,
            scrolledUnderElevation: 1,
            expandedHeight: 96,
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            automaticallyImplyLeading: false,
            titleSpacing: 16,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsetsDirectional.only(start: 16, bottom: 14, end: 140),
              expandedTitleScale: 1.25,
              title: RichText(
                maxLines: 2,
                text: TextSpan(
                  children: [
                    const TextSpan(
                      text: "Assalamu Alaikum, ",
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF6B7280),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    TextSpan(
                      text: displayName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF064E3B),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              // Saved (bookmarked advice)
              IconButton(
                tooltip: 'Saved advice',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SavedScreen()),
                  );
                },
                icon: const Icon(Icons.star_outline_rounded, color: Color(0xFF15803D)),
              ),
              // Bell icon for reminders
              IconButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RemindersScreen()),
                  );
                },
                icon: const Icon(Icons.notifications_outlined, color: Color(0xFF15803D)),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: const Color(0xFFDCFCE7),
                  backgroundImage: (photoBase64 != null && photoBase64!.isNotEmpty)
                      ? MemoryImage(base64Decode(photoBase64!))
                      : (photoUrl != null && photoUrl!.isNotEmpty)
                          ? NetworkImage(photoUrl!) as ImageProvider
                          : null,
                  child: (photoBase64 == null || photoBase64!.isEmpty) &&
                          (photoUrl == null || photoUrl!.isEmpty)
                      ? Text(
                          displayName.isNotEmpty
                              ? displayName[0].toUpperCase()
                              : 'S',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF15803D),
                            fontSize: 14,
                          ),
                        )
                      : null,
                ),
              ),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.all(20.0),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
              // ─── 1. Main Check-in CTA Card ───
              _buildCheckinCard(),
              const SizedBox(height: 20),

              // ─── 1b. Quick-mood tiles — one-tap reflection ───
              _buildQuickMoodRow(),
              const SizedBox(height: 24),

              // ─── 2. Daily Seerah Wisdom ───
              _buildSectionHeader('Daily Seerah Wisdom', null, null),
              const SizedBox(height: 12),
              _buildWisdomCard(),
              const SizedBox(height: 24),

              // ─── 3. Mood History (7-day) ───
              _buildSectionHeader('Mood History', 'Last 7 days', null),
              const SizedBox(height: 12),
              _buildMoodHistorySection(),
              const SizedBox(height: 24),

              // ─── 4. Today's Habits Summary ───
              _buildSectionHeader('Today\'s Habits', null, null),
              const SizedBox(height: 12),
              _buildHabitsSummarySection(),
              const SizedBox(height: 24),

              // ─── 5. Recent Journal + Streak ───
              _buildSectionHeader(
                'Recent Journal',
                _journalStreak > 0 ? '🔥 $_journalStreak day streak' : null,
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const JournalHistoryScreen()),
                  );
                },
              ),
              const SizedBox(height: 12),
              _buildRecentJournalCard(),
              const SizedBox(height: 40),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Check-in CTA Card ───
  Widget _buildCheckinCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF15803D), Color(0xFF14532D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF15803D).withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.favorite_rounded, color: Colors.white70, size: 32),
          const SizedBox(height: 16),
          const Text(
            "How is your heart feeling today?",
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "Check in to receive Seerah guidance.",
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const EmotionCheckinScreen()),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF15803D),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text("Start Check-in", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ─── Quick-mood tile row — tap a mood to jump straight into journaling pre-filled ───
  Widget _buildQuickMoodRow() {
    const quickMoods = [
      {'mood': 'grateful', 'emoji': '🤲', 'label': 'Grateful'},
      {'mood': 'sad', 'emoji': '😔', 'label': 'Sad'},
      {'mood': 'anxious', 'emoji': '😰', 'label': 'Anxious'},
      {'mood': 'angry', 'emoji': '😠', 'label': 'Angry'},
      {'mood': 'lonely', 'emoji': '🥺', 'label': 'Lonely'},
      {'mood': 'lost', 'emoji': '🧭', 'label': 'Lost'},
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            'Quick reflection',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6B7280),
              letterSpacing: 0.3,
            ),
          ),
        ),
        SizedBox(
          height: 86,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: quickMoods.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final m = quickMoods[i];
              return InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => JournalingScreen(mood: m['mood']!),
                    ),
                  );
                },
                child: Container(
                  width: 74,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(m['emoji']!, style: const TextStyle(fontSize: 24)),
                      const SizedBox(height: 6),
                      Text(
                        m['label']!,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF374151),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ─── Section Header ───
  Widget _buildSectionHeader(String title, String? trailing, VoidCallback? onViewAll) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1F2937)),
        ),
        const Spacer(),
        if (trailing != null && onViewAll == null)
          Text(trailing, style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
        if (onViewAll != null)
          GestureDetector(
            onTap: onViewAll,
            child: Row(
              children: [
                if (trailing != null) ...[
                  Text(trailing, style: const TextStyle(fontSize: 12, color: Color(0xFFEA580C))),
                  const SizedBox(width: 8),
                ],
                const Text('View All', style: TextStyle(fontSize: 13, color: Color(0xFF15803D), fontWeight: FontWeight.w600)),
                const SizedBox(width: 2),
                const Icon(Icons.arrow_forward_ios, size: 12, color: Color(0xFF15803D)),
              ],
            ),
          ),
      ],
    );
  }

  // ─── Daily Wisdom Card ───
  Widget _buildWisdomCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: _wisdomLoading
          ? const SizedBox(
              height: 80,
              child: Center(child: CircularProgressIndicator(color: Color(0xFF15803D), strokeWidth: 2)),
            )
          : Column(
              children: [
                const Icon(Icons.mosque_rounded, color: Color(0xFF15803D), size: 30),
                const SizedBox(height: 8),
                Text(
                  _dailyWisdom?['lesson'] ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    fontStyle: FontStyle.italic,
                    color: Color(0xFF374151),
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _dailyWisdom?['story_title'] ?? '',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade500,
                  ),
                ),
                if ((_dailyWisdom?['story_period'] ?? '').toString().isNotEmpty)
                  Text(
                    _dailyWisdom!['story_period'],
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                  ),
              ],
            ),
    );
  }

  // ─── Mood History (7-Day) ───
  Widget _buildMoodHistorySection() {
    final now = DateTime.now();
    final sevenDaysAgo = Timestamp.fromDate(
      DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6)),
    );

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('journals')
          .where('createdAt', isGreaterThanOrEqualTo: sevenDaysAgo)
          .snapshots(),
      builder: (context, snapshot) {
        // Build a map: dateString → mood (first entry per day)
        final moodByDay = <String, String>{};
        if (snapshot.hasData) {
          for (final doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final ts = data['createdAt'] as Timestamp?;
            if (ts != null) {
              final dt = ts.toDate();
              final key = '${dt.year}-${dt.month}-${dt.day}';
              if (!moodByDay.containsKey(key)) {
                moodByDay[key] = (data['mood'] ?? '').toString().toLowerCase();
              }
            }
          }
        }

        const dayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

        // Weekly insight: most-common mood across the logged days
        String? topMood;
        if (moodByDay.isNotEmpty) {
          final counts = <String, int>{};
          for (final m in moodByDay.values) {
            if (m.isEmpty) continue;
            counts[m] = (counts[m] ?? 0) + 1;
          }
          if (counts.isNotEmpty) {
            topMood = counts.entries
                .reduce((a, b) => a.value >= b.value ? a : b)
                .key;
          }
        }

        return Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            children: [
              if (topMood != null && moodByDay.length >= 2) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 12, left: 4),
                  child: Row(
                    children: [
                      Text(
                        _moodEmojis[topMood] ?? '🌱',
                        style: const TextStyle(fontSize: 18),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF374151),
                            ),
                            children: [
                              const TextSpan(text: 'This week, you mostly felt '),
                              TextSpan(
                                text: topMood,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF15803D),
                                ),
                              ),
                              const TextSpan(text: '.'),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFF3F4F6)),
                const SizedBox(height: 12),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(7, (i) {
              final date = now.subtract(Duration(days: 6 - i));
              final key = '${date.year}-${date.month}-${date.day}';
              final mood = moodByDay[key];
              final isToday = i == 6;
              final emoji = mood != null ? _moodEmojis[mood] : null;

              return Column(
                children: [
                  Text(
                    dayLetters[date.weekday - 1],
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                      color: isToday ? const Color(0xFF15803D) : const Color(0xFF9CA3AF),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: emoji != null
                          ? const Color(0xFFDCFCE7)
                          : const Color(0xFFF3F4F6),
                      border: isToday
                          ? Border.all(color: const Color(0xFF15803D), width: 2)
                          : null,
                    ),
                    child: Center(
                      child: emoji != null
                          ? Text(emoji, style: const TextStyle(fontSize: 18))
                          : Icon(Icons.remove, size: 14, color: Colors.grey.shade300),
                    ),
                  ),
                ],
              );
            }),
          ),
            ],
          ),
        );
      },
    );
  }

  // ─── Today's Habits Summary ───
  Widget _buildHabitsSummarySection() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('habits')
          .where('isActive', isEqualTo: true)
          .snapshots(),
      builder: (context, habitsSnap) {
        final total = habitsSnap.data?.docs.length ?? 0;

        if (total == 0) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.task_alt_rounded, color: Color(0xFF15803D), size: 22),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Text(
                    'No habits yet. Start building your daily Islamic habits!',
                    style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                  ),
                ),
              ],
            ),
          );
        }

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(_uid)
              .collection('habitLogs')
              .where('date', isEqualTo: _todayStr)
              .snapshots(),
          builder: (context, logsSnap) {
            final completed = logsSnap.data?.docs
                .where((d) => (d.data() as Map<String, dynamic>)['completed'] == true)
                .length ?? 0;

            final progress = total > 0 ? completed / total : 0.0;
            final allDone = completed >= total;

            return GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const HabitTrackerScreen()),
                );
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: allDone ? const Color(0xFFDCFCE7) : const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            allDone ? Icons.check_circle_rounded : Icons.task_alt_rounded,
                            color: const Color(0xFF15803D),
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$completed / $total completed',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1F2937),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                allDone
                                    ? 'MashaAllah! All done today!'
                                    : '${total - completed} remaining',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: allDone ? const Color(0xFF15803D) : const Color(0xFF9CA3AF),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios, size: 14, color: Color(0xFF9CA3AF)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: const Color(0xFFF3F4F6),
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF15803D)),
                        minHeight: 8,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ─── Recent Journal Card ───
  Widget _buildRecentJournalCard() {
    if (_recentJournal == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: const Column(
          children: [
            Icon(Icons.edit_note_rounded, size: 36, color: Color(0xFFD1D5DB)),
            SizedBox(height: 8),
            Text(
              'No journal entries yet. Start writing to receive Seerah guidance.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
            ),
          ],
        ),
      );
    }

    final text = _recentJournal!['text'] ?? '';
    final mood = _recentJournal!['mood'] ?? '';
    final ts = _recentJournal!['createdAt'] as Timestamp?;
    final preview = text.length > 120 ? '${text.substring(0, 120)}...' : text;
    final moodLabel = mood.isNotEmpty ? mood[0].toUpperCase() + mood.substring(1) : '';

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const JournalHistoryScreen()),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    moodLabel,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF15803D)),
                  ),
                ),
                const Spacer(),
                Text(
                  _formatDate(ts),
                  style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              preview,
              style: const TextStyle(fontSize: 14, color: Color(0xFF374151), height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
