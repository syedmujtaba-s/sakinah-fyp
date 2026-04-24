import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../services/notification_service.dart';
import 'habit_tracker_screen.dart' show getHabitIcon, getHabitColor, dateStr;
import 'add_habit_screen.dart';

class HabitDetailScreen extends StatefulWidget {
  final String habitId;
  final Map<String, dynamic> habitData;

  const HabitDetailScreen({
    super.key,
    required this.habitId,
    required this.habitData,
  });

  @override
  State<HabitDetailScreen> createState() => _HabitDetailScreenState();
}

class _HabitDetailScreenState extends State<HabitDetailScreen> {
  String? get _uidOrNull => FirebaseAuth.instance.currentUser?.uid;
  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  int _currentStreak = 0;
  int _bestStreak = 0;
  double _completionRate = 0;
  List<bool> _last30Days = List.filled(30, false);
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final uid = _uidOrNull;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final now = DateTime.now();
    final cutoff = dateStr(now.subtract(const Duration(days: 89)));

    try {
      // Single batched query: all habitLogs for this habit in the last 90 days.
      // Replaces the previous 90-round-trip loop that stalled on slow networks.
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('habitLogs')
          .where('habitId', isEqualTo: widget.habitId)
          .where('date', isGreaterThanOrEqualTo: cutoff)
          .get();

      final doneDates = <String>{};
      for (final d in snap.docs) {
        final data = d.data();
        if (data['completed'] != true) continue;
        final date = data['date']?.toString();
        if (date != null && date.isNotEmpty) doneDates.add(date);
      }

      // Last 30 days (index 0 = 29 days ago, index 29 = today)
      final last30 = <bool>[];
      for (int i = 29; i >= 0; i--) {
        final date = now.subtract(Duration(days: i));
        last30.add(doneDates.contains(dateStr(date)));
      }

      // Current streak
      int currentStreak = 0;
      for (int i = 0; i < 90; i++) {
        final date = now.subtract(Duration(days: i));
        if (doneDates.contains(dateStr(date))) {
          currentStreak++;
        } else {
          if (i == 0) continue;
          break;
        }
      }

      // Best streak
      int bestStreak = 0;
      int tempStreak = 0;
      for (int i = 89; i >= 0; i--) {
        final date = now.subtract(Duration(days: i));
        if (doneDates.contains(dateStr(date))) {
          tempStreak++;
          if (tempStreak > bestStreak) bestStreak = tempStreak;
        } else {
          tempStreak = 0;
        }
      }

      final completedDays = last30.where((b) => b).length;
      final rate = completedDays / 30 * 100;

      if (!mounted) return;
      setState(() {
        _currentStreak = currentStreak;
        _bestStreak = bestStreak;
        _completionRate = rate;
        _last30Days = last30;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _deleteHabit() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Archive Habit'),
        content: Text(
          'Archive "${widget.habitData['title']}"? It will be hidden from your list but you can restore it from the Archived screen. Your history is kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Archive', style: TextStyle(color: Color(0xFFDC2626))),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // Soft-delete: list stream already filters by isActive=true, so the habit
      // disappears from the tracker but the doc + its habitLogs remain intact.
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('habits')
          .doc(widget.habitId)
          .update({
        'isActive': false,
        'archivedAt': FieldValue.serverTimestamp(),
      });
      // Stop the daily reminder so archived habits don't still ping the user.
      await NotificationService.instance.cancelHabitReminder(widget.habitId);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = getHabitColor(widget.habitData['color'] ?? '#15803D');
    final icon = getHabitIcon(widget.habitData['icon'] ?? '');
    final title = widget.habitData['title'] ?? 'Habit';
    final category = widget.habitData['category'] ?? 'custom';

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        title: Text(title, style: const TextStyle(color: Color(0xFF15803D), fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        surfaceTintColor: Colors.white,
        iconTheme: const IconThemeData(color: Color(0xFF15803D)),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_rounded),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AddHabitScreen(
                    habitId: widget.habitId,
                    habitData: widget.habitData,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF15803D)))
          : _loadError != null
              ? _buildErrorState()
              : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(icon, color: color, size: 28),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1F2937))),
                              const SizedBox(height: 4),
                              Text(
                                category[0].toUpperCase() + category.substring(1),
                                style: const TextStyle(fontSize: 13, color: Color(0xFF9CA3AF)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Stats row
                  Row(
                    children: [
                      _buildStatCard('Current\nStreak', '$_currentStreak', Icons.local_fire_department_rounded, const Color(0xFFEA580C)),
                      const SizedBox(width: 12),
                      _buildStatCard('Best\nStreak', '$_bestStreak', Icons.emoji_events_rounded, const Color(0xFFD97706)),
                      const SizedBox(width: 12),
                      _buildStatCard('Completion\nRate', '${_completionRate.toStringAsFixed(0)}%', Icons.pie_chart_rounded, const Color(0xFF15803D)),
                    ],
                  ),
                  const SizedBox(height: 28),

                  // 30-Day Chart
                  const Text(
                    'Last 30 Days',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1F2937)),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    height: 180,
                    padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        maxY: 1.2,
                        barTouchData: BarTouchData(
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipItem: (group, groupIndex, rod, rodIndex) {
                              final date = DateTime.now().subtract(Duration(days: 29 - group.x.toInt()));
                              final done = _last30Days[group.x.toInt()];
                              return BarTooltipItem(
                                '${date.day}/${date.month}\n${done ? "Done" : "Missed"}',
                                TextStyle(color: done ? Colors.white : Colors.grey.shade300, fontSize: 11),
                              );
                            },
                          ),
                        ),
                        titlesData: FlTitlesData(
                          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              getTitlesWidget: (value, meta) {
                                final idx = value.toInt();
                                if (idx % 7 == 0 || idx == 29) {
                                  final date = DateTime.now().subtract(Duration(days: 29 - idx));
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      '${date.day}/${date.month}',
                                      style: const TextStyle(fontSize: 9, color: Color(0xFF9CA3AF)),
                                    ),
                                  );
                                }
                                return const SizedBox.shrink();
                              },
                            ),
                          ),
                        ),
                        gridData: const FlGridData(show: false),
                        borderData: FlBorderData(show: false),
                        barGroups: List.generate(30, (i) {
                          return BarChartGroupData(
                            x: i,
                            barRods: [
                              BarChartRodData(
                                toY: _last30Days[i] ? 1.0 : 0.15,
                                color: _last30Days[i] ? color : const Color(0xFFE5E7EB),
                                width: 6,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ],
                          );
                        }),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Monthly calendar grid
                  const Text(
                    'This Month',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1F2937)),
                  ),
                  const SizedBox(height: 16),
                  _buildMonthlyCalendar(color),
                  const SizedBox(height: 32),

                  // Delete button
                  Center(
                    child: TextButton.icon(
                      onPressed: _deleteHabit,
                      icon: const Icon(Icons.archive_outlined, color: Colors.red, size: 20),
                      label: const Text('Archive Habit', style: TextStyle(color: Colors.red)),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10, color: Color(0xFF9CA3AF), height: 1.3),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthlyCalendar(Color habitColor) {
    final now = DateTime.now();
    final firstDayOfMonth = DateTime(now.year, now.month, 1);
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final startWeekday = firstDayOfMonth.weekday; // 1=Mon

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          // Day headers
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
                .map((d) => SizedBox(
                      width: 32,
                      child: Center(
                        child: Text(d, style: const TextStyle(fontSize: 10, color: Color(0xFF9CA3AF), fontWeight: FontWeight.w600)),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 8),

          // Day grid
          ...List.generate(6, (week) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(7, (weekday) {
                  final dayNum = week * 7 + weekday + 1 - (startWeekday - 1);
                  if (dayNum < 1 || dayNum > daysInMonth) {
                    return const SizedBox(width: 32, height: 32);
                  }

                  final isToday = dayNum == now.day;
                  final isFuture = dayNum > now.day;
                  // Check if this day is in our last 30 days data
                  final daysAgo = now.day - dayNum;
                  final completed = daysAgo >= 0 && daysAgo < 30 && _last30Days[29 - daysAgo];

                  return Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: completed
                          ? habitColor
                          : isToday
                              ? const Color(0xFFF3F4F6)
                              : Colors.transparent,
                      shape: BoxShape.circle,
                      border: isToday && !completed
                          ? Border.all(color: habitColor, width: 2)
                          : null,
                    ),
                    child: Center(
                      child: Text(
                        '$dayNum',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                          color: completed
                              ? Colors.white
                              : isFuture
                                  ? const Color(0xFFD1D5DB)
                                  : const Color(0xFF374151),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
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
              child: const Icon(Icons.cloud_off_rounded,
                  size: 48, color: Color(0xFFDC2626)),
            ),
            const SizedBox(height: 24),
            const Text(
              'Could not load stats',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF064E3B),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _loadError ?? 'Unknown error',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF6B7280),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _loading = true;
                  _loadError = null;
                });
                _loadStats();
              },
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
}
