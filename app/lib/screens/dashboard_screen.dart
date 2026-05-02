import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'emotion_checkin_screen.dart';
import 'journaling_screen.dart';
import 'reminders_screen.dart';
import 'journal_history_screen.dart';
import 'saved_screen.dart';
import 'habits/habit_tracker_screen.dart';
import '../services/daily_wisdom_service.dart';
import '../widgets/hero_greeting_card.dart';

class DashboardScreen extends StatefulWidget {
  /// Switches the bottom-nav `IndexedStack` index in the parent. Used by the
  /// header's profile avatar so tapping it lands on the Profile tab without
  /// rebuilding the other tabs (preserves their state).
  final ValueChanged<int>? onNavigateToTab;

  /// Opens the global navigation drawer owned by HomeMain. Called via a
  /// callback because Scaffold.of(context) inside this screen would resolve
  /// to the local Scaffold (which has no drawer), not HomeMain's outer one.
  final VoidCallback? onOpenDrawer;

  const DashboardScreen({
    super.key,
    this.onNavigateToTab,
    this.onOpenDrawer,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String? photoBase64;
  String? photoUrl;
  String displayName = "Seeker";

  Map<String, dynamic>? _dailyWisdom;
  bool _wisdomLoading = true;

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
        if (!mounted) return;
        setState(() {
          photoBase64 = data['photoBase64'] as String?;
          photoUrl = data['photoUrl'] as String?;
          displayName = data['firstName'] ??
              user.displayName?.split(' ').first ??
              "Seeker";
        });
      } else {
        if (!mounted) return;
        setState(() {
          displayName = user.displayName?.split(' ').first ?? "Seeker";
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        displayName = user.displayName?.split(' ').first ?? "Seeker";
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
      final dayStart =
          DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
      final dayEnd = dayStart.add(const Duration(days: 1));

      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('journals')
          .where('createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(dayStart))
          .where('createdAt', isLessThan: Timestamp.fromDate(dayEnd))
          .limit(1)
          .get();

      if (snap.docs.isNotEmpty) {
        streak++;
      } else {
        if (i == 0) continue;
        break;
      }
    }

    if (mounted) setState(() => _journalStreak = streak);
  }

  String _formatDate(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  static const _moodEmojis = {
    'happy': '😊', 'sad': '😔', 'anxious': '😰', 'angry': '😠',
    'confused': '🤔', 'grateful': '🤲', 'lonely': '😞', 'stressed': '😫',
    'fearful': '😨', 'guilty': '😣', 'hopeless': '😶', 'overwhelmed': '🥺',
    'rejected': '💔', 'embarrassed': '😳', 'lost': '🌫️',
  };

  ImageProvider? get _avatarImage {
    if (photoBase64 != null && photoBase64!.isNotEmpty) {
      return MemoryImage(base64Decode(photoBase64!));
    }
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return NetworkImage(photoUrl!);
    }
    return null;
  }

  void _openProfile() {
    if (widget.onNavigateToTab != null) {
      widget.onNavigateToTab!(4);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: CustomScrollView(
        slivers: [
          _buildAppBar(),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                HeroGreetingCard(
                  name: displayName,
                  onCheckin: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const EmotionCheckinScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                _buildStatsRow(),
                const SizedBox(height: 24),
                _buildQuickMoodRow(),
                const SizedBox(height: 24),
                _buildSectionHeader('Daily Seerah Wisdom', null, null),
                const SizedBox(height: 12),
                _buildWisdomCard(),
                const SizedBox(height: 24),
                _buildSectionHeader('Mood History', 'Last 7 days', null),
                const SizedBox(height: 12),
                _buildMoodHistorySection(),
                const SizedBox(height: 24),
                _buildSectionHeader(
                  'Recent Journal',
                  _journalStreak > 0 ? '🔥 $_journalStreak day streak' : null,
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const JournalHistoryScreen(),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _buildRecentJournalCard(),
                const SizedBox(height: 24),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Top app bar (hamburger + Sakinah title + actions) ───
  Widget _buildAppBar() {
    return SliverAppBar(
      pinned: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: const Color(0xFFFAFAFA),
      surfaceTintColor: const Color(0xFFFAFAFA),
      automaticallyImplyLeading: false,
      titleSpacing: 4,
      toolbarHeight: 64,
      leading: IconButton(
        tooltip: 'Menu',
        onPressed: widget.onOpenDrawer,
        icon: const Icon(Icons.menu_rounded, color: Color(0xFF064E3B), size: 28),
      ),
      title: const Text(
        'Sakinah',
        style: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.bold,
          fontStyle: FontStyle.italic,
          color: Color(0xFF064E3B),
          letterSpacing: 0.3,
        ),
      ),
      actions: [
        IconButton(
          tooltip: 'Saved advice',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SavedScreen()),
          ),
          icon: const Icon(Icons.star_outline_rounded,
              color: Color(0xFF15803D)),
        ),
        IconButton(
          tooltip: 'Reminders',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const RemindersScreen()),
          ),
          icon: const Icon(Icons.notifications_outlined,
              color: Color(0xFF15803D)),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 14, left: 4),
          child: GestureDetector(
            onTap: _openProfile,
            behavior: HitTestBehavior.opaque,
            child: CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFFDCFCE7),
              backgroundImage: _avatarImage,
              child: _avatarImage == null
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
        ),
      ],
    );
  }

  // ─── Stat tile pair (Streak + Habits) ───
  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(child: _buildStreakTile()),
        const SizedBox(width: 14),
        Expanded(child: _buildHabitsTile()),
      ],
    );
  }

  Widget _buildStreakTile() {
    return _animatedTile(
      delayMs: 80,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
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
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text('🔥', style: TextStyle(fontSize: 16)),
                ),
                const Spacer(),
                const Text(
                  'streak',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.3,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$_journalStreak',
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1F2937),
                    height: 1,
                  ),
                ),
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    _journalStreak == 1 ? 'day' : 'days',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _journalStreak == 0
                  ? 'Begin your reflection.'
                  : 'Keep going, MashaAllah.',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF6B7280),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHabitsTile() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('habits')
          .where('isActive', isEqualTo: true)
          .snapshots(),
      builder: (context, habitsSnap) {
        final total = habitsSnap.data?.docs.length ?? 0;

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(_uid)
              .collection('habitLogs')
              .where('date', isEqualTo: _todayStr)
              .snapshots(),
          builder: (context, logsSnap) {
            final completed = logsSnap.data?.docs
                    .where((d) =>
                        (d.data() as Map<String, dynamic>)['completed'] ==
                        true)
                    .length ??
                0;
            final progress = total > 0 ? completed / total : 0.0;
            final allDone = total > 0 && completed >= total;

            return _animatedTile(
              delayMs: 160,
              child: GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const HabitTrackerScreen(),
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
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
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDCFCE7),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              allDone
                                  ? Icons.check_circle_rounded
                                  : Icons.task_alt_rounded,
                              color: const Color(0xFF15803D),
                              size: 16,
                            ),
                          ),
                          const Spacer(),
                          const Text(
                            'habits',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.3,
                              color: Color(0xFF9CA3AF),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '$completed',
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1F2937),
                              height: 1,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              ' / $total',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: progress,
                          backgroundColor: const Color(0xFFF3F4F6),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                              Color(0xFF15803D)),
                          minHeight: 6,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _animatedTile({required Widget child, required int delayMs}) {
    return child
        .animate(delay: delayMs.ms)
        .fadeIn(duration: 500.ms, curve: Curves.easeOutCubic)
        .slideY(
          begin: 0.05,
          end: 0,
          duration: 500.ms,
          curve: Curves.easeOutCubic,
        );
  }

  // ─── Quick Mood Row ───
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
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => JournalingScreen(mood: m['mood']!),
                  ),
                ),
                child: Container(
                  width: 74,
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
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
              )
                  .animate(delay: (240 + i * 50).ms)
                  .fadeIn(duration: 360.ms, curve: Curves.easeOutCubic)
                  .slideX(
                    begin: 0.1,
                    end: 0,
                    duration: 360.ms,
                    curve: Curves.easeOutCubic,
                  );
            },
          ),
        ),
      ],
    );
  }

  // ─── Section Header ───
  Widget _buildSectionHeader(
      String title, String? trailing, VoidCallback? onViewAll) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1F2937),
          ),
        ),
        const Spacer(),
        if (trailing != null && onViewAll == null)
          Text(
            trailing,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF9CA3AF),
            ),
          ),
        if (onViewAll != null)
          GestureDetector(
            onTap: onViewAll,
            child: Row(
              children: [
                if (trailing != null) ...[
                  Text(
                    trailing,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFFEA580C),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                const Text(
                  'View All',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF15803D),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(Icons.arrow_forward_ios,
                    size: 12, color: Color(0xFF15803D)),
              ],
            ),
          ),
      ],
    );
  }

  // ─── Daily Wisdom Card ───
  Widget _buildWisdomCard() {
    return _animatedTile(
      delayMs: 320,
      child: Container(
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
                child: Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFF15803D),
                    strokeWidth: 2,
                  ),
                ),
              )
            : Column(
                children: [
                  const Icon(Icons.mosque_rounded,
                      color: Color(0xFF15803D), size: 30),
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
                    (_dailyWisdom?['story_title'] ?? '').toString(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade500,
                    ),
                  ),
                  if ((_dailyWisdom?['story_period'] ?? '')
                      .toString()
                      .isNotEmpty)
                    Text(
                      _dailyWisdom!['story_period'],
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade400,
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  // ─── 7-Day Mood History ───
  Widget _buildMoodHistorySection() {
    final now = DateTime.now();
    final sevenDaysAgo = Timestamp.fromDate(
      DateTime(now.year, now.month, now.day)
          .subtract(const Duration(days: 6)),
    );

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('journals')
          .where('createdAt', isGreaterThanOrEqualTo: sevenDaysAgo)
          .snapshots(),
      builder: (context, snapshot) {
        final moodByDay = <String, String>{};
        if (snapshot.hasData) {
          for (final doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final ts = data['createdAt'] as Timestamp?;
            if (ts != null) {
              final dt = ts.toDate();
              final key = '${dt.year}-${dt.month}-${dt.day}';
              if (!moodByDay.containsKey(key)) {
                moodByDay[key] =
                    (data['mood'] ?? '').toString().toLowerCase();
              }
            }
          }
        }

        const dayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

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

        return _animatedTile(
          delayMs: 400,
          child: Container(
            padding:
                const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
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
                        Text(_moodEmojis[topMood] ?? '🌱',
                            style: const TextStyle(fontSize: 18)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF374151),
                              ),
                              children: [
                                const TextSpan(
                                    text: 'This week, you mostly felt '),
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
                            fontWeight: isToday
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isToday
                                ? const Color(0xFF15803D)
                                : const Color(0xFF9CA3AF),
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
                                ? Border.all(
                                    color: const Color(0xFF15803D),
                                    width: 2)
                                : null,
                          ),
                          child: Center(
                            child: emoji != null
                                ? Text(emoji,
                                    style: const TextStyle(fontSize: 18))
                                : Icon(Icons.remove,
                                    size: 14,
                                    color: Colors.grey.shade300),
                          ),
                        ),
                      ],
                    );
                  }),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─── Recent Journal Card ───
  Widget _buildRecentJournalCard() {
    if (_recentJournal == null) {
      return _animatedTile(
        delayMs: 480,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: const Column(
            children: [
              Icon(Icons.edit_note_rounded,
                  size: 36, color: Color(0xFFD1D5DB)),
              SizedBox(height: 8),
              Text(
                'No journal entries yet. Start writing to receive Seerah guidance.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
              ),
            ],
          ),
        ),
      );
    }

    final text = _recentJournal!['text'] ?? '';
    final mood = _recentJournal!['mood'] ?? '';
    final ts = _recentJournal!['createdAt'] as Timestamp?;
    final preview = text.length > 120 ? '${text.substring(0, 120)}...' : text;
    final moodLabel =
        mood.isNotEmpty ? mood[0].toUpperCase() + mood.substring(1) : '';

    return _animatedTile(
      delayMs: 480,
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const JournalHistoryScreen(),
          ),
        ),
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
                  if (moodLabel.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDCFCE7),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        moodLabel,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF15803D),
                        ),
                      ),
                    ),
                  const Spacer(),
                  Text(
                    _formatDate(ts),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                preview,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF374151),
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
