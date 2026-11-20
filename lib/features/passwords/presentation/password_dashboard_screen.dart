import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../../core/widgets/empty_state_view.dart';
import '../../../core/widgets/rupee_bunny_mascot.dart';
import '../../../core/widgets/status_badge.dart';
import '../../authentication/presentation/auth_providers.dart';
import '../domain/password_entry_model.dart';

class PasswordDashboardScreen extends ConsumerWidget {
  const PasswordDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.themeColors;
    final passwordsAsync = ref.watch(allPasswordsProvider);
    final auditAsync = ref.watch(passwordSecurityAuditProvider);
    final categoriesAsync = ref.watch(passwordCategoriesProvider);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.key_rounded, color: colors.primaryAccent, size: 24),
            const SizedBox(width: 10),
            const Text('Passwords', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.shield_outlined),
            tooltip: 'Security Audit',
            onPressed: () => context.push('/password-security'),
          ),
          IconButton(
            icon: const Icon(Icons.password_rounded),
            tooltip: 'Password Generator',
            onPressed: () => context.push('/password-generator'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: colors.primaryAccent,
        foregroundColor: colors.onPrimaryAccent,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Password', style: TextStyle(fontWeight: FontWeight.w700)),
        onPressed: () => context.push('/add-password'),
      ),
      body: RefreshIndicator(
        color: colors.primaryAccent,
        onRefresh: () async {
          ref.invalidate(allPasswordsProvider);
          ref.invalidate(passwordCategoriesProvider);
        },
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          children: [
            // Security Health Header Banner
            auditAsync.when(
              data: (audit) => _buildSecurityHealthCard(context, audit, colors),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 16),

            // Metrics Summary Grid
            passwordsAsync.when(
              data: (list) {
                final favoritesCount = list.where((p) => p.isFavorite).length;
                return Row(
                  children: [
                    Expanded(
                      child: _buildMetricTile(
                        context,
                        title: 'Total Saved',
                        count: list.length.toString(),
                        icon: Icons.vpn_key_outlined,
                        color: colors.primaryAccent,
                        colors: colors,
                        onTap: () => context.push('/passwords-list'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildMetricTile(
                        context,
                        title: 'Favorites',
                        count: favoritesCount.toString(),
                        icon: Icons.star_outline_rounded,
                        color: Colors.amber,
                        colors: colors,
                        onTap: () => context.push('/passwords-list?filter=favorites'),
                      ),
                    ),
                  ],
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 20),

            // Quick Tools Bar
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context.push('/password-generator'),
                    icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                    label: const Text('Generator'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context.push('/password-security'),
                    icon: const Icon(Icons.security_rounded, size: 18),
                    label: const Text('Audit Health'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Categories Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Categories',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                TextButton(
                  onPressed: () => context.push('/passwords-list'),
                  child: const Text('View All'),
                ),
              ],
            ),
            const SizedBox(height: 8),

            categoriesAsync.when(
              data: (cats) => SizedBox(
                height: 42,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: cats.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final cat = cats[i];
                    return ActionChip(
                      label: Text(cat.name, style: const TextStyle(fontSize: 12)),
                      avatar: CircleAvatar(
                        radius: 8,
                        backgroundColor: Color(cat.colorValue),
                      ),
                      onPressed: () => context.push('/passwords-list?category=${cat.id}'),
                    );
                  },
                ),
              ),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 24),

            // Recent Passwords Header
            const Text(
              'Saved Accounts',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),

            // Passwords List
            passwordsAsync.when(
              data: (passwords) {
                if (passwords.isEmpty) {
                  return EmptyStateView(
                    icon: Icons.key_off_outlined,
                    title: 'No passwords saved yet',
                    message: 'Securely store website and app credentials locally with AES-256-GCM encryption.',
                    mascotPose: MascotPose.saving,
                    actionLabel: 'Add First Password',
                    onAction: () => context.push('/add-password'),
                  );
                }

                return Column(
                  children: passwords.take(8).map((p) => _buildPasswordRow(context, p, colors)).toList(),
                );
              },
              loading: () => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: CircularProgressIndicator(color: colors.primaryAccent),
                ),
              ),
              error: (err, _) => Text('Error: $err'),
            ),
            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }

  Widget _buildSecurityHealthCard(BuildContext context, dynamic audit, AppThemeColors colors) {
    final score = audit.overallScore as int;
    final color = score >= 80
        ? colors.success
        : score >= 50
            ? colors.warning
            : colors.error;

    return InkWell(
      onTap: () => context.push('/password-security'),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.cardBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '$score',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Password Security Score',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    score >= 80
                        ? 'Good Health • Strong and unique credentials'
                        : '${audit.weakCount + audit.shortCount} vulnerable account(s) detected',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: colors.primaryAccent),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricTile(
    BuildContext context, {
    required String title,
    required String count,
    required IconData icon,
    required Color color,
    required AppThemeColors colors,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.cardBackground,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colors.cardBorder,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 12),
            Text(
              count,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPasswordRow(BuildContext context, PasswordEntryModel p, AppThemeColors colors) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colors.cardBorder,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: colors.primaryAccent.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Icon(Icons.lock_outline_rounded, color: colors.primaryAccent, size: 22),
          ),
        ),
        title: Text(
          p.title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        subtitle: Text(
          p.decryptedUsername ?? p.decryptedEmail ?? 'No username',
          style: TextStyle(
            fontSize: 13,
            color: colors.textSecondary,
          ),
        ),
        trailing: p.isFavorite
            ? const Icon(Icons.star_rounded, color: Colors.amber, size: 20)
            : const Icon(Icons.chevron_right_rounded, size: 20),
        onTap: () => context.push('/password/${p.id}'),
      ),
    );
  }
}

