import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/guidance_service.dart';
import 'guidance_screen.dart';

class JournalHistoryScreen extends StatelessWidget {
  const JournalHistoryScreen({super.key});

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        title: const Text(
          'Journal History',
          style: TextStyle(color: Color(0xFF15803D), fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF15803D)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(_uid)
            .collection('journals')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF15803D)),
            );
          }

          final docs = snapshot.data?.docs ?? [];

          if (docs.isEmpty) {
            return _buildEmptyState();
          }

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              return _JournalEntryCard(
                text: data['text'] ?? '',
                mood: data['mood'] ?? '',
                createdAt: data['createdAt'] as Timestamp?,
              );
            },
          );
        },
      ),
    );
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
              child: const Icon(Icons.menu_book_rounded, size: 48, color: Color(0xFF15803D)),
            ),
            const SizedBox(height: 24),
            const Text(
              'No Journals Yet',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF064E3B),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Start your reflection journey.\nYour journal entries will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Color(0xFF6B7280), height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Expandable Journal Entry Card ───

class _JournalEntryCard extends StatefulWidget {
  final String text;
  final String mood;
  final Timestamp? createdAt;

  const _JournalEntryCard({
    required this.text,
    required this.mood,
    required this.createdAt,
  });

  @override
  State<_JournalEntryCard> createState() => _JournalEntryCardState();
}

class _JournalEntryCardState extends State<_JournalEntryCard> {
  bool _isExpanded = false;
  bool _isLoadingGuidance = false;

  String _formatDate(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate();
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final amPm = dt.hour >= 12 ? 'PM' : 'AM';
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} at $hour:${dt.minute.toString().padLeft(2, '0')} $amPm';
  }

  Color _moodBgColor(String mood) {
    const map = {
      'happy': Color(0xFFFEF9C3),
      'grateful': Color(0xFFFEF9C3),
      'sad': Color(0xFFDBEAFE),
      'lonely': Color(0xFFDBEAFE),
      'hopeless': Color(0xFFDBEAFE),
      'anxious': Color(0xFFFEF3C7),
      'stressed': Color(0xFFFEF3C7),
      'fearful': Color(0xFFFEF3C7),
      'overwhelmed': Color(0xFFFEF3C7),
      'angry': Color(0xFFFFE4E6),
      'guilty': Color(0xFFFFE4E6),
      'rejected': Color(0xFFFFE4E6),
      'embarrassed': Color(0xFFFFE4E6),
      'confused': Color(0xFFF3F4F6),
      'lost': Color(0xFFF3F4F6),
    };
    return map[mood.toLowerCase()] ?? const Color(0xFFDCFCE7);
  }

  Color _moodTextColor(String mood) {
    const map = {
      'happy': Color(0xFF92400E),
      'grateful': Color(0xFF92400E),
      'sad': Color(0xFF1E40AF),
      'lonely': Color(0xFF1E40AF),
      'hopeless': Color(0xFF1E40AF),
      'anxious': Color(0xFF92400E),
      'stressed': Color(0xFF92400E),
      'fearful': Color(0xFF92400E),
      'overwhelmed': Color(0xFF92400E),
      'angry': Color(0xFF9F1239),
      'guilty': Color(0xFF9F1239),
      'rejected': Color(0xFF9F1239),
      'embarrassed': Color(0xFF9F1239),
      'confused': Color(0xFF374151),
      'lost': Color(0xFF374151),
    };
    return map[mood.toLowerCase()] ?? const Color(0xFF15803D);
  }

  Future<void> _getGuidanceAgain() async {
    setState(() => _isLoadingGuidance = true);
    try {
      final guidanceData = await GuidanceService.getGuidance(
        journalEntry: widget.text,
        emotion: widget.mood,
      );
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => GuidanceScreen(
            mood: widget.mood,
            guidanceData: guidanceData,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Could not connect to guidance server.'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoadingGuidance = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = widget.text.length > 120
        ? '${widget.text.substring(0, 120)}...'
        : widget.text;
    final moodLabel = widget.mood.isNotEmpty
        ? widget.mood[0].toUpperCase() + widget.mood.substring(1)
        : '';

    return GestureDetector(
      onTap: () => setState(() => _isExpanded = !_isExpanded),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: mood tag + date
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _moodBgColor(widget.mood),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    moodLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _moodTextColor(widget.mood),
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  _formatDate(widget.createdAt),
                  style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Text content
            Text(
              _isExpanded ? widget.text : preview,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF374151),
                height: 1.5,
              ),
            ),

            // Expand indicator
            if (!_isExpanded && widget.text.length > 120) ...[
              const SizedBox(height: 8),
              const Text(
                'Tap to read more',
                style: TextStyle(fontSize: 12, color: Color(0xFF15803D), fontWeight: FontWeight.w500),
              ),
            ],

            // Expanded: Get Guidance Again button
            if (_isExpanded) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isLoadingGuidance ? null : _getGuidanceAgain,
                  icon: _isLoadingGuidance
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF15803D)),
                        )
                      : const Icon(Icons.auto_awesome, size: 16),
                  label: Text(_isLoadingGuidance ? 'Finding Guidance...' : 'Get Guidance Again'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF15803D),
                    side: const BorderSide(color: Color(0xFF15803D)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
