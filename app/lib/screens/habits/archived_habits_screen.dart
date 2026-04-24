import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/notification_service.dart';
import 'habit_tracker_screen.dart' show getHabitColor, getHabitIcon;

/// Lists habits where `isActive == false`. Restore puts them back on the
/// tracker; Purge is a true destructive delete for users who want to clean
/// house. Completion logs stay intact across archive/restore cycles.
class ArchivedHabitsScreen extends StatelessWidget {
  const ArchivedHabitsScreen({super.key});

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  Widget build(BuildContext context) {
    final uid = _uid;
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        title: const Text(
          'Archived Habits',
          style: TextStyle(color: Color(0xFF15803D), fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        surfaceTintColor: Colors.white,
        iconTheme: const IconThemeData(color: Color(0xFF15803D)),
      ),
      body: uid == null
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Text('Sign in to view archived habits.',
                    style: TextStyle(color: Color(0xFF6B7280))),
              ),
            )
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(uid)
                  .collection('habits')
                  .where('isActive', isEqualTo: false)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return _errorBox(snap.error);
                }
                if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: Color(0xFF15803D)),
                  );
                }
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) return _emptyState();

                // Client-side sort by archivedAt desc (fallback to createdAt)
                final list = List<QueryDocumentSnapshot>.from(docs);
                list.sort((a, b) {
                  final aData = a.data() as Map<String, dynamic>;
                  final bData = b.data() as Map<String, dynamic>;
                  final at = (aData['archivedAt'] ?? aData['createdAt']) as Timestamp?;
                  final bt = (bData['archivedAt'] ?? bData['createdAt']) as Timestamp?;
                  if (at == null && bt == null) return 0;
                  if (at == null) return 1;
                  if (bt == null) return -1;
                  return bt.compareTo(at);
                });

                return ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: list.length,
                  itemBuilder: (context, i) => _ArchivedHabitTile(
                    doc: list[i],
                    uid: uid,
                  ),
                );
              },
            ),
    );
  }

  Widget _emptyState() {
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
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(Icons.archive_outlined,
                  size: 48, color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 24),
            const Text(
              'Nothing archived',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF064E3B),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Archived habits appear here. You can restore or permanently delete them anytime.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Color(0xFF6B7280), height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorBox(Object? err) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Could not load archived habits: $err',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF6B7280)),
        ),
      ),
    );
  }
}

class _ArchivedHabitTile extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  final String uid;

  const _ArchivedHabitTile({required this.doc, required this.uid});

  Future<void> _restore(BuildContext context) async {
    await doc.reference.update({
      'isActive': true,
      'archivedAt': FieldValue.delete(),
    });
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Restored to your habits.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _purge(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete forever?'),
        content: const Text(
          'This permanently deletes the habit AND all its completion history. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete forever'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // Delete the habit doc + all habitLogs tied to it (batched, 30 IDs per query)
    final habitId = doc.id;
    final db = FirebaseFirestore.instance;
    try {
      final logsSnap = await db
          .collection('users')
          .doc(uid)
          .collection('habitLogs')
          .where('habitId', isEqualTo: habitId)
          .get();
      for (var i = 0; i < logsSnap.docs.length; i += 500) {
        final batch = db.batch();
        for (final log in logsSnap.docs.skip(i).take(500)) {
          batch.delete(log.reference);
        }
        await batch.commit();
      }
      await doc.reference.delete();
      // Safety net in case the reminder was still scheduled
      await NotificationService.instance.cancelHabitReminder(habitId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Permanently deleted.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Purge failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = doc.data() as Map<String, dynamic>;
    final title = (data['title'] ?? '').toString();
    final category = (data['category'] ?? 'custom').toString();
    final color = getHabitColor((data['color'] ?? '#15803D').toString());
    final icon = getHabitIcon((data['icon'] ?? '').toString());
    final archivedAt = (data['archivedAt'] as Timestamp?)?.toDate();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1F2937),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  archivedAt == null
                      ? category
                      : '$category · archived ${_formatAgo(archivedAt)}',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Restore',
            onPressed: () => _restore(context),
            icon: const Icon(Icons.unarchive_outlined, color: Color(0xFF15803D), size: 22),
          ),
          IconButton(
            tooltip: 'Delete forever',
            onPressed: () => _purge(context),
            icon: const Icon(Icons.delete_forever_outlined, color: Color(0xFFDC2626), size: 22),
          ),
        ],
      ),
    );
  }

  String _formatAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 30) return '${(diff.inDays / 30).floor()}mo ago';
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    return 'just now';
  }
}
