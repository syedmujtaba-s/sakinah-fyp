import 'package:flutter/material.dart';
import 'journaling_screen.dart';

class EmotionCheckinScreen extends StatefulWidget {
  const EmotionCheckinScreen({super.key});

  @override
  State<EmotionCheckinScreen> createState() => _EmotionCheckinScreenState();
}

class _EmotionCheckinScreenState extends State<EmotionCheckinScreen> {
  bool _isScanning = false;
  String? _detectedMood;
  bool _showManualSelection = false;

  // Mock function to simulate AI detection delay
  void _startScan() {
    setState(() {
      _isScanning = true;
      _showManualSelection = false;
    });

    // Simulate 2 second delay then "detect" a mood
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _isScanning = false;
          // Randomly picking a mood for demo purposes
          _detectedMood = "Anxious"; 
        });
        _showConfirmationDialog();
      }
    });
  }

  void _showConfirmationDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
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
                _detectedMood ?? "Neutral",
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF064E3B),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        setState(() {
                          _showManualSelection = true;
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
                      child: const Text("No, I'm not", style: TextStyle(color: Colors.grey)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context); // Close sheet
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
              )
            ],
          ),
        );
      },
    );
  }

  void _navigateToJournal() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => JournalingScreen(mood: _detectedMood ?? "Neutral"),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Camera View Placeholder
          SizedBox.expand(
            child: Container(
              color: Colors.grey.shade900,
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.camera_alt_rounded, color: Colors.white24, size: 60),
                    SizedBox(height: 16),
                    Text(
                      "Camera Preview Simulation",
                      style: TextStyle(color: Colors.white24),
                    )
                  ],
                ),
              ),
            ),
          ),

          // 2. Overlay Frame
          Center(
            child: Container(
              width: 280,
              height: 380,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white.withOpacity(0.5), width: 2),
                borderRadius: BorderRadius.circular(200), // Oval shape for face
              ),
            ),
          ),

          // 3. UI Controls
          SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
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
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 48), // Balance
                    ],
                  ),
                ),
                
                const Spacer(),

                // Bottom Panel
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_showManualSelection) ...[
                        const Text(
                          "How are you feeling?",
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF064E3B)),
                        ),
                        const SizedBox(height: 20),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          alignment: WrapAlignment.center,
                          children: [
                            _buildMoodChip("Happy", "😊"),
                            _buildMoodChip("Sad", "😔"),
                            _buildMoodChip("Anxious", "😰"),
                            _buildMoodChip("Angry", "😠"),
                            _buildMoodChip("Confused", "🤔"),
                            _buildMoodChip("Grateful", "🤲"),
                            _buildMoodChip("Lonely", "😞"),
                            _buildMoodChip("Stressed", "😫"),
                            _buildMoodChip("Fearful", "😨"),
                            _buildMoodChip("Guilty", "😣"),
                            _buildMoodChip("Hopeless", "😶"),
                            _buildMoodChip("Overwhelmed", "🥺"),
                            _buildMoodChip("Rejected", "💔"),
                            _buildMoodChip("Embarrassed", "😳"),
                            _buildMoodChip("Lost", "🌫️"),
                          ],
                        ),
                      ] else ...[
                         Text(
                          _isScanning ? "Scanning expression..." : "Align your face",
                          style: const TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                        const SizedBox(height: 24),
                        GestureDetector(
                          onTap: _isScanning ? null : _startScan,
                          child: Container(
                            width: 70,
                            height: 70,
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0xFF15803D), width: 4),
                            ),
                            child: Container(
                              decoration: const BoxDecoration(
                                color: Color(0xFF15803D),
                                shape: BoxShape.circle,
                              ),
                              child: _isScanning
                                  ? const Padding(
                                      padding: EdgeInsets.all(16.0),
                                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                    )
                                  : const Icon(Icons.face_rounded, color: Colors.white, size: 32),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _showManualSelection = true;
                            });
                          },
                          child: const Text("Select Manually", style: TextStyle(color: Color(0xFF15803D))),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMoodChip(String label, String emoji) {
    return GestureDetector(
      onTap: () {
        setState(() => _detectedMood = label);
        _navigateToJournal();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
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
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF374151))),
          ],
        ),
      ),
    );
  }
}