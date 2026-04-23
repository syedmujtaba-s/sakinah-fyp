import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class GuidanceScreen extends StatefulWidget {
  final String mood;
  final Map<String, dynamic> guidanceData;

  const GuidanceScreen({
    super.key,
    required this.mood,
    required this.guidanceData,
  });

  @override
  State<GuidanceScreen> createState() => _GuidanceScreenState();
}

class _GuidanceScreenState extends State<GuidanceScreen> {
  final Set<String> _trackedAdvice = {};
  final Set<String> _tracking = {};

  String _slug(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');

  Future<void> _trackAdvice(String advice) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to track this advice as a habit.')),
      );
      return;
    }
    if (_tracking.contains(advice) || _trackedAdvice.contains(advice)) return;

    setState(() => _tracking.add(advice));

    final storyTitle = widget.guidanceData['story_title']?.toString() ?? '';
    final storyId = widget.guidanceData['story_id']?.toString() ?? '';
    final emotion = widget.mood;

    // Deterministic ID: story + first chars of advice slug, so re-tapping the
    // same bullet in the same session is idempotent.
    final adviceSlug = _slug(advice);
    final shortSlug = adviceSlug.length > 40 ? adviceSlug.substring(0, 40) : adviceSlug;
    final docId = 'advice_${_slug(storyTitle)}_$shortSlug';

    // Habit title: first ~40 chars of the advice, trailing ellipsis if cut.
    final habitTitle = advice.length > 45 ? '${advice.substring(0, 42).trim()}…' : advice;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('habits')
          .doc(docId)
          .set({
        'title': habitTitle,
        'category': 'guidance',
        'icon': 'lightbulb',
        'color': '#15803D',
        'frequency': 'daily',
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
        'sourceAdvice': advice,
        'sourceStoryId': storyId,
        'sourceStoryTitle': storyTitle,
        'sourceEmotion': emotion,
        'feedbackStatus': null,
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() {
        _tracking.remove(advice);
        _trackedAdvice.add(advice);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Added to your Habits — check the Habits tab.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _tracking.remove(advice));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not add habit: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final guidanceData = widget.guidanceData;
    final mood = widget.mood;
    final title = guidanceData['story_title'] ?? 'Guidance';
    final period = guidanceData['story_period'] ?? '';
    final seerahConnection = guidanceData['seerah_connection'] ?? '';
    final lessons = List<String>.from(guidanceData['lessons'] ?? []);
    final practicalAdvice = List<String>.from(guidanceData['practical_advice'] ?? []);
    final dua = guidanceData['dua'] ?? '';

    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          // Header
          SliverAppBar(
            expandedHeight: 200.0,
            floating: false,
            pinned: true,
            backgroundColor: const Color(0xFF15803D),
            flexibleSpace: FlexibleSpaceBar(
              title: Text(title, style: const TextStyle(fontSize: 16)),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF15803D), Color(0xFF14532D)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Center(
                  child: Icon(Icons.mosque_rounded, size: 80, color: Colors.white.withOpacity(0.2)),
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Mood + Period Tags
                  Wrap(
                    spacing: 8,
                    children: [
                      _buildTag("Feeling $mood", const Color(0xFFDCFCE7), const Color(0xFF15803D)),
                      if (period.isNotEmpty)
                        _buildTag(period, const Color(0xFFFEF3C7), const Color(0xFF92400E)),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Seerah Connection
                  const Text(
                    "The Seerah Connection",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    seerahConnection,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Color(0xFF4B5563),
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Lessons
                  if (lessons.isNotEmpty) ...[
                    _buildSectionCard(
                      icon: Icons.lightbulb_outline,
                      title: "Lessons",
                      items: lessons,
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Practical Advice — each bullet is trackable as a habit
                  if (practicalAdvice.isNotEmpty) ...[
                    _buildTrackableAdviceCard(practicalAdvice),
                    const SizedBox(height: 24),
                  ],

                  // Dua Card
                  if (dua.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFF15803D).withOpacity(0.3)),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF15803D).withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          const Text(
                            "Recommended Dua",
                            style: TextStyle(
                              fontSize: 14,
                              color: Color(0xFF6B7280),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            dua,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              fontStyle: FontStyle.italic,
                              color: Color(0xFF1F2937),
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 40),
                  Center(
                    child: TextButton(
                      onPressed: () {
                        Navigator.of(context).popUntil((route) => route.isFirst);
                      },
                      child: const Text("Return Home", style: TextStyle(color: Colors.grey)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTag(String text, Color bgColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildTrackableAdviceCard(List<String> items) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.checklist_rounded, color: Color(0xFF15803D), size: 20),
              SizedBox(width: 8),
              Text('Practical Advice',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF15803D))),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Tap "Track" to add any step to your Habit Tracker.',
            style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 12),
          ...items.map((item) {
            final tracked = _trackedAdvice.contains(item);
            final loading = _tracking.contains(item);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Text('  •  ',
                        style: TextStyle(color: Color(0xFF15803D), fontWeight: FontWeight.bold)),
                  ),
                  Expanded(
                    child: Text(
                      item,
                      style: const TextStyle(color: Color(0xFF374151), height: 1.4),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 32,
                    child: tracked
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDCFCE7),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            alignment: Alignment.center,
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_circle, size: 14, color: Color(0xFF15803D)),
                                SizedBox(width: 4),
                                Text('Tracking',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF15803D),
                                    )),
                              ],
                            ),
                          )
                        : ElevatedButton(
                            onPressed: loading ? null : () => _trackAdvice(item),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF15803D),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              minimumSize: const Size(0, 32),
                              textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                            child: loading
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Track'),
                          ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required IconData icon,
    required String title,
    required List<String> items,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF15803D), size: 20),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF15803D))),
            ],
          ),
          const SizedBox(height: 12),
          ...items.map((item) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("  \u2022  ", style: TextStyle(color: Color(0xFF15803D), fontWeight: FontWeight.bold)),
                Expanded(
                  child: Text(
                    item,
                    style: const TextStyle(color: Color(0xFF374151), height: 1.4),
                  ),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }
}
