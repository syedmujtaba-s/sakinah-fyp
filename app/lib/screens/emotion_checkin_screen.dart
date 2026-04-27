import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/emotion_correction_logger.dart';
import '../services/face_emotion_service.dart';
import '../services/user_preferences_service.dart';
import '../widgets/emotion_camera_view.dart';
import 'journaling_screen.dart';

/// Emotion Check-in screen — multi-modal entry point.
///
/// Flow:
///   1. Camera permission check.
///   2. Live camera + ML Kit face quality gate (centered, eyes open, frontal).
///   3. Auto-capture once the user holds steady for ~800ms.
///   4. Upload JPEG to /api/emotion/detect → fused HSEmotion + RoBERTa
///      result mapped to Sakinah's 15 emotions.
///   5. Confirmation sheet — accept the AI's read or pick manually.
///
/// Manual fallback (the 15-emotion grid) is *always* available via the
/// "Select Manually" button so the camera is never a hard dependency.
class EmotionCheckinScreen extends StatefulWidget {
  const EmotionCheckinScreen({super.key});

  @override
  State<EmotionCheckinScreen> createState() => _EmotionCheckinScreenState();
}

enum _Stage { askingPermission, camera, analyzing, manual, error }

class _EmotionCheckinScreenState extends State<EmotionCheckinScreen> {
  _Stage _stage = _Stage.askingPermission;
  String? _errorMessage;
  String? _detectedMood; // capitalized, e.g. "Anxious"
  // Held so we can log "AI said X but user picked Y" overrides into
  // Firestore as passive training data. Cleared after Confirm so users
  // who agree with the AI don't generate noise rows.
  EmotionDetectionResult? _lastAiSuggestion;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  /// Resolve the user's preference first, then either request camera
  /// permission or jump straight to the manual grid. Honoring the toggle
  /// up front means a privacy-conscious user never even sees a permission
  /// dialog.
  Future<void> _bootstrap() async {
    final cameraEnabled = await UserPreferencesService.cameraEmotionEnabled();
    if (!mounted) return;

    if (!cameraEnabled) {
      setState(() => _stage = _Stage.manual);
      return;
    }

    await _requestCameraPermission();
  }

  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    if (!mounted) return;

    if (status.isGranted) {
      setState(() => _stage = _Stage.camera);
    } else if (status.isPermanentlyDenied) {
      setState(() {
        _stage = _Stage.manual;
        _errorMessage =
            'Camera permission is blocked. You can still pick your emotion manually below.';
      });
    } else {
      // User denied — drop straight into manual mode without an error banner.
      setState(() => _stage = _Stage.manual);
    }
  }

  Future<void> _onFaceCaptured(Uint8List jpegBytes) async {
    setState(() => _stage = _Stage.analyzing);
    try {
      final result = await FaceEmotionService.detect(imageBytes: jpegBytes);
      if (!mounted) return;

      // No face detected at backend (despite ML Kit gate) — drop to manual.
      if (!result.faceDetected && result.sourcesUsed.isEmpty) {
        setState(() {
          _stage = _Stage.manual;
          _errorMessage =
              "I couldn't read your face clearly. Please pick your emotion below.";
        });
        return;
      }

      // Hold the suggestion so we can log it as training data if the user
      // ends up overriding the AI's pick (either via "No, I'm not" or by
      // picking a different chip in the manual grid).
      _lastAiSuggestion = result;
      _detectedMood = result.displayEmotion;
      _showConfirmationSheet(result);
    } catch (e, stack) {
      // Surface the real error so we can diagnose mismatched URLs, multipart
      // format issues, oversized images, etc. The phone log will show the
      // full message; the in-app banner shows the short form.
      debugPrint('[EmotionCheckin] detect failed: $e\n$stack');
      if (!mounted) return;
      setState(() {
        _stage = _Stage.manual;
        _errorMessage = 'Detection failed: $e';
      });
    }
  }

  void _onCameraError() {
    if (!mounted) return;
    setState(() {
      _stage = _Stage.manual;
      _errorMessage = 'Camera unavailable on this device.';
    });
  }

  // ─── Confirmation sheet ─────────────────────────────────────────────
  void _showConfirmationSheet(EmotionDetectionResult result) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "We sensed that you are feeling",
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Text(
              result.displayEmotion,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Color(0xFF064E3B),
              ),
            ),
            const SizedBox(height: 4),
            _ConfidenceBar(confidence: result.confidence),
            const SizedBox(height: 12),
            _SourceChip(result: result),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      setState(() {
                        _stage = _Stage.manual;
                        _detectedMood = null;
                      });
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: BorderSide(color: Colors.grey.shade300),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      "No, I'm not",
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      // User accepted the AI's suggestion — clear the held
                      // result so a later manual pick on the same screen
                      // (after they cancel back to manual) doesn't get
                      // misattributed as an "override".
                      _lastAiSuggestion = null;
                      _navigateToJournal();
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: const Color(0xFF15803D),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text("Confirm"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToJournal() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => JournalingScreen(mood: _detectedMood ?? "Neutral"),
      ),
    );
  }

  // ─── Build ───────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          _buildStageBody(),

          // Top bar — always visible.
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Text(
                    "Emotion Check-in",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
          ),

          // Bottom panel — camera CTA or manual grid.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomPanel(),
          ),
        ],
      ),
    );
  }

  Widget _buildStageBody() {
    switch (_stage) {
      case _Stage.askingPermission:
        return Container(
          color: Colors.grey.shade900,
          alignment: Alignment.center,
          child: const CircularProgressIndicator(color: Colors.white),
        );
      case _Stage.camera:
        return EmotionCameraView(
          onCaptured: _onFaceCaptured,
          onCameraError: _onCameraError,
        );
      case _Stage.analyzing:
        return Container(
          color: Colors.black,
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              CircularProgressIndicator(color: Color(0xFF15803D)),
              SizedBox(height: 24),
              Text(
                'Analysing your expression…',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
            ],
          ),
        );
      case _Stage.manual:
      case _Stage.error:
        return Container(color: Colors.grey.shade900);
    }
  }

  Widget _buildBottomPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_stage == _Stage.manual) ..._buildManualPanel(),
            if (_stage == _Stage.camera) ..._buildCameraPanel(),
            if (_stage == _Stage.analyzing) ..._buildAnalyzingPanel(),
            if (_stage == _Stage.askingPermission)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Requesting camera permission…',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildCameraPanel() {
    return [
      const Text(
        'Hold steady — auto-captures when ready',
        style: TextStyle(fontSize: 14, color: Colors.grey),
      ),
      const SizedBox(height: 12),
      TextButton.icon(
        onPressed: () => setState(() => _stage = _Stage.manual),
        icon: const Icon(Icons.touch_app, color: Color(0xFF15803D)),
        label: const Text(
          'Select Manually',
          style: TextStyle(color: Color(0xFF15803D)),
        ),
      ),
    ];
  }

  List<Widget> _buildAnalyzingPanel() {
    return const [
      Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'Connecting your face to your feelings…',
          style: TextStyle(color: Colors.grey),
        ),
      ),
    ];
  }

  List<Widget> _buildManualPanel() {
    return [
      if (_errorMessage != null) ...[
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline,
                  color: Colors.amber, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
      const Text(
        'How are you feeling?',
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Color(0xFF064E3B),
        ),
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: WrapAlignment.center,
        children: const [
          _MoodChipData('Happy', '😊'),
          _MoodChipData('Sad', '😔'),
          _MoodChipData('Anxious', '😰'),
          _MoodChipData('Angry', '😠'),
          _MoodChipData('Confused', '🤔'),
          _MoodChipData('Grateful', '🤲'),
          _MoodChipData('Lonely', '😞'),
          _MoodChipData('Stressed', '😫'),
          _MoodChipData('Fearful', '😨'),
          _MoodChipData('Guilty', '😣'),
          _MoodChipData('Hopeless', '😶'),
          _MoodChipData('Overwhelmed', '🥺'),
          _MoodChipData('Rejected', '💔'),
          _MoodChipData('Embarrassed', '😳'),
          _MoodChipData('Lost', '🌫️'),
        ].map((m) => _buildMoodChip(m.label, m.emoji)).toList(),
      ),
      const SizedBox(height: 12),
      if (_stage == _Stage.manual)
        TextButton.icon(
          onPressed: () async {
            // User wants to retry the camera path.
            final status = await Permission.camera.status;
            if (!mounted) return;
            if (status.isGranted) {
              setState(() {
                _errorMessage = null;
                _stage = _Stage.camera;
              });
            } else {
              await openAppSettings();
            }
          },
          icon: const Icon(Icons.camera_alt_outlined,
              color: Color(0xFF15803D)),
          label: const Text(
            'Use Camera Instead',
            style: TextStyle(color: Color(0xFF15803D)),
          ),
        ),
    ];
  }

  Widget _buildMoodChip(String label, String emoji) {
    return GestureDetector(
      onTap: () {
        // Log the manual pick as training data. If the AI had previously
        // suggested a different label this becomes an "override" row;
        // otherwise it's a "no AI suggestion" baseline row. Both useful.
        EmotionCorrectionLogger.logOverride(
          aiSuggestion: _lastAiSuggestion,
          chosenLabel: label,
        );
        _lastAiSuggestion = null;
        setState(() => _detectedMood = label);
        _navigateToJournal();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: Color(0xFF374151),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoodChipData {
  final String label;
  final String emoji;
  const _MoodChipData(this.label, this.emoji);
}

// ─── Confidence bar ─────────────────────────────────────────────────────
class _ConfidenceBar extends StatelessWidget {
  final double confidence;
  const _ConfidenceBar({required this.confidence});

  @override
  Widget build(BuildContext context) {
    final pct = (confidence * 100).clamp(0, 100).toInt();
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: confidence.clamp(0, 1),
            minHeight: 6,
            backgroundColor: Colors.grey.shade200,
            valueColor: const AlwaysStoppedAnimation<Color>(
              Color(0xFF15803D),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Confidence $pct%',
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ],
    );
  }
}

// ─── Source breakdown chip ──────────────────────────────────────────────
class _SourceChip extends StatelessWidget {
  final EmotionDetectionResult result;
  const _SourceChip({required this.result});

  @override
  Widget build(BuildContext context) {
    final parts = <String>[];
    if (result.facePredicted != null) {
      parts.add('Face: ${result.facePredicted}');
    }
    if (result.textPredicted != null) {
      parts.add('Text: ${result.textPredicted}');
    }
    if (parts.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        parts.join('  •  '),
        style: const TextStyle(
          color: Color(0xFF14532D),
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
