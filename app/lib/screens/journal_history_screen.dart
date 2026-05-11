import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/guidance_service.dart';
import '../services/notification_service.dart';
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
        scrolledUnderElevation: 1,
        surfaceTintColor: Colors.white,
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
              final savedGuidance = (data['hasGuidance'] == true)
                  ? (data['guidance'] as Map<String, dynamic>?)
                  : null;
              return _JournalEntryCard(
                entryId: docs[index].id,
                uid: _uid,
                storyId: savedGuidance?['story_id'] as String?,
                text: data['text'] ?? '',
                mood: data['mood'] ?? '',
                createdAt: data['createdAt'] as Timestamp?,
                savedGuidance: savedGuidance,
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
  final String entryId;
  final String uid;
  // Null when this entry has no saved guidance (hasGuidance == false).
  // When null, the cascade-delete checkbox is hidden because there's
  // nothing to cascade — no bookmarks or habits can be linked.
  final String? storyId;
  final String text;
  final String mood;
  final Timestamp? createdAt;
  final Map<String, dynamic>? savedGuidance;

  const _JournalEntryCard({
    required this.entryId,
    required this.uid,
    required this.storyId,
    required this.text,
    required this.mood,
    required this.createdAt,
    this.savedGuidance,
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

  void _openSavedGuidance() {
    final saved = widget.savedGuidance;
    if (saved == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GuidanceScreen(
          mood: widget.mood,
          guidanceData: Map<String, dynamic>.from(saved),
        ),
      ),
    );
  }

  /// Two-step delete: confirmation dialog with an optional cascade
  /// checkbox. When the checkbox is checked, we also delete every
  /// bookmark and habit that references this entry's story (NOT just
  /// this entry — see dialog wording). All deletes happen atomically
  /// in a single Firestore WriteBatch so we don't end up half-deleted
  /// if the network drops mid-cleanup.
  Future<void> _confirmAndDelete() async {
    bool cascade = false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocalState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Delete this entry?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'This will permanently remove this journal entry and its saved guidance.',
                style: TextStyle(fontSize: 14, height: 1.4),
              ),
              if (widget.storyId != null && widget.storyId!.isNotEmpty) ...[
                const SizedBox(height: 16),
                InkWell(
                  onTap: () => setLocalState(() => cascade = !cascade),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox(
                          value: cascade,
                          activeColor: const Color(0xFF15803D),
                          onChanged: (v) => setLocalState(() => cascade = v ?? false),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        const SizedBox(width: 4),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Also delete bookmarks and habits from this story',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Saved items from this story will be removed — even if you saved them from a different journal entry that retrieved the same story.',
                                style: TextStyle(fontSize: 11, color: Color(0xFF6B7280), height: 1.4),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;

    final firestore = FirebaseFirestore.instance;
    final journalRef = firestore
        .collection('users')
        .doc(widget.uid)
        .collection('journals')
        .doc(widget.entryId);

    int bookmarksRemoved = 0;
    int habitsRemoved = 0;

    try {
      if (cascade &&
          widget.storyId != null &&
          widget.storyId!.isNotEmpty) {
        final batch = firestore.batch();
        batch.delete(journalRef);

        // Bookmarks: filtered by storyId so we delete only this story's saves.
        final bookmarks = await firestore
            .collection('users')
            .doc(widget.uid)
            .collection('bookmarks')
            .where('storyId', isEqualTo: widget.storyId)
            .get();
        for (final doc in bookmarks.docs) {
          batch.delete(doc.reference);
        }
        bookmarksRemoved = bookmarks.docs.length;

        // Habits: filtered by sourceStoryId.
        final habits = await firestore
            .collection('users')
            .doc(widget.uid)
            .collection('habits')
            .where('sourceStoryId', isEqualTo: widget.storyId)
            .get();
        // Cancel scheduled local notifications for each habit before
        // wiping them from Firestore — otherwise they'd fire pointing
        // at a deleted doc.
        for (final doc in habits.docs) {
          await NotificationService.instance.cancelHabitReminder(doc.id);
          batch.delete(doc.reference);
        }
        habitsRemoved = habits.docs.length;

        await batch.commit();
      } else {
        // Simple path: just delete the journal doc. No batch needed.
        await journalRef.delete();
      }

      if (!mounted) return;
      final summary = cascade
          ? 'Entry deleted. Also removed $bookmarksRemoved bookmark(s) and $habitsRemoved habit(s) from this story.'
          : 'Entry deleted.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(summary),
          backgroundColor: const Color(0xFF15803D),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not delete entry: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
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
            // Header: mood tag + date + actions menu
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
                PopupMenuButton<String>(
                  tooltip: 'Entry options',
                  icon: const Icon(Icons.more_vert, size: 18, color: Color(0xFF9CA3AF)),
                  padding: EdgeInsets.zero,
                  // Stop tap-bubble so opening the menu doesn't also toggle
                  // the card's expand/collapse state.
                  onOpened: () {},
                  onSelected: (value) {
                    if (value == 'delete') _confirmAndDelete();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem<String>(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, size: 18, color: Colors.red),
                          SizedBox(width: 8),
                          Text('Delete entry', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
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

            // Saved-guidance marker in collapsed view
            if (!_isExpanded && widget.savedGuidance != null) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.auto_awesome, size: 14, color: Color(0xFF15803D)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Guidance saved · ${widget.savedGuidance!['story_title'] ?? ''}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF15803D),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ],

            // Expanded: View Guidance (primary if saved) + Get Guidance Again (secondary)
            if (_isExpanded) ...[
              const SizedBox(height: 16),
              if (widget.savedGuidance != null) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _openSavedGuidance,
                    icon: const Icon(Icons.menu_book_rounded, size: 16),
                    label: const Text('View Guidance'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF15803D),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
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
                  label: Text(
                    _isLoadingGuidance
                        ? 'Finding Guidance...'
                        : (widget.savedGuidance != null ? 'Get New Guidance' : 'Get Guidance Again'),
                  ),
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
