import 'package:flutter/material.dart';

// =============================================================================
// RUPEEFLOW DESIGN SYSTEM — SEMANTIC THEME TOKENS
// =============================================================================

@immutable
class AppThemeColors extends ThemeExtension<AppThemeColors> {
  final String id;
  final String name;
  final String subtitle;
  final bool isDark;

  // Surfaces & Backgrounds
  final Color background;
  final Color surface;
  final Color surfaceSecondary;
  final Color surfaceElevated;
  final Color cardBorder;
  final Color divider;

  // Typography
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  // Primary Accent & Containers
  final Color primaryAccent;
  final Color primaryAccentContainer;
  final Color onPrimaryAccent;

  // Semantic Feedback Tokens
  final Color success;
  final Color successContainer;
  final Color onSuccess;
  final Color error;
  final Color errorContainer;
  final Color onError;
  final Color warning;
  final Color warningContainer;
  final Color onWarning;
  final Color info;
  final Color infoContainer;

  // RupeeFlow Pastel Accent Palette
  final Color primaryPeach;
  final Color deepPeach;
  final Color accentPink;
  final Color softLavender;
  final Color mint;
  final Color warmYellow;

  // Thematic Gradients & Shadow
  final LinearGradient heroGradient;
  final LinearGradient cardGradient;
  final Color heroShadow;
  final List<Color> paletteColors;

  const AppThemeColors({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.isDark,
    required this.background,
    required this.surface,
    required this.surfaceSecondary,
    required this.surfaceElevated,
    required this.cardBorder,
    required this.divider,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.primaryAccent,
    required this.primaryAccentContainer,
    required this.onPrimaryAccent,
    required this.success,
    required this.successContainer,
    required this.onSuccess,
    required this.error,
    required this.errorContainer,
    required this.onError,
    required this.warning,
    required this.warningContainer,
    required this.onWarning,
    required this.info,
    required this.infoContainer,
    required this.primaryPeach,
    required this.deepPeach,
    required this.accentPink,
    required this.softLavender,
    required this.mint,
    required this.warmYellow,
    required this.heroGradient,
    required this.cardGradient,
    required this.heroShadow,
    required this.paletteColors,
  });

  // Semantic Aliases
  Color get cardBackground => surfaceSecondary;
  Color get cardElevated => surfaceElevated;
  Color get accentSecondary => accentPink;
  Color get accentContainer => primaryAccentContainer;
  Color get incomeGreen => success;
  Color get expenseRed => error;
  Color get textMuted => textTertiary;
  Color get inputBackground => isDark ? surfaceSecondary : surface;

  List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: (isDark ? Colors.black : heroShadow).withOpacity(0.06),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];

  List<BoxShadow> get floatingShadow => [
    BoxShadow(
      color: (isDark ? Colors.black : heroShadow).withOpacity(0.12),
      blurRadius: 16,
      offset: const Offset(0, 6),
    ),
  ];

  // ===========================================================================
  // 1. PEACHY COZY THEME (RupeeFlow Default)
  // Warm, cute, minimal, cream backgrounds & chocolate-brown typography
  // ===========================================================================
  static const AppThemeColors peachy = AppThemeColors(
    id: 'peachy',
    name: 'Peachy Cozy',
    subtitle: 'Warm, cute, minimal and modern peach aesthetic',
    isDark: false,
    background: Color(0xFFFFF8F1),
    surface: Color(0xFFFFFFFF),
    surfaceSecondary: Color(0xFFFFF0E6),
    surfaceElevated: Color(0xFFFFFFFF),
    cardBorder: Color(0xFFF0DDD2),
    divider: Color(0xFFF0DDD2),
    textPrimary: Color(0xFF4A3028),
    textSecondary: Color(0xFF92766B),
    textTertiary: Color(0xFFB8A298),
    primaryAccent: Color(0xFFF58B72),
    primaryAccentContainer: Color(0xFFFFF0E6),
    onPrimaryAccent: Color(0xFFFFFFFF),
    success: Color(0xFF268B65),
    successContainer: Color(0xFFD8F3E5),
    onSuccess: Color(0xFFFFFFFF),
    error: Color(0xFFD95757),
    errorContainer: Color(0xFFFDE8E8),
    onError: Color(0xFFFFFFFF),
    warning: Color(0xFFFFD98E),
    warningContainer: Color(0xFFFFF5DC),
    onWarning: Color(0xFF4A3028),
    info: Color(0xFFDCCBFA),
    infoContainer: Color(0xFFF4EEFE),
    primaryPeach: Color(0xFFFFAD91),
    deepPeach: Color(0xFFF58B72),
    accentPink: Color(0xFFF5A6B8),
    softLavender: Color(0xFFDCCBFA),
    mint: Color(0xFFB9E5D2),
    warmYellow: Color(0xFFFFD98E),
    heroGradient: LinearGradient(
      colors: [Color(0xFFF58B72), Color(0xFFFFAD91)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    cardGradient: LinearGradient(
      colors: [Color(0xFFFFF0E6), Color(0xFFFFFFFF)],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    ),
    heroShadow: Color(0x40F58B72),
    paletteColors: [
      Color(0xFFFFF8F1),
      Color(0xFFFFAD91),
      Color(0xFFF58B72),
      Color(0xFF268B65),
      Color(0xFF4A3028),
    ],
  );

  // ===========================================================================
  // 2. LAVENDER DREAM THEME
  // Soft lavender, pastel purple, lilac & tranquil serenity
  // ===========================================================================
  static const AppThemeColors lavender = AppThemeColors(
    id: 'lavender',
    name: 'Lavender Dream',
    subtitle: 'Soft lavender, pastel purple, lilac & tranquil serenity',
    isDark: false,
    background: Color(0xFFF7F3FC),
    surface: Color(0xFFFFFFFF),
    surfaceSecondary: Color(0xFFEEE7F7),
    surfaceElevated: Color(0xFFFFFFFF),
    cardBorder: Color(0xFFE2D8EF),
    divider: Color(0xFFE2D8EF),
    textPrimary: Color(0xFF342A45),
    textSecondary: Color(0xFF80748F),
    textTertiary: Color(0xFFA69BB5),
    primaryAccent: Color(0xFF9274C8),
    primaryAccentContainer: Color(0xFFEEE7F7),
    onPrimaryAccent: Color(0xFFFFFFFF),
    success: Color(0xFF269B78),
    successContainer: Color(0xFFD8F3E9),
    onSuccess: Color(0xFFFFFFFF),
    error: Color(0xFFD95770),
    errorContainer: Color(0xFFFCE8ED),
    onError: Color(0xFFFFFFFF),
    warning: Color(0xFFD99B49),
    warningContainer: Color(0xFFFCF3E5),
    onWarning: Color(0xFFFFFFFF),
    info: Color(0xFFB9A4E8),
    infoContainer: Color(0xFFF0EAFC),
    primaryPeach: Color(0xFFB9A4E8),
    deepPeach: Color(0xFF9274C8),
    accentPink: Color(0xFFE6BCEB),
    softLavender: Color(0xFFC9B9E8),
    mint: Color(0xFF269B78),
    warmYellow: Color(0xFFD99B49),
    heroGradient: LinearGradient(
      colors: [Color(0xFF9274C8), Color(0xFFB9A4E8)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    cardGradient: LinearGradient(
      colors: [Color(0xFFEEE7F7), Color(0xFFFFFFFF)],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    ),
    heroShadow: Color(0x409274C8),
    paletteColors: [
      Color(0xFFF7F3FC),
      Color(0xFF9274C8),
      Color(0xFFB9A4E8),
      Color(0xFFE6BCEB),
      Color(0xFF342A45),
    ],
  );

  // ===========================================================================
  // 3. MIDNIGHT MOCHI THEME
  // Deep midnight purple, dark plum surfaces & lavender glow
  // ===========================================================================
  static const AppThemeColors midnightMochi = AppThemeColors(
    id: 'midnight_mochi',
    name: 'Midnight Mochi',
    subtitle: 'Deep midnight purple, dark plum surfaces & lavender glow',
    isDark: true,
    background: Color(0xFF100E19),
    surface: Color(0xFF191626),
    surfaceSecondary: Color(0xFF252036),
    surfaceElevated: Color(0xFF211D31),
    cardBorder: Color(0xFF393149),
    divider: Color(0x33B6ADC9),
    textPrimary: Color(0xFFF5F0FC),
    textSecondary: Color(0xFFB6ADC9),
    textTertiary: Color(0xFF867C99),
    primaryAccent: Color(0xFFB49AEF),
    primaryAccentContainer: Color(0xFF252036),
    onPrimaryAccent: Color(0xFF100E19),
    success: Color(0xFF55C99B),
    successContainer: Color(0x2655C99B),
    onSuccess: Color(0xFF100E19),
    error: Color(0xFFF07891),
    errorContainer: Color(0x26F07891),
    onError: Color(0xFFF5F0FC),
    warning: Color(0xFFE7B66C),
    warningContainer: Color(0x26E7B66C),
    onWarning: Color(0xFF100E19),
    info: Color(0xFFD0BDF8),
    infoContainer: Color(0x26D0BDF8),
    primaryPeach: Color(0xFFD0BDF8),
    deepPeach: Color(0xFFB49AEF),
    accentPink: Color(0xFFF0A9D5),
    softLavender: Color(0xFF9576CB),
    mint: Color(0xFF55C99B),
    warmYellow: Color(0xFFE7B66C),
    heroGradient: LinearGradient(
      colors: [Color(0xFF252036), Color(0xFF191626)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    cardGradient: LinearGradient(
      colors: [Color(0xFF252036), Color(0xFF191626)],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    ),
    heroShadow: Color(0x38B49AEF),
    paletteColors: [
      Color(0xFF100E19),
      Color(0xFF191626),
      Color(0xFFB49AEF),
      Color(0xFFF0A9D5),
      Color(0xFFF5F0FC),
    ],
  );

  // ===========================================================================
  // 4. EXISTING RUPEEFLOW THEME (Midnight Dark)
  // High-contrast dark mode with electric blue neon accents
  // ===========================================================================
  static const AppThemeColors rupeeFlowDark = AppThemeColors(
    id: 'dark',
    name: 'RupeeFlow Theme',
    subtitle: 'High-contrast dark mode with electric blue neon accents',
    isDark: true,
    background: Color(0xFF0A0E17),
    surface: Color(0xFF111827),
    surfaceSecondary: Color(0xFF1E293B),
    surfaceElevated: Color(0xFF1E293B),
    cardBorder: Color(0x3394A3B8),
    divider: Color(0x1A94A3B8),
    textPrimary: Color(0xFFF8FAFC),
    textSecondary: Color(0xFF94A3B8),
    textTertiary: Color(0xFF64748B),
    primaryAccent: Color(0xFF3B82F6),
    primaryAccentContainer: Color(0xFF1E293B),
    onPrimaryAccent: Color(0xFFFFFFFF),
    success: Color(0xFF10B981),
    successContainer: Color(0x2610B981),
    onSuccess: Color(0xFF0A0E17),
    error: Color(0xFFEF4444),
    errorContainer: Color(0x26EF4444),
    onError: Color(0xFFF8FAFC),
    warning: Color(0xFFF59E0B),
    warningContainer: Color(0x26F59E0B),
    onWarning: Color(0xFF0A0E17),
    info: Color(0xFF06B6D4),
    infoContainer: Color(0x2606B6D4),
    primaryPeach: Color(0xFF60A5FA),
    deepPeach: Color(0xFF3B82F6),
    accentPink: Color(0xFFEC4899),
    softLavender: Color(0xFF8B5CF6),
    mint: Color(0xFF10B981),
    warmYellow: Color(0xFFF59E0B),
    heroGradient: LinearGradient(
      colors: [Color(0xFF1E3A8A), Color(0xFF0A0E17)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    cardGradient: LinearGradient(
      colors: [Color(0xFF1E293B), Color(0xFF111827)],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    ),
    heroShadow: Color(0x403B82F6),
    paletteColors: [
      Color(0xFF0A0E17),
      Color(0xFF111827),
      Color(0xFF3B82F6),
      Color(0xFF10B981),
      Color(0xFFF8FAFC),
    ],
  );

  static const List<AppThemeColors> allThemes = [
    peachy,
    lavender,
    midnightMochi,
    rupeeFlowDark,
  ];

  static AppThemeColors fromId(String? id, [Brightness? systemBrightness]) {
    final normalized = (id ?? '').toLowerCase().trim();
    switch (normalized) {
      case 'peachy':
      case 'light':
        return peachy;
      case 'lavender':
        return lavender;
      case 'midnight_mochi':
      case 'mochi':
        return midnightMochi;
      case 'dark':
      case 'rupeeflow_dark':
      case 'midnight_dark':
        return rupeeFlowDark;
      case 'system':
        return (systemBrightness == Brightness.dark) ? rupeeFlowDark : peachy;
      default:
        return peachy;
    }
  }

  @override
  ThemeExtension<AppThemeColors> copyWith({
    String? id,
    String? name,
    String? subtitle,
    bool? isDark,
    Color? background,
    Color? surface,
    Color? surfaceSecondary,
    Color? surfaceElevated,
    Color? cardBorder,
    Color? divider,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? primaryAccent,
    Color? primaryAccentContainer,
    Color? onPrimaryAccent,
    Color? success,
    Color? successContainer,
    Color? onSuccess,
    Color? error,
    Color? errorContainer,
    Color? onError,
    Color? warning,
    Color? warningContainer,
    Color? onWarning,
    Color? info,
    Color? infoContainer,
    Color? primaryPeach,
    Color? deepPeach,
    Color? accentPink,
    Color? softLavender,
    Color? mint,
    Color? warmYellow,
    LinearGradient? heroGradient,
    LinearGradient? cardGradient,
    Color? heroShadow,
    List<Color>? paletteColors,
  }) {
    return AppThemeColors(
      id: id ?? this.id,
      name: name ?? this.name,
      subtitle: subtitle ?? this.subtitle,
      isDark: isDark ?? this.isDark,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceSecondary: surfaceSecondary ?? this.surfaceSecondary,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      cardBorder: cardBorder ?? this.cardBorder,
      divider: divider ?? this.divider,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      primaryAccent: primaryAccent ?? this.primaryAccent,
      primaryAccentContainer:
          primaryAccentContainer ?? this.primaryAccentContainer,
      onPrimaryAccent: onPrimaryAccent ?? this.onPrimaryAccent,
      success: success ?? this.success,
      successContainer: successContainer ?? this.successContainer,
      onSuccess: onSuccess ?? this.onSuccess,
      error: error ?? this.error,
      errorContainer: errorContainer ?? this.errorContainer,
      onError: onError ?? this.onError,
      warning: warning ?? this.warning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarning: onWarning ?? this.onWarning,
      info: info ?? this.info,
      infoContainer: infoContainer ?? this.infoContainer,
      primaryPeach: primaryPeach ?? this.primaryPeach,
      deepPeach: deepPeach ?? this.deepPeach,
      accentPink: accentPink ?? this.accentPink,
      softLavender: softLavender ?? this.softLavender,
      mint: mint ?? this.mint,
      warmYellow: warmYellow ?? this.warmYellow,
      heroGradient: heroGradient ?? this.heroGradient,
      cardGradient: cardGradient ?? this.cardGradient,
      heroShadow: heroShadow ?? this.heroShadow,
      paletteColors: paletteColors ?? this.paletteColors,
    );
  }

  @override
  ThemeExtension<AppThemeColors> lerp(
    ThemeExtension<AppThemeColors>? other,
    double t,
  ) {
    if (other is! AppThemeColors) return this;
    return AppThemeColors(
      id: t < 0.5 ? id : other.id,
      name: t < 0.5 ? name : other.name,
      subtitle: t < 0.5 ? subtitle : other.subtitle,
      isDark: t < 0.5 ? isDark : other.isDark,
      background: Color.lerp(background, other.background, t) ?? background,
      surface: Color.lerp(surface, other.surface, t) ?? surface,
      surfaceSecondary:
          Color.lerp(surfaceSecondary, other.surfaceSecondary, t) ??
          surfaceSecondary,
      surfaceElevated:
          Color.lerp(surfaceElevated, other.surfaceElevated, t) ??
          surfaceElevated,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t) ?? cardBorder,
      divider: Color.lerp(divider, other.divider, t) ?? divider,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t) ?? textPrimary,
      textSecondary:
          Color.lerp(textSecondary, other.textSecondary, t) ?? textSecondary,
      textTertiary:
          Color.lerp(textTertiary, other.textTertiary, t) ?? textTertiary,
      primaryAccent:
          Color.lerp(primaryAccent, other.primaryAccent, t) ?? primaryAccent,
      primaryAccentContainer:
          Color.lerp(primaryAccentContainer, other.primaryAccentContainer, t) ??
          primaryAccentContainer,
      onPrimaryAccent:
          Color.lerp(onPrimaryAccent, other.onPrimaryAccent, t) ??
          onPrimaryAccent,
      success: Color.lerp(success, other.success, t) ?? success,
      successContainer:
          Color.lerp(successContainer, other.successContainer, t) ??
          successContainer,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t) ?? onSuccess,
      error: Color.lerp(error, other.error, t) ?? error,
      errorContainer:
          Color.lerp(errorContainer, other.errorContainer, t) ?? errorContainer,
      onError: Color.lerp(onError, other.onError, t) ?? onError,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
      warningContainer:
          Color.lerp(warningContainer, other.warningContainer, t) ??
          warningContainer,
      onWarning: Color.lerp(onWarning, other.onWarning, t) ?? onWarning,
      info: Color.lerp(info, other.info, t) ?? info,
      infoContainer:
          Color.lerp(infoContainer, other.infoContainer, t) ?? infoContainer,
      primaryPeach:
          Color.lerp(primaryPeach, other.primaryPeach, t) ?? primaryPeach,
      deepPeach: Color.lerp(deepPeach, other.deepPeach, t) ?? deepPeach,
      accentPink: Color.lerp(accentPink, other.accentPink, t) ?? accentPink,
      softLavender:
          Color.lerp(softLavender, other.softLavender, t) ?? softLavender,
      mint: Color.lerp(mint, other.mint, t) ?? mint,
      warmYellow: Color.lerp(warmYellow, other.warmYellow, t) ?? warmYellow,
      heroGradient: t < 0.5 ? heroGradient : other.heroGradient,
      cardGradient: t < 0.5 ? cardGradient : other.cardGradient,
      heroShadow: Color.lerp(heroShadow, other.heroShadow, t) ?? heroShadow,
      paletteColors: t < 0.5 ? paletteColors : other.paletteColors,
    );
  }
}
