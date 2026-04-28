import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Used both for *creating* a new community post and *editing* an existing
/// one the user owns. Pass [editPostId] (plus the initial values from the
/// existing doc) to switch into edit mode — the screen then PATCHes the
/// existing document instead of creating a new one.
class CreatePostScreen extends StatefulWidget {
  /// When provided, the screen runs in edit mode and updates this post id.
  final String? editPostId;
  final String? initialTitle;
  final String? initialBody;
  final String? initialTag;

  const CreatePostScreen({
    super.key,
    this.editPostId,
    this.initialTitle,
    this.initialBody,
    this.initialTag,
  });

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  bool _isSubmitting = false;
  String? _selectedTag;

  // Sakinah Topics
  final List<String> _tags = [
    'General',
    'Anxiety',
    'Gratitude',
    'Patience',
    'Hope',
  ];
  final Color primaryColor = const Color(0xFF15803D);

  bool get _isEditing => widget.editPostId != null;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle ?? '');
    _bodyController = TextEditingController(text: widget.initialBody ?? '');
    // If the incoming tag is somehow no longer in the canonical list, fall
    // back to "General" so the dropdown doesn't hit the assertion.
    _selectedTag = (widget.initialTag != null && _tags.contains(widget.initialTag))
        ? widget.initialTag
        : null;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _submitPost() async {
    if (_titleController.text.isEmpty || _selectedTag == null) return;
    setState(() => _isSubmitting = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      if (_isEditing) {
        // Edit path — only mutate the fields the author is allowed to
        // change. Author identity, like/comment counts, createdAt all stay
        // pinned. We attach an editedAt server timestamp so the UI can
        // surface "(edited)" indicators later if the team wants to.
        await FirebaseFirestore.instance
            .collection('posts')
            .doc(widget.editPostId)
            .update({
          'postTitle': _titleController.text.trim(),
          'postBody': _bodyController.text.trim(),
          'tag': _selectedTag,
          'editedAt': FieldValue.serverTimestamp(),
        });
      } else {
        // Create path — unchanged from before. Username is denormalised
        // onto the post doc so feed reads don't fan out into a per-author
        // user-doc fetch.
        String username = user.displayName ?? 'Seeker';
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (userDoc.exists && userDoc.data()?['firstName'] != null) {
          username = userDoc.data()!['firstName'];
        }

        await FirebaseFirestore.instance.collection('posts').add({
          "username": username,
          "userId": user.uid,
          "postTitle": _titleController.text.trim(),
          "postBody": _bodyController.text.trim(),
          "tag": _selectedTag,
          "likeCount": 0,
          "commentCount": 0,
          "likedBy": [],
          "createdAt": FieldValue.serverTimestamp(),
        });
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        surfaceTintColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _isEditing ? "Edit Post" : "Create Post",
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isSubmitting ? null : _submitPost,
            child: _isSubmitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    _isEditing ? "Save" : "Post",
                    style: TextStyle(
                      color: primaryColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Tag Dropdown
            DropdownButtonFormField<String>(
              initialValue: _selectedTag,
              hint: const Text("Select Topic"),
              items: _tags
                  .map((tag) => DropdownMenuItem(value: tag, child: Text(tag)))
                  .toList(),
              onChanged: (val) => setState(() => _selectedTag = val),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.grey.shade50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Title
            TextField(
              controller: _titleController,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                hintText: "Title",
                border: InputBorder.none,
              ),
            ),
            const Divider(),

            // Body
            TextField(
              controller: _bodyController,
              maxLines: 10,
              decoration: const InputDecoration(
                hintText: "Share your thoughts...",
                border: InputBorder.none,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
