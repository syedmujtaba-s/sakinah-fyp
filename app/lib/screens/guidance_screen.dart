import 'package:flutter/material.dart';

class GuidanceScreen extends StatelessWidget {
  final String mood;
  final Map<String, dynamic> guidanceData;

  const GuidanceScreen({
    super.key,
    required this.mood,
    required this.guidanceData,
  });

  @override
  Widget build(BuildContext context) {
    final title = guidanceData['story_title'] ?? 'Guidance';
    final period = guidanceData['story_period'] ?? '';
    final seerahConnection = guidanceData['seerah_connection'] ?? '';
    final lessons = List<String>.from(guidanceData['lessons'] ?? []);
    final practicalAdvice = List<String>.from(guidanceData['practical_advice'] ?? []);
    final dua = guidanceData['dua'] ?? '';

    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          // Header
          SliverAppBar(
            expandedHeight: 200.0,
            floating: false,
            pinned: true,
            backgroundColor: const Color(0xFF15803D),
            flexibleSpace: FlexibleSpaceBar(
              title: Text(title, style: const TextStyle(fontSize: 16)),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF15803D), Color(0xFF14532D)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Center(
                  child: Icon(Icons.mosque_rounded, size: 80, color: Colors.white.withOpacity(0.2)),
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Mood + Period Tags
                  Wrap(
                    spacing: 8,
                    children: [
                      _buildTag("Feeling $mood", const Color(0xFFDCFCE7), const Color(0xFF15803D)),
                      if (period.isNotEmpty)
                        _buildTag(period, const Color(0xFFFEF3C7), const Color(0xFF92400E)),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Seerah Connection
                  const Text(
                    "The Seerah Connection",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    seerahConnection,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Color(0xFF4B5563),
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Lessons
                  if (lessons.isNotEmpty) ...[
                    _buildSectionCard(
                      icon: Icons.lightbulb_outline,
                      title: "Lessons",
                      items: lessons,
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Practical Advice
                  if (practicalAdvice.isNotEmpty) ...[
                    _buildSectionCard(
                      icon: Icons.checklist_rounded,
                      title: "Practical Advice",
                      items: practicalAdvice,
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Dua Card
                  if (dua.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFF15803D).withOpacity(0.3)),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF15803D).withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          const Text(
                            "Recommended Dua",
                            style: TextStyle(
                              fontSize: 14,
                              color: Color(0xFF6B7280),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            dua,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              fontStyle: FontStyle.italic,
                              color: Color(0xFF1F2937),
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 40),
                  Center(
                    child: TextButton(
                      onPressed: () {
                        Navigator.of(context).popUntil((route) => route.isFirst);
                      },
                      child: const Text("Return Home", style: TextStyle(color: Colors.grey)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTag(String text, Color bgColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required IconData icon,
    required String title,
    required List<String> items,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF15803D), size: 20),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF15803D))),
            ],
          ),
          const SizedBox(height: 12),
          ...items.map((item) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("  \u2022  ", style: TextStyle(color: Color(0xFF15803D), fontWeight: FontWeight.bold)),
                Expanded(
                  child: Text(
                    item,
                    style: const TextStyle(color: Color(0xFF374151), height: 1.4),
                  ),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }
}
