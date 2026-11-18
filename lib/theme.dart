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

/// Ilova ranglari logotipdagi to'q sariq (orange) rangga moslashtirilgan.
class AppColors {
  static const brandPrimary = Color(0xFFFA5602);
  static const brandCyan = Color(0xFFFF8A3D);
  static const brandIndigo = Color(0xFFC2410C);

  static const statusPresent = Color(0xFF10B981);
  static const statusLate = Color(0xFFF59E0B);
  static const statusAbsent = Color(0xFFEF4444);
  static const statusEarly = Color(0xFF8B5CF6);

  static const darkBg = Color(0xFF0C0907);
  static const darkCard = Color(0xFF1A1210);
  static const darkElevated = Color(0xFF251A16);
  static const darkBorder = Color(0xFF3A2822);
  static const darkText = Color(0xFFF8F5F2);
  static const darkSubtext = Color(0xFFB8A79E);
  static const darkMuted = Color(0xFF8C7A70);

  static const lightBg = Color(0xFFF7F1EC);
  static const lightCard = Color(0xFFFFFFFF);
  static const lightBorder = Color(0xFFE4D4CB);
  static const lightText = Color(0xFF201511);
  static const lightSubtext = Color(0xFF5E4A41);
  static const lightMuted = Color(0xFF9C8B82);
}

bool isDarkOf(BuildContext c) => Theme.of(c).brightness == Brightness.dark;

BoxDecoration appScreenBackground(bool isDark) => BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: isDark
            ? const [Color(0xFF1D0F08), Color(0xFF100A07), Color(0xFF070504)]
            : const [Color(0xFFFFF1E7), Color(0xFFF7F1EC), Color(0xFFFCFAF8)],
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
        fillColor: d ? AppColors.darkElevated : const Color(0xFFFCF7F3),
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
