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

  // The mood is locked in at check-in via widget.mood, but if the journal
  // text strongly contradicts it the backend flags an emotion_mismatch and
  // the user can switch. We track the live value here so the switch sticks
  // for the resubmit, the saved journal doc, and the guidance screen.
  late String _mood = widget.mood;

  /// [emotionConfirmed] is true on the resubmit AFTER the user has answered
  /// the emotion-mismatch dialog — it tells the backend to skip the mismatch
  /// pre-flight so we can't loop back into the same dialog.
  Future<void> _submitJournal({bool emotionConfirmed = false}) async {
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
          'mood': _mood,
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
        emotion: _mood,
        excludeStoryIds: widget.excludeStoryIds,
        emotionConfirmed: emotionConfirmed,
      );

      _hasFetchedGuidanceThisSession = true;

      // Emotion-mismatch path. The journal text clearly contradicts the
      // mood the user checked in with (e.g. checked in "happy" but wrote
      // about grief). Delete the placeholder doc, then ask the user which
      // feeling is truer — their answer drives the resubmit.
      if (guidanceData['emotion_mismatch'] == true) {
        if (journalRef != null) {
          try {
            await journalRef.delete();
          } catch (_) {/* best-effort cleanup */}
        }
        if (!mounted) return;
        setState(() => _isProcessing = false);
        await _showEmotionMismatchDialog(
          claimed: (guidanceData['claimed_emotion'] as String?) ?? _mood,
          suggested: (guidanceData['suggested_emotion'] as String?) ?? _mood,
          message: (guidanceData['mismatch_message'] as String?) ??
              'Your reflection sounds different from the mood you picked.',
        );
        return;
      }

      // Off-topic redirect path. Backend detected the text isn't an
      // emotional reflection (e.g. "who is the PM of Pakistan?"). Don't
      // pollute history with these — delete the placeholder doc we created
      // up top, then show a friendly dialog with example prompts.
      if (guidanceData['off_topic'] == true) {
        if (journalRef != null) {
          try {
            await journalRef.delete();
          } catch (_) {
            // Best-effort cleanup; if it fails the entry just sits as a
            // hasGuidance:false placeholder — user can delete it manually.
          }
        }
        if (!mounted) return;
        setState(() => _isProcessing = false);
        await _showOffTopicDialog(
          message: (guidanceData['redirect_message'] as String?) ??
              'Sakinah is here for emotional reflection.',
          suggestions: ((guidanceData['suggested_prompts'] as List?) ?? const [])
              .map((e) => e.toString())
              .toList(),
        );
        return;
      }

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
              'emotion': guidanceData['emotion'] ?? _mood,
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
            mood: _mood,
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

  /// Friendly redirect when the backend classifies the journal entry as
  /// off-topic. Shows the message + a column of tappable example prompts;
  /// tapping a prompt pre-fills the text field so the user can edit and
  /// resubmit rather than starting from scratch.
  Future<void> _showOffTopicDialog({
    required String message,
    required List<String> suggestions,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Let's try that again"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message, style: const TextStyle(fontSize: 14, height: 1.4)),
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'Try one of these:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF6B7280)),
              ),
              const SizedBox(height: 8),
              ...suggestions.map(
                (s) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      _journalController.text = s;
                      _journalController.selection = TextSelection.fromPosition(
                        TextPosition(offset: s.length),
                      );
                      Navigator.pop(ctx);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(s, style: const TextStyle(fontSize: 13)),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  /// Shown when the backend detects the journal text strongly contradicts
  /// the mood the user checked in with. The user always has the final say —
  /// "Keep" trusts their original pick, "Switch" adopts the AI's reading.
  /// Either choice resubmits with emotionConfirmed:true so the backend
  /// skips the mismatch check the second time and proceeds to guidance.
  Future<void> _showEmotionMismatchDialog({
    required String claimed,
    required String suggested,
    required String message,
  }) async {
    String cap(String s) =>
        s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('How are you feeling?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message, style: const TextStyle(fontSize: 14, height: 1.45)),
            const SizedBox(height: 12),
            const Text(
              'You have the final say — pick whichever is true for you.',
              style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
            ),
          ],
        ),
        actionsOverflowDirection: VerticalDirection.down,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, claimed),
            child: Text('Keep ${cap(claimed)}'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, suggested),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF15803D),
              foregroundColor: Colors.white,
            ),
            child: Text('Switch to ${cap(suggested)}'),
          ),
        ],
      ),
    );

    if (choice == null || !mounted) return;
    // Whatever the user chose becomes the live mood. Re-run guidance with
    // emotionConfirmed:true so the backend doesn't ask again.
    setState(() => _mood = choice);
    await _submitJournal(emotionConfirmed: true);
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
                      _mood,
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
