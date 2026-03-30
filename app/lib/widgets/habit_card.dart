import 'package:flutter/material.dart';
import 'weekly_dots.dart';

class HabitCard extends StatefulWidget {
  final String title;
  final String category;
  final IconData icon;
  final Color color;
  final int streak;
  final bool completedToday;
  final List<bool> weeklyStatus; // 7 bools, index 6 = today
  final VoidCallback onToggle;
  final VoidCallback onTap;

  const HabitCard({
    super.key,
    required this.title,
    required this.category,
    required this.icon,
    required this.color,
    required this.streak,
    required this.completedToday,
    required this.weeklyStatus,
    required this.onToggle,
    required this.onTap,
  });

  @override
  State<HabitCard> createState() => _HabitCardState();
}

class _HabitCardState extends State<HabitCard> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnim = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.3), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.3, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(parent: _animController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _handleToggle() {
    _animController.forward(from: 0);
    widget.onToggle();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Icon circle
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: widget.color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(widget.icon, color: widget.color, size: 22),
            ),
            const SizedBox(width: 14),

            // Title + category + weekly dots
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1F2937),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (widget.streak > 0) ...[
                        const SizedBox(width: 6),
                        const Text('🔥', style: TextStyle(fontSize: 12)),
                        const SizedBox(width: 2),
                        Text(
                          '${widget.streak}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFEA580C),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.category[0].toUpperCase() + widget.category.substring(1),
                    style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
                  ),
                  const SizedBox(height: 8),
                  WeeklyDots(days: widget.weeklyStatus),
                ],
              ),
            ),
            const SizedBox(width: 12),

            // Checkbox
            GestureDetector(
              onTap: _handleToggle,
              child: ScaleTransition(
                scale: _scaleAnim,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.completedToday
                        ? const Color(0xFF15803D)
                        : Colors.transparent,
                    border: Border.all(
                      color: widget.completedToday
                          ? const Color(0xFF15803D)
                          : const Color(0xFFD1D5DB),
                      width: 2,
                    ),
                  ),
                  child: widget.completedToday
                      ? const Icon(Icons.check, color: Colors.white, size: 18)
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
