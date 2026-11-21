import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme_colors.dart';
import 'app_typography.dart';

extension AppThemeContextX on BuildContext {
  AppThemeColors get themeColors => AppTheme.of(this);
  bool get isDarkTheme => themeColors.isDark;
}

class AppTheme {
  // Current active colors (updated synchronously on app build)
  static AppThemeColors _currentColors = AppThemeColors.peachy;
  static AppThemeColors get currentColors => _currentColors;

  static AppThemeColors of(BuildContext context) {
    return Theme.of(context).extension<AppThemeColors>() ?? _currentColors;
  }

  // Pre-configured Material 3 Theme instances for each of the 4 RupeeFlow themes
  static ThemeData get peachyTheme => _buildTheme(AppThemeColors.peachy);
  static ThemeData get lavenderTheme => _buildTheme(AppThemeColors.lavender);
  static ThemeData get midnightMochiTheme =>
      _buildTheme(AppThemeColors.midnightMochi);
  static ThemeData get rupeeFlowDarkTheme =>
      _buildTheme(AppThemeColors.rupeeFlowDark);

  // Backward compatibility getters
  static ThemeData get darkTheme => rupeeFlowDarkTheme;
  static ThemeData get lightTheme => peachyTheme;

  static ThemeData themeFor(String? themeId, [Brightness? systemBrightness]) {
    final colors = AppThemeColors.fromId(themeId, systemBrightness);
    _currentColors = colors;
    return _buildTheme(colors);
  }

  static ThemeData _buildTheme(AppThemeColors colors) {
    final isDark = colors.isDark;

    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: colors.background,
      colorScheme: ColorScheme(
        brightness: isDark ? Brightness.dark : Brightness.light,
        primary: colors.primaryAccent,
        onPrimary: colors.onPrimaryAccent,
        primaryContainer: colors.primaryAccentContainer,
        onPrimaryContainer: colors.textPrimary,
        secondary: colors.deepPeach,
        onSecondary: colors.onPrimaryAccent,
        secondaryContainer: colors.surfaceSecondary,
        onSecondaryContainer: colors.textPrimary,
        tertiary: colors.mint,
        onTertiary: colors.textPrimary,
        surface: colors.surface,
        onSurface: colors.textPrimary,
        surfaceVariant: colors.surfaceSecondary,
        onSurfaceVariant: colors.textSecondary,
        outline: colors.cardBorder,
        outlineVariant: colors.divider,
        error: colors.error,
        onError: colors.onError,
        errorContainer: colors.errorContainer,
        onErrorContainer: colors.error,
      ),
      textTheme: AppTypography.textThemeFor(colors),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.background,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: colors.textPrimary),
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: colors.textPrimary,
        ),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          systemNavigationBarColor: colors.surface,
          systemNavigationBarIconBrightness: isDark
              ? Brightness.light
              : Brightness.dark,
        ),
      ),
      cardTheme: CardThemeData(
        color: colors.surfaceSecondary,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.cardBorder, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceSecondary,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.primaryAccent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.error),
        ),
        hintStyle: TextStyle(color: colors.textTertiary, fontSize: 14),
        labelStyle: TextStyle(color: colors.textSecondary, fontSize: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.primaryAccent,
          foregroundColor: colors.onPrimaryAccent,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.textPrimary,
          side: BorderSide(color: colors.cardBorder),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colors.divider,
        thickness: 1,
        space: 1,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: colors.surface,
        selectedItemColor: colors.primaryAccent,
        unselectedItemColor: colors.textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        selectedLabelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surfaceElevated,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: colors.cardBorder),
        ),
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: colors.textPrimary,
        ),
        contentTextStyle: TextStyle(fontSize: 14, color: colors.textSecondary),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surfaceElevated,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      extensions: [colors],
    );
  }
}
