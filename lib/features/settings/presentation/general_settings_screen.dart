import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../authentication/presentation/auth_providers.dart';

class GeneralSettingsScreen extends ConsumerWidget {
  const GeneralSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.lightBackground,
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        children: [
          // Security Navigation
          _buildCard(context, [
            ListTile(
              leading: const Icon(Icons.security_rounded, color: AppColors.primaryTeal),
              title: const Text('Security & Master Key', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('PIN, Biometrics, Auto-Lock, FLAG_SECURE', style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/security-settings'),
            ),
          ]),
          const SizedBox(height: 16),

          // Vault Operations & Tools
          _buildCard(context, [
            ListTile(
              leading: const Icon(Icons.pie_chart_outline_rounded, color: Color(0xFF2563EB)),
              title: const Text('Storage Consumption', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Encrypted files, thumbnails, and database breakdown', style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/storage-info'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.category_outlined, color: Color(0xFF7C3AED)),
              title: const Text('Manage Categories', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Add, rename, or remove custom document categories', style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/category-management'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.history_rounded, color: Color(0xFF059669)),
              title: const Text('Activity Timeline', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('View local audit logs of document operations', style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/timeline'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Color(0xFFE11D48)),
              title: const Text('Trash & Recovery', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('View, restore, or permanently purge deleted items', style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/trash'),
            ),
          ]),
          const SizedBox(height: 16),

          // Preferences (Theme & Notifications)
          _buildCard(context, [
            ListTile(
              leading: const Icon(Icons.palette_outlined, color: AppColors.primaryTeal),
              title: const Text('Appearance Theme', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('Current: ${settings.themeMode.toUpperCase()}', style: const TextStyle(fontSize: 12)),
              trailing: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: settings.themeMode,
                  items: const [
                    DropdownMenuItem(value: 'system', child: Text('System')),
                    DropdownMenuItem(value: 'dark', child: Text('Dark')),
                    DropdownMenuItem(value: 'light', child: Text('Light')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      ref.read(settingsProvider.notifier).setThemeMode(val);
                    }
                  },
                ),
              ),
            ),
            const Divider(height: 1),
            SwitchListTile(
              secondary: const Icon(Icons.notifications_active_outlined, color: AppColors.primaryTeal),
              title: const Text('Expiry Notifications', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Local alerts for upcoming document validity dates', style: TextStyle(fontSize: 12)),
              value: settings.notificationsEnabled,
              activeColor: AppColors.primaryTeal,
              onChanged: (val) {
                ref.read(settingsProvider.notifier).setNotificationsEnabled(val);
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.auto_delete_outlined, color: AppColors.primaryTeal),
              title: const Text('Trash Retention Policy', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('Auto-cleanup after ${settings.trashRetentionDays} days', style: const TextStyle(fontSize: 12)),
              trailing: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: settings.trashRetentionDays,
                  items: const [
                    DropdownMenuItem(value: 7, child: Text('7 Days')),
                    DropdownMenuItem(value: 15, child: Text('15 Days')),
                    DropdownMenuItem(value: 30, child: Text('30 Days')),
                    DropdownMenuItem(value: 60, child: Text('60 Days')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      ref.read(settingsProvider.notifier).setTrashRetentionDays(val);
                    }
                  },
                ),
              ),
            ),
          ]),
          const SizedBox(height: 16),

          // About & Privacy
          _buildCard(context, [
            ListTile(
              leading: const Icon(Icons.info_outline_rounded, color: AppColors.primaryTeal),
              title: const Text('About & Privacy Architecture', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Offline guarantees, cryptography specs, and licenses', style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/about-privacy'),
            ),
          ]),
          const SizedBox(height: 24),

          // Lock Vault Button
          OutlinedButton.icon(
            onPressed: () {
              ref.read(vaultSessionProvider).lock();
              context.go('/pin-unlock');
            },
            icon: const Icon(Icons.lock_outline_rounded, size: 18),
            label: const Text('Lock Vault Immediately'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildCard(BuildContext context, List<Widget> children) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
      ),
      child: Column(children: children),
    );
  }
}

