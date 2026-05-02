import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../theme/app_theme.dart';

class BentoTile extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? background;
  final Color? borderColor;
  final double radius;
  final VoidCallback? onTap;
  final int? animationIndex;
  final List<BoxShadow>? shadows;

  const BentoTile({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.background,
    this.borderColor,
    this.radius = AppRadius.tile,
    this.onTap,
    this.animationIndex,
    this.shadows,
  });

  @override
  Widget build(BuildContext context) {
    final tile = Material(
      color: background ?? AppColors.surface,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius),
        child: Ink(
          decoration: BoxDecoration(
            color: background ?? AppColors.surface,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: borderColor ?? AppColors.hairline,
              width: 1,
            ),
            boxShadow: shadows ?? AppShadows.soft,
          ),
          padding: padding,
          child: child,
        ),
      ),
    );

    if (animationIndex == null) return tile;

    return tile
        .animate(delay: (animationIndex! * 80).ms)
        .fadeIn(duration: 520.ms, curve: Curves.easeOutCubic)
        .slideY(
          begin: 0.05,
          end: 0,
          duration: 520.ms,
          curve: Curves.easeOutCubic,
        );
  }
}
