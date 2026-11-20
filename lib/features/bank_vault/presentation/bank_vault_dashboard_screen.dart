import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../../core/widgets/empty_state_view.dart';
import '../../../core/widgets/rupee_bunny_mascot.dart';
import '../../authentication/presentation/auth_providers.dart';
import '../domain/bank_account_model.dart';

class BankVaultDashboardScreen extends ConsumerWidget {
  const BankVaultDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.themeColors;
    final accountsAsync = ref.watch(allBankAccountsProvider);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.account_balance_rounded, color: colors.primaryAccent, size: 24),
            const SizedBox(width: 10),
            const Text('Bank Vault', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            tooltip: 'Search Accounts',
            onPressed: () => context.push('/bank-accounts-list'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: colors.primaryAccent,
        foregroundColor: colors.onPrimaryAccent,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Account', style: TextStyle(fontWeight: FontWeight.w700)),
        onPressed: () => context.push('/add-bank-account'),
      ),
      body: RefreshIndicator(
        color: colors.primaryAccent,
        onRefresh: () async {
          ref.invalidate(allBankAccountsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          children: [
            // Strict Privacy Guarantee Banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.cardBackground,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.primaryAccent.withOpacity(0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colors.primaryAccent.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.verified_user_rounded,
                        color: colors.primaryAccent, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Strict Offline Reference Vault',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Bank Vault only stores local reference details. It does NOT connect to banks, execute transactions, or store ATM PINs, CVVs, or Netbanking passwords.',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textSecondary,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Summary Metrics
            accountsAsync.when(
              data: (accounts) {
                final favoritesCount = accounts.where((a) => a.isFavorite).length;
                final savingsCount = accounts.where((a) => a.accountType == 'savings').length;
                final currentCount = accounts.where((a) => a.accountType == 'current').length;

                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildMetricTile(
                            'Total Accounts',
                            accounts.length.toString(),
                            Icons.account_balance_rounded,
                            colors.primaryAccent,
                            colors,
                            () => context.push('/bank-accounts-list'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildMetricTile(
                            'Favorites',
                            favoritesCount.toString(),
                            Icons.star_outline_rounded,
                            Colors.amber,
                            colors,
                            () => context.push('/bank-accounts-list?filter=favorites'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildMetricTile(
                            'Savings Accounts',
                            savingsCount.toString(),
                            Icons.savings_outlined,
                            colors.success,
                            colors,
                            () => context.push('/bank-accounts-list?type=savings'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildMetricTile(
                            'Current / Business',
                            currentCount.toString(),
                            Icons.business_center_outlined,
                            colors.info,
                            colors,
                            () => context.push('/bank-accounts-list?type=current'),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 24),

            // Accounts List Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Your Bank Accounts',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                TextButton(
                  onPressed: () => context.push('/bank-accounts-list'),
                  child: const Text('View All'),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Accounts List
            accountsAsync.when(
              data: (accounts) {
                if (accounts.isEmpty) {
                  return EmptyStateView(
                    icon: Icons.account_balance_outlined,
                    title: 'No bank accounts saved yet',
                    message: 'Safely store your account numbers and IFSC codes with AES-256-GCM encryption.',
                    mascotPose: MascotPose.saving,
                    actionLabel: 'Add First Account',
                    onAction: () => context.push('/add-bank-account'),
                  );
                }

                return Column(
                  children: accounts.map((a) => _buildAccountRow(context, a, colors)).toList(),
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

  Widget _buildMetricTile(
    String title,
    String count,
    IconData icon,
    Color color,
    AppThemeColors colors,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.cardBackground,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: colors.cardBorder,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 8),
            Text(count, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(
              title,
              style: TextStyle(
                fontSize: 11,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountRow(BuildContext context, BankAccountModel a, AppThemeColors colors) {
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
            child: Icon(Icons.account_balance_rounded, color: colors.primaryAccent, size: 22),
          ),
        ),
        title: Text(
          a.bankName,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        subtitle: Text(
          '${a.nickname != null ? '${a.nickname} • ' : ''}${a.maskedAccountNumber}',
          style: TextStyle(
            fontSize: 12.5,
            color: colors.textSecondary,
          ),
        ),
        trailing: a.isFavorite
            ? const Icon(Icons.star_rounded, color: Colors.amber, size: 20)
            : const Icon(Icons.chevron_right_rounded, size: 20),
        onTap: () => context.push('/bank-account/${a.id}'),
      ),
    );
  }
}

