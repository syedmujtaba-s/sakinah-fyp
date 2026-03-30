import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sakinah/community/widgets/postCard.dart';
import 'package:sakinah/community/widgets/communityTagChips.dart';
import 'package:sakinah/community/post.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  final List<String> tags = ['All Topics', 'General', 'Anxiety', 'Gratitude', 'Patience', 'Hope'];
  int selectedTag = 0;
  final Color primaryColor = const Color(0xFF15803D);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        title: const Text("Community", style: TextStyle(color: Color(0xFF15803D), fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const CreatePostScreen()));
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text("New Post"),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                elevation: 0,
              ),
            ),
          )
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 10),
          // Filter Chips
          CommunityTagChips(
            tags: tags,
            selectedTag: selectedTag,
            onTagSelected: (val) => setState(() => selectedTag = val),
          ),
          const SizedBox(height: 10),
          
          // Post List
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('posts')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_outline, size: 48, color: Colors.grey),
                        SizedBox(height: 16),
                        Text("No posts yet. Start the conversation!", style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  );
                }

                final posts = snapshot.data!.docs;
                
                // Filter logic
                final filteredPosts = selectedTag == 0
                    ? posts
                    : posts.where((doc) => (doc['tag'] ?? '') == tags[selectedTag]).toList();

                if (filteredPosts.isEmpty) {
                  return const Center(child: Text("No posts found for this topic."));
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: filteredPosts.length,
                  itemBuilder: (context, index) {
                    return PostCard(postDoc: filteredPosts[index]);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}