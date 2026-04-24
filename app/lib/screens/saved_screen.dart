import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class SavedScreen extends StatelessWidget {
  const SavedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        title: const Text(
          'Saved Advice',
          style: TextStyle(color: Color(0xFF15803D), fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        surfaceTintColor: Colors.white,
        iconTheme: const IconThemeData(color: Color(0xFF15803D)),
      ),
      body: user == null
          ? _buildSignInRequired()
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .collection('bookmarks')
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: Color(0xFF15803D)),
                  );
                }
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Could not load bookmarks: ${snap.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFF6B7280)),
                      ),
                    ),
                  );
                }

                // Client-side sort by createdAt desc so we don't need a composite index
                final docs = (snap.data?.docs ?? []).toList()
                  ..sort((a, b) {
                    final at = (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
                    final bt = (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
                    if (at == null && bt == null) return 0;
                    if (at == null) return 1;
                    if (bt == null) return -1;
                    return bt.compareTo(at);
                  });

                if (docs.isEmpty) {
                  return _buildEmptyState();
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final doc = docs[i];
                    final data = doc.data() as Map<String, dynamic>;
                    return _BookmarkCard(
                      advice: (data['advice'] ?? '').toString(),
                      storyTitle: (data['storyTitle'] ?? '').toString(),
                      storyPeriod: (data['storyPeriod'] ?? '').toString(),
                      emotion: (data['emotion'] ?? '').toString(),
                      createdAt: data['createdAt'] as Timestamp?,
                      onRemove: () => doc.reference.delete(),
                    );
                  },
                );
              },
            ),
    );
  }

  Widget _buildSignInRequired() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(40),
        child: Text(
          'Sign in to view your saved advice.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF6B7280), fontSize: 15),
        ),
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
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(Icons.star_outline_rounded,
                  size: 48, color: Color(0xFFF59E0B)),
            ),
            const SizedBox(height: 24),
            const Text(
              'No saved advice yet',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF064E3B),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Tap the star next to any practical advice on a guidance screen to save it here for later.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Color(0xFF6B7280), height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _BookmarkCard extends StatelessWidget {
  final String advice;
  final String storyTitle;
  final String storyPeriod;
  final String emotion;
  final Timestamp? createdAt;
  final VoidCallback onRemove;

  const _BookmarkCard({
    required this.advice,
    required this.storyTitle,
    required this.storyPeriod,
    required this.emotion,
    required this.createdAt,
    required this.onRemove,
  });

  String _formatDate(Timestamp? ts) {
    if (ts == null) return '';
    final dt = ts.toDate();
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
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
          Row(
            children: [
              const Icon(Icons.star_rounded, size: 20, color: Color(0xFFF59E0B)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  advice,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Color(0xFF1F2937),
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (storyTitle.isNotEmpty) _metaChip(storyTitle, Icons.menu_book_rounded),
              if (emotion.isNotEmpty) _metaChip('Feeling $emotion', Icons.favorite_outline),
              if (storyPeriod.isNotEmpty) _metaChip(storyPeriod, Icons.access_time_rounded),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                _formatDate(createdAt),
                style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: onRemove,
                icon: const Icon(Icons.star_rounded, size: 16, color: Color(0xFFDC2626)),
                label: const Text(
                  'Unsave',
                  style: TextStyle(fontSize: 12, color: Color(0xFFDC2626)),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 28),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metaChip(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: const Color(0xFF6B7280)),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
          ),
        ],
      ),
    );
  }
}
