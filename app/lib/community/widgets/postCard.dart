import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sakinah/community/post.dart';
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
                  ImageProvider? img;
                  if (snapshot.hasData && snapshot.data!.exists) {
                    final userData = snapshot.data!.data() as Map<String, dynamic>;
                    final b64 = userData['photoBase64'] as String?;
                    final url = userData['photoUrl'] as String?;
                    if (b64 != null && b64.isNotEmpty) {
                      img = MemoryImage(base64Decode(b64));
                    } else if (url != null && url.isNotEmpty) {
                      img = NetworkImage(url);
                    }
                  }

                  return CircleAvatar(
                    radius: 18,
                    backgroundColor: primaryColor.withOpacity(0.1),
                    backgroundImage: img,
                    child: img == null
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
              // Owner-only menu — Edit + Delete. We hide the entire trailing
              // affordance for non-authors so other users don't even see a
              // disabled icon hinting at the moderation surface.
              if (isMyPost)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 20, color: Colors.grey),
                  tooltip: 'Post options',
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  onSelected: (value) {
                    if (value == 'edit') {
                      _openEditScreen(context, data);
                    } else if (value == 'delete') {
                      _confirmDelete(context, widget.postDoc.id);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem<String>(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 18, color: Colors.black87),
                          SizedBox(width: 10),
                          Text('Edit'),
                        ],
                      ),
                    ),
                    PopupMenuItem<String>(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, size: 18, color: Colors.red),
                          SizedBox(width: 10),
                          Text('Delete', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
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

  /// Opens the same screen used for *creating* a post, but in edit mode —
  /// `CreatePostScreen` runs an `update()` instead of `add()` when given an
  /// `editPostId`, and only mutates the fields the author may change
  /// (title, body, tag). likeCount, comments, userId, createdAt all stay
  /// pinned regardless of how many times the post is edited.
  void _openEditScreen(BuildContext context, Map<String, dynamic> data) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreatePostScreen(
          editPostId: widget.postDoc.id,
          initialTitle: data['postTitle'] as String? ?? '',
          initialBody: data['postBody'] as String? ?? '',
          initialTag: data['tag'] as String?,
        ),
      ),
    );
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