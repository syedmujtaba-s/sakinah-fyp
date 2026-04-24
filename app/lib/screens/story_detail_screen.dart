import 'package:flutter/material.dart';

class StoryDetailScreen extends StatelessWidget {
  final String title;
  final String period;
  final String summary;
  final String fullStory;
  final List<String> lessons;

  const StoryDetailScreen({
    super.key,
    required this.title,
    required this.period,
    required this.summary,
    required this.fullStory,
    this.lessons = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 180,
            pinned: true,
            backgroundColor: const Color(0xFF15803D),
            iconTheme: const IconThemeData(color: Colors.white),
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsetsDirectional.only(start: 56, bottom: 16, end: 16),
              title: Text(
                title,
                style: const TextStyle(fontSize: 14, color: Colors.white),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF15803D), Color(0xFF14532D)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: Center(
                  child: Icon(
                    Icons.menu_book_rounded,
                    size: 72,
                    color: Colors.white.withOpacity(0.2),
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (period.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        period,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF92400E),
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  if (summary.isNotEmpty) ...[
                    const Text(
                      'Summary',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6B7280),
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      summary,
                      style: const TextStyle(
                        fontSize: 15,
                        color: Color(0xFF374151),
                        height: 1.5,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Divider(color: Color(0xFFE5E7EB), height: 1),
                    const SizedBox(height: 20),
                  ],
                  const Text(
                    'The Full Story',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    fullStory.isNotEmpty
                        ? fullStory
                        : 'This story\'s full narrative is not available.',
                    style: const TextStyle(
                      fontSize: 16,
                      color: Color(0xFF4B5563),
                      height: 1.7,
                    ),
                  ),
                  if (lessons.isNotEmpty) ...[
                    const SizedBox(height: 28),
                    const Divider(color: Color(0xFFE5E7EB), height: 1),
                    const SizedBox(height: 20),
                    Row(
                      children: const [
                        Icon(Icons.lightbulb_outline, size: 20, color: Color(0xFF15803D)),
                        SizedBox(width: 8),
                        Text(
                          'Core Lessons from This Story',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF15803D),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...lessons.map((l) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(top: 2),
                                child: Text(' • ',
                                    style: TextStyle(
                                        color: Color(0xFF15803D),
                                        fontWeight: FontWeight.bold)),
                              ),
                              Expanded(
                                child: Text(
                                  l,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Color(0xFF374151),
                                    height: 1.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )),
                  ],
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
