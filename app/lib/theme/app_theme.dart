import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const primary = Color(0xFF15803D);
  static const primaryDeep = Color(0xFF064E3B);
  static const primaryTint = Color(0xFFDCFCE7);

  static const cream = Color(0xFFFDF8EC);
  static const sand = Color(0xFFE9DEC0);

  static const surface = Color(0xFFFFFFFF);
  static const background = Color(0xFFFAF9F6);

  static const ink = Color(0xFF1F2937);
  static const inkSoft = Color(0xFF374151);
  static const mutedInk = Color(0xFF6B7280);
  static const subtleInk = Color(0xFF9CA3AF);

  static const hairline = Color(0xFFE5E7EB);
  static const danger = Color(0xFFB91C1C);
}

class AppTheme {
  static TextTheme _textTheme(TextTheme base) {
    final body = GoogleFonts.plusJakartaSansTextTheme(base);
    return body.copyWith(
      displayLarge: GoogleFonts.fraunces(
        textStyle: base.displayLarge,
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
        height: 1.05,
      ),
      displayMedium: GoogleFonts.fraunces(
        textStyle: base.displayMedium,
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
        height: 1.05,
      ),
      displaySmall: GoogleFonts.fraunces(
        textStyle: base.displaySmall,
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
      ),
      headlineLarge: GoogleFonts.fraunces(
        textStyle: base.headlineLarge,
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
      ),
      headlineMedium: GoogleFonts.fraunces(
        textStyle: base.headlineMedium,
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
      ),
      headlineSmall: GoogleFonts.fraunces(
        textStyle: base.headlineSmall,
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
      ),
      titleLarge: GoogleFonts.fraunces(
        textStyle: base.titleLarge,
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
      ),
    );
  }

  static ThemeData get light {
    final base = ThemeData.light(useMaterial3: true);
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      surface: AppColors.surface,
    );

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.background,
      textTheme: _textTheme(base.textTheme),
      primaryTextTheme: _textTheme(base.primaryTextTheme),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.ink,
        surfaceTintColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: AppColors.primaryDeep),
        titleTextStyle: GoogleFonts.fraunces(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
      ),
      iconTheme: const IconThemeData(color: AppColors.inkSoft),
      dividerTheme: const DividerThemeData(
        color: AppColors.hairline,
        thickness: 1,
        space: 1,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            letterSpacing: 0.2,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class AppRadius {
  static const tile = 22.0;
  static const tileSmall = 16.0;
  static const pill = 999.0;
}

class AppShadows {
  static List<BoxShadow> soft = [
    BoxShadow(
      color: const Color(0xFF0F172A).withOpacity(0.04),
      blurRadius: 14,
      offset: const Offset(0, 6),
    ),
  ];

  static List<BoxShadow> hero = [
    BoxShadow(
      color: AppColors.primary.withOpacity(0.22),
      blurRadius: 24,
      offset: const Offset(0, 14),
    ),
  ];
}
