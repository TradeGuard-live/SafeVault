import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../authentication/presentation/auth_providers.dart';

class GeneralSettingsScreen extends ConsumerWidget {
  const GeneralSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.themeColors;
    final settings = ref.watch(settingsProvider);
    final activeTheme = AppThemeColors.fromId(settings.themeMode);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text(
          'Settings',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
        backgroundColor: colors.background,
        elevation: 0,
        iconTheme: IconThemeData(color: colors.textPrimary),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        children: [
          // Security Navigation
          _buildCard(context, colors, [
            ListTile(
              leading: Icon(
                Icons.security_rounded,
                color: colors.primaryAccent,
              ),
              title: Text(
                'Security & Master Key',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              subtitle: Text(
                '2FA, PIN, Biometrics, Auto-Lock, FLAG_SECURE',
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
              ),
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: colors.textSecondary,
              ),
              onTap: () => context.push('/security-settings'),
            ),
          ]),
          const SizedBox(height: 16),

          // RupeeFlow Appearance & 4-Theme System
          _buildCard(context, colors, [
            ListTile(
              leading: Icon(
                Icons.palette_outlined,
                color: colors.primaryAccent,
              ),
              title: Text(
                'Appearance Theme',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              subtitle: Text(
                '${activeTheme.name} • ${activeTheme.subtitle}',
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: activeTheme.primaryAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colors.textSecondary,
                  ),
                ],
              ),
              onTap: () => context.push('/theme-selector'),
            ),
            const Divider(height: 1),
            // Quick Theme Selector Chips
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'QUICK THEME SWITCH',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: colors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _buildQuickThemeChip(
                        context: context,
                        ref: ref,
                        theme: AppThemeColors.peachy,
                        isSelected:
                            settings.themeMode == 'peachy' ||
                            settings.themeMode == 'light' ||
                            settings.themeMode.isEmpty,
                        activeColors: colors,
                      ),
                      const SizedBox(width: 8),
                      _buildQuickThemeChip(
                        context: context,
                        ref: ref,
                        theme: AppThemeColors.lavender,
                        isSelected: settings.themeMode == 'lavender',
                        activeColors: colors,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildQuickThemeChip(
                        context: context,
                        ref: ref,
                        theme: AppThemeColors.midnightMochi,
                        isSelected:
                            settings.themeMode == 'midnight_mochi' ||
                            settings.themeMode == 'mochi',
                        activeColors: colors,
                      ),
                      const SizedBox(width: 8),
                      _buildQuickThemeChip(
                        context: context,
                        ref: ref,
                        theme: AppThemeColors.rupeeFlowDark,
                        isSelected:
                            settings.themeMode == 'dark' ||
                            settings.themeMode == 'rupeeflow_dark',
                        activeColors: colors,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            SwitchListTile(
              secondary: Icon(
                Icons.notifications_active_outlined,
                color: colors.primaryAccent,
              ),
              title: Text(
                'Expiry Notifications',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              subtitle: Text(
                'Local alerts for upcoming document validity dates',
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
              ),
              value: settings.notificationsEnabled,
              activeColor: colors.primaryAccent,
              onChanged: (val) {
                ref
                    .read(settingsProvider.notifier)
                    .setNotificationsEnabled(val);
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                Icons.auto_delete_outlined,
                color: colors.primaryAccent,
              ),
              title: Text(
                'Trash Retention Policy',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              subtitle: Text(
                'Auto-cleanup after ${settings.trashRetentionDays} days',
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
              ),
              trailing: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: settings.trashRetentionDays,
                  dropdownColor: colors.surfaceElevated,
                  items: [
                    DropdownMenuItem(
                      value: 7,
                      child: Text(
                        '7 Days',
                        style: TextStyle(color: colors.textPrimary),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 15,
                      child: Text(
                        '15 Days',
                        style: TextStyle(color: colors.textPrimary),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 30,
                      child: Text(
                        '30 Days',
                        style: TextStyle(color: colors.textPrimary),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 60,
                      child: Text(
                        '60 Days',
                        style: TextStyle(color: colors.textPrimary),
                      ),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      ref
                          .read(settingsProvider.notifier)
                          .setTrashRetentionDays(val);
                    }
                  },
                ),
              ),
            ),
          ]),
          const SizedBox(height: 16),

          // Vault Operations & Tools
          _buildCard(context, colors, [
            ListTile(
              leading: Icon(
                Icons.pie_chart_outline_rounded,
                color: colors.info,
              ),
              title: Text(
                'Storage Consumption',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              subtitle: Text(
                'Encrypted files, thumbnails, and database breakdown',
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
              ),
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: colors.textSecondary,
              ),
              onTap: () => context.push('/storage-info'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                Icons.category_outlined,
                color: colors.primaryAccent,
              ),
              title: Text(
                'Manage Categories',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              subtitle: Text(
                'Add, rename, or remove custom document categories',
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
              ),
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: colors.textSecondary,
              ),
              onTap: () => context.push('/category-management'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.history_rounded, color: colors.success),
              title: Text(
                'Activity Timeline',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              subtitle: Text(
                'View local audit logs of document operations',
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
              ),
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: colors.textSecondary,
              ),
              onTap: () => context.push('/timeline'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: colors.error),
              title: Text(
                'Trash & Recovery',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              subtitle: Text(
                'View, restore, or permanently purge deleted items',
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
              ),
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: colors.textSecondary,
              ),
              onTap: () => context.push('/trash'),
            ),
          ]),
          const SizedBox(height: 16),

          // About & Privacy
          _buildCard(context, colors, [
            ListTile(
              leading: Icon(
                Icons.info_outline_rounded,
                color: colors.primaryAccent,
              ),
              title: Text(
                'About & Privacy Architecture',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              subtitle: Text(
                'Offline guarantees, cryptography specs, and licenses',
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
              ),
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: colors.textSecondary,
              ),
              onTap: () => context.push('/about-privacy'),
            ),
          ]),
          const SizedBox(height: 24),

          // Lock Vault Button
          OutlinedButton.icon(
            onPressed: () {
              ref.read(vaultSessionProvider).lock();
              context.go('/biometric-unlock');
            },
            icon: const Icon(Icons.lock_outline_rounded, size: 18),
            label: const Text('Lock Vault Immediately'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              foregroundColor: colors.primaryAccent,
              side: BorderSide(color: colors.cardBorder),
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildQuickThemeChip({
    required BuildContext context,
    required WidgetRef ref,
    required AppThemeColors theme,
    required bool isSelected,
    required AppThemeColors activeColors,
  }) {
    return Expanded(
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          ref.read(settingsProvider.notifier).setThemeMode(theme.id);
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? theme.primaryAccent.withOpacity(0.15)
                : activeColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? theme.primaryAccent : activeColors.cardBorder,
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: theme.primaryAccent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  theme.name,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected
                        ? theme.primaryAccent
                        : activeColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isSelected)
                Icon(Icons.check, size: 14, color: theme.primaryAccent),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCard(
    BuildContext context,
    AppThemeColors colors,
    List<Widget> children,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.cardBorder),
      ),
      child: Column(children: children),
    );
  }
}
