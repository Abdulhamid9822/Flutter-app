import 'package:flutter/material.dart';

class AppColors {
  static const bg = Color(0xFF0F0A08);
  static const surface = Color(0xFF1B1210);
  static const surfaceHigh = Color(0xFF261A16);
  static const border = Color(0xFF3A2822);
  static const primary = Color(0xFFFF7A33);
  static const primaryDark = Color(0xFFFA5602);
  static const accent = Color(0xFFFFB27A);
  static const text = Color(0xFFFFF6F1);
  static const subtext = Color(0xFFC6B2A7);
  static const muted = Color(0xFF96827A);
  static const green = Color(0xFF4ADE80);
  static const greenBg = Color(0xFF16352A);
  static const red = Color(0xFFF87171);
  static const redBg = Color(0xFF3A1D24);
  static const yellow = Color(0xFFFBBF24);
  static const yellowBg = Color(0xFF3A2F16);
}

ThemeData buildTheme() {
  final scheme = const ColorScheme.dark(
    primary: AppColors.primary,
    onPrimary: Color(0xFF2A0F05),
    secondary: AppColors.accent,
    onSecondary: Color(0xFF2A0F05),
    surface: AppColors.surface,
    onSurface: AppColors.text,
    error: AppColors.red,
    onError: Color(0xFF2A0B10),
    outline: AppColors.border,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      foregroundColor: AppColors.text,
      titleTextStyle: TextStyle(
        color: AppColors.text,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: const Color(0xFF2A0F05),
        disabledBackgroundColor: AppColors.surfaceHigh,
        disabledForegroundColor: AppColors.muted,
        minimumSize: const Size(64, 54),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.text,
        side: const BorderSide(color: AppColors.border),
        minimumSize: const Size(64, 52),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surfaceHigh,
      hintStyle: const TextStyle(color: AppColors.muted),
      labelStyle: const TextStyle(color: AppColors.subtext),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.red),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.border,
      thickness: 1,
      space: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.surfaceHigh,
      contentTextStyle: const TextStyle(color: AppColors.text),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: const TextStyle(
        color: AppColors.text,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
      contentTextStyle: const TextStyle(
        color: AppColors.subtext,
        fontSize: 15,
        height: 1.45,
      ),
    ),
    sliderTheme: base.sliderTheme.copyWith(
      activeTrackColor: AppColors.primary,
      inactiveTrackColor: AppColors.surfaceHigh,
      thumbColor: AppColors.primary,
      overlayColor: AppColors.primary.withValues(alpha: 0.15),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: AppColors.surfaceHigh,
      selectedColor: AppColors.primary,
      labelStyle: const TextStyle(color: AppColors.text),
      secondaryLabelStyle: const TextStyle(color: Color(0xFF2A0F05)),
      side: const BorderSide(color: AppColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

String formatWait(Duration duration) {
  final total = duration.inSeconds.clamp(0, 3600);
  final minutes = total ~/ 60;
  final seconds = total % 60;
  if (minutes <= 0) return '$seconds soniya';
  if (seconds == 0) return '$minutes daqiqa';
  return '$minutes daqiqa $seconds soniya';
}

/// Attendance ilovasi ichida FaceID ekranlari uchun tayyor tema.
final ThemeData faceIdTheme = buildTheme();
