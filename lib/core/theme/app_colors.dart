import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'app_theme_colors.dart';

class AppColors {
  // Dynamic accessor to active RupeeFlow theme tokens
  static AppThemeColors get current => AppTheme.currentColors;
  static AppThemeColors of(BuildContext context) => AppTheme.of(context);

  // Primary & Accent (Teal / Emerald - fallback defaults)
  static const Color primaryTeal = Color(0xFF0D9488); // Teal 600
  static const Color primaryTealLight = Color(0xFF14B8A6); // Teal 500
  static const Color primaryTealDark = Color(0xFF0F766E); // Teal 700
  static const Color accentEmerald = Color(0xFF10B981); // Emerald 500

  // Dark Theme Surfaces (Deep Navy / Charcoal)
  static const Color darkBackground = Color(0xFF090D16);
  static const Color darkSurface = Color(0xFF111726);
  static const Color darkCard = Color(0xFF172033);
  static const Color darkCardElevated = Color(0xFF1E293B);
  static const Color darkBorder = Color(0xFF26334A);
  static const Color darkDivider = Color(0xFF1F2937);

  // Light Theme Surfaces (Clean / Warm White)
  static const Color lightBackground = Color(0xFFF8FAFC);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightCardElevated = Color(0xFFF1F5F9);
  static const Color lightBorder = Color(0xFFE2E8F0);
  static const Color lightDivider = Color(0xFFE5E7EB);

  // Text Colors - Dark
  static const Color darkTextPrimary = Color(0xFFF8FAFC);
  static const Color darkTextSecondary = Color(0xFF94A3B8);
  static const Color darkTextTertiary = Color(0xFF64748B);

  // Text Colors - Light
  static const Color lightTextPrimary = Color(0xFF0F172A);
  static const Color lightTextSecondary = Color(0xFF475569);
  static const Color lightTextTertiary = Color(0xFF94A3B8);

  // Status & Semantic Colors
  static const Color statusSuccess = Color(0xFF10B981); // Emerald
  static const Color statusWarning = Color(0xFFF59E0B); // Amber
  static const Color statusDanger = Color(0xFFEF4444); // Red
  static const Color statusInfo = Color(0xFF3B82F6); // Blue

  // Semantic Aliases
  static const Color errorRed = Color(0xFFEF4444);
  static const Color successGreen = Color(0xFF10B981);

  // Badges & Pastels
  static const Color badgeExpiredBg = Color(0x20EF4444);
  static const Color badgeExpiringSoonBg = Color(0x20F59E0B);
  static const Color badgeValidBg = Color(0x2010B981);
}
