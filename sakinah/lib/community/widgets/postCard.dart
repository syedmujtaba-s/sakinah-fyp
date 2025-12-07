import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sakinah/community/widgets/comment.dart';

class PostCard extends StatefulWidget {
  final QueryDocumentSnapshot postDoc;
  const PostCard({super.key, required this.postDoc});

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  final Color primaryColor = const Color(0xFF15803D);
  bool isLiking = false;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final data = widget.postDoc.data() as Map<String, dynamic>;
    
    // Parse Data
    final String username = data['username'] ?? 'User';
    final String title = data['postTitle'] ?? '';
    final String body = data['postBody'] ?? '';
    final String tag = data['tag'] ?? '';
    final int likeCount = data['likeCount'] ?? 0;
    final int commentCount = data['commentCount'] ?? 0;
    final List likedBy = data['likedBy'] ?? [];
    final bool isLiked = likedBy.contains(user?.uid);
    final bool isMyPost = data['userId'] == user?.uid;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Avatar, Name, Tag
          Row(
            children: [
              FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance
                    .collection('users')
                    .doc(data['userId'])
                    .get(),
                builder: (context, snapshot) {
                  String? photoUrl;
                  if (snapshot.hasData && snapshot.data!.exists) {
                    final userData = snapshot.data!.data() as Map<String, dynamic>;
                    photoUrl = userData['photoUrl'] as String?;
                  }
                  
                  return CircleAvatar(
                    radius: 18,
                    backgroundColor: primaryColor.withOpacity(0.1),
                    backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
                        ? NetworkImage(photoUrl)
                        : null,
                    child: (photoUrl == null || photoUrl.isEmpty)
                        ? Icon(Icons.person, color: primaryColor, size: 20)
                        : null,
                  );
                },
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(username, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    if (tag.isNotEmpty)
                      Text(tag, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                  ],
                ),
              ),
              if (isMyPost)
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20, color: Colors.grey),
                  onPressed: () => _confirmDelete(context, widget.postDoc.id),
                ),
            ],
          ),
          const SizedBox(height: 12),
          
          // Content
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 6),
          Text(body, style: TextStyle(color: Colors.grey.shade800, fontSize: 14, height: 1.4)),
          const SizedBox(height: 16),

          // Actions
          Row(
            children: [
              // Like Button
              GestureDetector(
                onTap: () => _toggleLike(isLiked, likeCount),
                child: Row(
                  children: [
                    Icon(
                      isLiked ? Icons.favorite : Icons.favorite_border,
                      color: isLiked ? Colors.red : Colors.grey,
                      size: 20,
                    ),
                    const SizedBox(width: 6),
                    Text("$likeCount", style: TextStyle(color: Colors.grey.shade700)),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              // Comment Button
              GestureDetector(
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => CommentSheet(postId: widget.postDoc.id),
                  );
                },
                child: Row(
                  children: [
                    const Icon(Icons.mode_comment_outlined, color: Colors.grey, size: 20),
                    const SizedBox(width: 6),
                    Text("$commentCount", style: TextStyle(color: Colors.grey.shade700)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _toggleLike(bool isLiked, int currentCount) async {
    if (isLiking) return;
    setState(() => isLiking = true);
    
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final ref = FirebaseFirestore.instance.collection('posts').doc(widget.postDoc.id);

    try {
      if (isLiked) {
        await ref.update({
          'likeCount': currentCount - 1,
          'likedBy': FieldValue.arrayRemove([user.uid])
        });
      } else {
        await ref.update({
          'likeCount': currentCount + 1,
          'likedBy': FieldValue.arrayUnion([user.uid])
        });
      }
    } catch (_) {}
    
    if (mounted) setState(() => isLiking = false);
  }

  void _confirmDelete(BuildContext context, String postId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Post"),
        content: const Text("Are you sure you want to delete this post?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          TextButton(
            onPressed: () {
              FirebaseFirestore.instance.collection('posts').doc(postId).delete();
              Navigator.pop(ctx);
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}