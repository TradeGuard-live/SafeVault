import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../../core/widgets/rupee_bunny_mascot.dart';
import '../../authentication/presentation/auth_providers.dart';

class ThemeSelectionScreen extends ConsumerWidget {
  const ThemeSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final activeColors = context.themeColors;
    final currentThemeId = settings.themeMode;

    return Scaffold(
      backgroundColor: activeColors.background,
      appBar: AppBar(
        title: const Text('Theme & Aesthetics'),
        backgroundColor: activeColors.background,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        children: [
          // Cute Bunny Header Card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: activeColors.heroGradient,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: activeColors.heroShadow,
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                const RupeeBunnyMascot(
                  pose: MascotPose.celebration,
                  size: 64,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'RupeeFlow Design System',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Choose from 4 handcrafted aesthetics. Themes update instantly across every vault screen.',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          Text(
            'SELECT THEME',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: activeColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),

          // 1. Peachy Cozy (Active / Default)
          _ThemePreviewCard(
            theme: AppThemeColors.peachy,
            isSelected: currentThemeId == 'peachy' || currentThemeId == 'light' || currentThemeId.isEmpty,
            onSelect: () => _selectTheme(ref, 'peachy'),
          ),
          const SizedBox(height: 14),

          // 2. Lavender Dream
          _ThemePreviewCard(
            theme: AppThemeColors.lavender,
            isSelected: currentThemeId == 'lavender',
            onSelect: () => _selectTheme(ref, 'lavender'),
          ),
          const SizedBox(height: 14),

          // 3. Midnight Mochi
          _ThemePreviewCard(
            theme: AppThemeColors.midnightMochi,
            isSelected: currentThemeId == 'midnight_mochi' || currentThemeId == 'mochi',
            onSelect: () => _selectTheme(ref, 'midnight_mochi'),
          ),
          const SizedBox(height: 14),

          // 4. RupeeFlow Theme (Midnight Dark)
          _ThemePreviewCard(
            theme: AppThemeColors.rupeeFlowDark,
            isSelected: currentThemeId == 'dark' || currentThemeId == 'rupeeflow_dark',
            onSelect: () => _selectTheme(ref, 'dark'),
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }

  void _selectTheme(WidgetRef ref, String themeId) {
    HapticFeedback.lightImpact();
    ref.read(settingsProvider.notifier).setThemeMode(themeId);
  }
}

class _ThemePreviewCard extends StatelessWidget {
  final AppThemeColors theme;
  final bool isSelected;
  final VoidCallback onSelect;

  const _ThemePreviewCard({
    required this.theme,
    required this.isSelected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final activeColors = context.themeColors;

    return InkWell(
      onTap: onSelect,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: activeColors.surfaceSecondary,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? theme.primaryAccent : activeColors.cardBorder,
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: theme.primaryAccent.withOpacity(0.2),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row: Title, Badge, Radio/Check
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            theme.name,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: activeColors.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: theme.isDark
                                  ? const Color(0xFF252036)
                                  : const Color(0xFFFFF0E6),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              theme.isDark ? 'Dark Mode' : 'Light Mode',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: theme.isDark
                                    ? const Color(0xFFB49AEF)
                                    : const Color(0xFFF58B72),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        theme.subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: activeColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? theme.primaryAccent : Colors.transparent,
                    border: Border.all(
                      color: isSelected ? theme.primaryAccent : activeColors.cardBorder,
                      width: 2,
                    ),
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Palette Swatches Row
            Row(
              children: [
                Text(
                  'Palette:',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: activeColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 8),
                for (final color in theme.paletteColors) ...[
                  Container(
                    width: 20,
                    height: 20,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.black.withOpacity(0.12),
                        width: 1,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),

            // Live Mini Component Preview Box
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.background,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: theme.cardBorder),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.primaryAccentContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.shield_rounded,
                      color: theme.primaryAccent,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Encrypted Document Vault',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: theme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'AES-256-GCM + 2FA Protected',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.successContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'SECURE',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: theme.success,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

