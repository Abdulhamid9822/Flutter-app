import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeController {
  static final mode = ValueNotifier<ThemeMode>(ThemeMode.dark);

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    mode.value = p.getString('theme') == 'light' ? ThemeMode.light : ThemeMode.dark;
  }

  static Future<void> set(ThemeMode m) async {
    mode.value = m;
    final p = await SharedPreferences.getInstance();
    await p.setString('theme', m == ThemeMode.light ? 'light' : 'dark');
  }
}

class AppColors {
  static const brandPrimary = Color(0xFF0284C7);
  static const brandCyan = Color(0xFF06B6D4);
  static const brandIndigo = Color(0xFF6366F1);

  static const statusPresent = Color(0xFF10B981);
  static const statusLate = Color(0xFFF59E0B);
  static const statusAbsent = Color(0xFFEF4444);
  static const statusEarly = Color(0xFF8B5CF6);

  static const darkBg = Color(0xFF090E17);
  static const darkCard = Color(0xFF131F33);
  static const darkElevated = Color(0xFF17253D);
  static const darkBorder = Color(0xFF223654);
  static const darkText = Color(0xFFF8FAFC);
  static const darkSubtext = Color(0xFF94A3B8);
  static const darkMuted = Color(0xFF64748B);

  static const lightBg = Color(0xFFF1F5F9);
  static const lightCard = Color(0xFFFFFFFF);
  static const lightBorder = Color(0xFFCBD5E1);
  static const lightText = Color(0xFF0F172A);
  static const lightSubtext = Color(0xFF475569);
  static const lightMuted = Color(0xFF94A3B8);
}

bool isDarkOf(BuildContext c) => Theme.of(c).brightness == Brightness.dark;

BoxDecoration appScreenBackground(bool isDark) => BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isDark
            ? const [Color(0xFF0B1426), Color(0xFF080D18), Color(0xFF04060C)]
            : const [Color(0xFFEBF3FA), Color(0xFFF1F5F9), Color(0xFFF8FAFC)],
      ),
    );

Color appCardBackground(bool d) => d ? AppColors.darkCard : AppColors.lightCard;
Color appCardBorder(bool d) => d ? AppColors.darkBorder : AppColors.lightBorder;
Color appText(bool d) => d ? AppColors.darkText : AppColors.lightText;
Color appSubtext(bool d) => d ? AppColors.darkSubtext : AppColors.lightSubtext;
Color appMuted(bool d) => d ? AppColors.darkMuted : AppColors.lightMuted;

BoxDecoration cardDecoration(bool d) => BoxDecoration(
      color: appCardBackground(d),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: appCardBorder(d)),
    );

class AppTheme {
  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness b) {
    final d = b == Brightness.dark;
    final scheme = ColorScheme(
      brightness: b,
      primary: AppColors.brandPrimary,
      onPrimary: Colors.white,
      secondary: AppColors.brandCyan,
      onSecondary: Colors.white,
      error: AppColors.statusAbsent,
      onError: Colors.white,
      surface: appCardBackground(d),
      onSurface: appText(d),
    );
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c, width: w));
    return ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme,
      scaffoldBackgroundColor: d ? AppColors.darkBg : AppColors.lightBg,
      appBarTheme: AppBarTheme(
        backgroundColor: d ? AppColors.darkBg : AppColors.lightBg,
        foregroundColor: appText(d),
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: appCardBackground(d),
        indicatorColor: AppColors.brandPrimary.withValues(alpha: .2),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: d ? AppColors.darkElevated : const Color(0xFFF8FAFC),
        border: border(appCardBorder(d)),
        enabledBorder: border(appCardBorder(d)),
        focusedBorder: border(AppColors.brandPrimary, 2),
        labelStyle: TextStyle(color: appSubtext(d)),
        hintStyle: TextStyle(color: appMuted(d)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.brandPrimary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      dividerColor: appCardBorder(d),
      textTheme: (d ? ThemeData.dark() : ThemeData.light())
          .textTheme
          .apply(bodyColor: appText(d), displayColor: appText(d)),
    );
  }
}
