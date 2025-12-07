import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CommentSheet extends StatefulWidget {
  final String postId;
  const CommentSheet({super.key, required this.postId});

  @override
  State<CommentSheet> createState() => _CommentSheetState();
}

class _CommentSheetState extends State<CommentSheet> {
  final TextEditingController _controller = TextEditingController();
  bool _isSending = false;
  final Color primaryColor = const Color(0xFF15803D);

  Future<void> _addComment() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _isSending = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      // Fetch user details for the comment
      String username = user?.displayName ?? 'Seeker';
      
      // Try to get from Firestore for better accuracy
      if (user != null) {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (userDoc.exists && userDoc.data()?['firstName'] != null) {
          username = userDoc.data()!['firstName'];
        }
      }

      final postRef = FirebaseFirestore.instance.collection('posts').doc(widget.postId);

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final newCommentRef = postRef.collection('comments').doc();
        transaction.set(newCommentRef, {
          'username': username,
          'userId': user?.uid,
          'comment': text,
          'createdAt': FieldValue.serverTimestamp(),
        });
        transaction.update(postRef, {'commentCount': FieldValue.increment(1)});
      });

      _controller.clear();
    } catch (e) {
      debugPrint("Error adding comment: $e");
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        top: 16,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            "Comments",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF15803D)),
          ),
          const Divider(),
          
          // Comment List
          SizedBox(
            height: 300,
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('posts')
                  .doc(widget.postId)
                  .collection('comments')
                  .orderBy('createdAt', descending: false)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text("No comments yet. Be the first!"));
                }
                final comments = snapshot.data!.docs;
                
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: comments.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    final data = comments[index].data() as Map<String, dynamic>;
                    final userId = data['userId'] as String?;
                    
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FutureBuilder<DocumentSnapshot>(
                          future: userId != null
                              ? FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(userId)
                                  .get()
                              : Future.value(null as DocumentSnapshot?),
                          builder: (context, snapshot) {
                            String? photoUrl;
                            if (snapshot.hasData && snapshot.data != null && snapshot.data!.exists) {
                              final userData = snapshot.data!.data() as Map<String, dynamic>;
                              photoUrl = userData['photoUrl'] as String?;
                            }
                            
                            return CircleAvatar(
                              radius: 16,
                              backgroundColor: Colors.grey.shade200,
                              backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
                                  ? NetworkImage(photoUrl)
                                  : null,
                              child: (photoUrl == null || photoUrl.isEmpty)
                                  ? const Icon(Icons.person, size: 18, color: Colors.grey)
                                  : null,
                            );
                          },
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                data['username'] ?? 'User',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              Text(
                                data['comment'] ?? '',
                                style: const TextStyle(fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),

          // Input Field
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: "Add a comment...",
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: _isSending 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) 
                    : Icon(Icons.send, color: primaryColor),
                  onPressed: _isSending ? null : _addComment,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}