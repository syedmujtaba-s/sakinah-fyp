import 'package:flutter/material.dart';

class WeeklyDots extends StatelessWidget {
  /// List of 7 booleans (index 0 = 6 days ago, index 6 = today).
  /// true = completed, false = not completed.
  final List<bool> days;

  const WeeklyDots({super.key, required this.days});

  @override
  Widget build(BuildContext context) {
    final labels = _getDayLabels();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(7, (i) {
        final isToday = i == 6;
        final completed = i < days.length && days[i];
        final dotSize = isToday ? 10.0 : 8.0;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2.5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: dotSize,
                height: dotSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: completed ? const Color(0xFF15803D) : Colors.transparent,
                  border: Border.all(
                    color: completed
                        ? const Color(0xFF15803D)
                        : isToday
                            ? const Color(0xFF9CA3AF)
                            : const Color(0xFFD1D5DB),
                    width: isToday ? 2 : 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                labels[i],
                style: TextStyle(
                  fontSize: 8,
                  color: isToday ? const Color(0xFF374151) : const Color(0xFF9CA3AF),
                  fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  List<String> _getDayLabels() {
    const dayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final labels = <String>[];
    for (int i = 6; i >= 0; i--) {
      final day = DateTime.now().subtract(Duration(days: i));
      labels.add(dayLetters[day.weekday - 1]);
    }
    return labels;
  }
}
