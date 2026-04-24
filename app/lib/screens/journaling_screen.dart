import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/guidance_service.dart';
import 'guidance_screen.dart';
import 'journal_history_screen.dart';

class JournalingScreen extends StatefulWidget {
  final String mood;
  // When a habit's source advice didn't help, we route the user here with the
  // original story excluded so the RAG pipeline surfaces something different.
  final List<String> excludeStoryIds;
  const JournalingScreen({
    super.key,
    required this.mood,
    this.excludeStoryIds = const [],
  });

  @override
  State<JournalingScreen> createState() => _JournalingScreenState();
}

class _JournalingScreenState extends State<JournalingScreen> {
  static bool _hasFetchedGuidanceThisSession = false;
  final TextEditingController _journalController = TextEditingController();
  bool _isProcessing = false;

  Future<void> _submitJournal() async {
    if (_journalController.text.trim().isEmpty) return;

    setState(() => _isProcessing = true);

    final journalText = _journalController.text.trim();

    // Create the journal doc up front so it's captured even if guidance fails.
    // We keep the ref around and merge the guidance response into the same doc
    // once it's available, so history can re-open the full session.
    final user = FirebaseAuth.instance.currentUser;
    DocumentReference<Map<String, dynamic>>? journalRef;
    if (user != null) {
      try {
        journalRef = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('journals')
            .add({
          'text': journalText,
          'mood': widget.mood,
          'createdAt': FieldValue.serverTimestamp(),
          'hasGuidance': false,
        });
      } catch (e) {
        // Handle error silently — guidance call can still proceed.
      }
    }

    if (!mounted) return;

    // Call backend API for AI-powered guidance
    try {
      final guidanceData = await GuidanceService.getGuidance(
        journalEntry: journalText,
        emotion: widget.mood,
        excludeStoryIds: widget.excludeStoryIds,
      );

      _hasFetchedGuidanceThisSession = true;

      // Persist the full guidance response so it's revisitable from history.
      if (journalRef != null) {
        try {
          await journalRef.update({
            'hasGuidance': true,
            'guidance': {
              'story_id': guidanceData['story_id'] ?? '',
              'story_title': guidanceData['story_title'] ?? '',
              'story_period': guidanceData['story_period'] ?? '',
              'story_summary': guidanceData['story_summary'] ?? '',
              'story': guidanceData['story'] ?? '',
              'seerah_connection': guidanceData['seerah_connection'] ?? '',
              'lessons': guidanceData['lessons'] ?? [],
              'practical_advice': guidanceData['practical_advice'] ?? [],
              'dua': guidanceData['dua'] ?? '',
              'follow_up_questions': guidanceData['follow_up_questions'] ?? [],
              'emotion': guidanceData['emotion'] ?? widget.mood,
              'ai_fallback': guidanceData['ai_fallback'] ?? false,
              'crisis': guidanceData['crisis'] ?? false,
              'crisis_message': guidanceData['crisis_message'] ?? '',
            },
          });
        } catch (_) {
          // Saving history is best-effort; don't block the user from seeing guidance.
        }
      }

      if (!mounted) return;

      Navigator.pushReplacement(
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
      setState(() => _isProcessing = false);

      debugPrint('GuidanceService error: $e');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Guidance failed: $e'),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 8),
        ),
      );
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
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "Reflection",
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const JournalHistoryScreen()),
              );
            },
            child: const Text(
              'History',
              style: TextStyle(color: Color(0xFF15803D), fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Context Tag
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text("Feeling: ", style: TextStyle(color: Colors.grey)),
                    Text(
                      widget.mood,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF15803D),
                      ),
                    ),
                  ],
                ),
              ),

              // Alternatives banner — shown when the user arrived here from the
              // "Need alternative" feedback flow so they know this is a retry.
              if (widget.excludeStoryIds.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFDE68A)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Icon(Icons.refresh_rounded, size: 20, color: Color(0xFF92400E)),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "We'll skip the story from last time and find something different. Write what's on your mind — even a sentence is fine.",
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF78350F),
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),

              const Text(
                "Pour your heart out...",
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF064E3B),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "This space is private. Allah listens, and writing helps clarify the mind.",
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 24),

              // Text Input
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAFAFA),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: TextField(
                    controller: _journalController,
                    maxLines: null,
                    expands: true,
                    style: const TextStyle(fontSize: 16, height: 1.5),
                    decoration: const InputDecoration(
                      hintText: "Start writing here...",
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Submit Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isProcessing ? null : _submitJournal,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: const Color(0xFF15803D),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _isProcessing
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                            SizedBox(width: 12),
                            Text("Finding Guidance..."),
                          ],
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text("Get Guidance", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            SizedBox(width: 8),
                            Icon(Icons.auto_awesome, size: 18),
                          ],
                        ),
                ),
              ),
              if (_isProcessing && !_hasFetchedGuidanceThisSession)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'The first response can take up to a minute while the model warms up.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: Color(0xFF6B7280), height: 1.4),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
