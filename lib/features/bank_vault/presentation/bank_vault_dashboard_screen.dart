import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../../core/widgets/empty_state_view.dart';
import '../../../core/widgets/rupee_bunny_mascot.dart';
import '../../authentication/presentation/auth_providers.dart';
import '../../cards/domain/payment_card_model.dart';
import '../../cards/presentation/widgets/payment_card_widget.dart';
import '../domain/bank_account_model.dart';

enum BankVaultSection { accounts, cards }

class BankVaultDashboardScreen extends ConsumerStatefulWidget {
  const BankVaultDashboardScreen({super.key});

  @override
  ConsumerState<BankVaultDashboardScreen> createState() =>
      _BankVaultDashboardScreenState();
}

class _BankVaultDashboardScreenState
    extends ConsumerState<BankVaultDashboardScreen> {
  BankVaultSection _activeSection = BankVaultSection.accounts;

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final accountsAsync = ref.watch(allBankAccountsProvider);
    final cardsAsync = ref.watch(allPaymentCardsProvider);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Row(
          children: [
            Icon(
              Icons.account_balance_rounded,
              color: colors.primaryAccent,
              size: 24,
            ),
            const SizedBox(width: 10),
            const Text(
              'Bank & Card Vault',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            tooltip: _activeSection == BankVaultSection.accounts
                ? 'Search Accounts'
                : 'Search Cards',
            onPressed: () {
              if (_activeSection == BankVaultSection.accounts) {
                context.push('/bank-accounts-list');
              } else {
                context.push('/cards-list');
              }
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: colors.primaryAccent,
        foregroundColor: colors.onPrimaryAccent,
        icon: const Icon(Icons.add_rounded),
        label: Text(
          _activeSection == BankVaultSection.accounts
              ? 'Add Account'
              : 'Add Card',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        onPressed: () {
          if (_activeSection == BankVaultSection.accounts) {
            context.push('/add-bank-account');
          } else {
            context.push('/add-card');
          }
        },
      ),
      body: RefreshIndicator(
        color: colors.primaryAccent,
        onRefresh: () async {
          ref.invalidate(allBankAccountsProvider);
          ref.invalidate(allPaymentCardsProvider);
          ref.invalidate(favoritePaymentCardsProvider);
          ref.invalidate(expiringPaymentCardsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          children: [
            // Strict Offline Financial Guarantee Banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.cardBackground,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colors.primaryAccent.withOpacity(0.3),
                ),
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
                    child: Icon(
                      Icons.verified_user_rounded,
                      color: colors.primaryAccent,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Strict Offline Financial Vault',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Stores reference details only with AES-256-GCM encryption. Never connects to banking servers, never stores CVVs, ATM PINs, UPI PINs, or OTPs.',
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

            // Top Section Switcher: [ Bank Accounts | Payment Cards ]
            Container(
              decoration: BoxDecoration(
                color: colors.cardBackground,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colors.cardBorder),
              ),
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  Expanded(
                    child: _buildSectionTab(
                      section: BankVaultSection.accounts,
                      label: 'Bank Accounts',
                      icon: Icons.account_balance_outlined,
                      count: accountsAsync.valueOrNull?.length,
                      colors: colors,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _buildSectionTab(
                      section: BankVaultSection.cards,
                      label: 'Cards',
                      icon: Icons.credit_card_outlined,
                      count: cardsAsync.valueOrNull?.length,
                      colors: colors,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Body depending on Active Section
            if (_activeSection == BankVaultSection.accounts) ...[
              _buildAccountsView(context, accountsAsync, colors),
            ] else ...[
              _buildCardsView(context, cardsAsync, colors),
            ],

            const SizedBox(height: 60),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTab({
    required BankVaultSection section,
    required String label,
    required IconData icon,
    int? count,
    required AppThemeColors colors,
  }) {
    final isSelected = _activeSection == section;
    return InkWell(
      onTap: () => setState(() => _activeSection = section),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? colors.primaryAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? colors.onPrimaryAccent : colors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              count != null ? '$label ($count)' : label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                color: isSelected
                    ? colors.onPrimaryAccent
                    : colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- ACCOUNTS SUBSECTION ---
  Widget _buildAccountsView(
    BuildContext context,
    AsyncValue<List<BankAccountModel>> accountsAsync,
    AppThemeColors colors,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        accountsAsync.when(
          data: (accounts) {
            final favoritesCount = accounts.where((a) => a.isFavorite).length;
            final savingsCount = accounts
                .where((a) => a.accountType == 'savings')
                .length;
            final currentCount = accounts
                .where((a) => a.accountType == 'current')
                .length;

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
                        () => context.push(
                          '/bank-accounts-list?filter=favorites',
                        ),
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
              children: accounts
                  .map((a) => _buildAccountRow(context, a, colors))
                  .toList(),
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
      ],
    );
  }

  // --- CARDS SUBSECTION ---
  Widget _buildCardsView(
    BuildContext context,
    AsyncValue<List<PaymentCardModel>> cardsAsync,
    AppThemeColors colors,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        cardsAsync.when(
          data: (cards) {
            final creditCount = cards
                .where((c) => c.cardType == CardType.credit)
                .length;
            final debitCount = cards
                .where((c) => c.cardType == CardType.debit)
                .length;
            final favoritesCount = cards.where((c) => c.isFavorite).length;
            final expiringCount = cards.where((c) => c.isExpiringSoon()).length;

            return Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricTile(
                        'Total Cards',
                        cards.length.toString(),
                        Icons.credit_card_rounded,
                        colors.primaryAccent,
                        colors,
                        () => context.push('/cards-list'),
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
                        () => context.push('/cards-list?filter=favorites'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricTile(
                        'Credit Cards',
                        creditCount.toString(),
                        Icons.credit_score_rounded,
                        colors.info,
                        colors,
                        () => context.push('/cards-list?type=credit'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildMetricTile(
                        'Debit Cards',
                        debitCount.toString(),
                        Icons.payment_rounded,
                        colors.success,
                        colors,
                        () => context.push('/cards-list?type=debit'),
                      ),
                    ),
                  ],
                ),
                if (expiringCount > 0) ...[
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () => context.push('/cards-list?filter=expiring'),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.amber.withOpacity(0.35),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.amber,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '$expiringCount payment card${expiringCount > 1 ? 's' : ''} expiring within 60 days.',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: Colors.amber,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: Colors.amber,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        ),
        const SizedBox(height: 24),

        // Cards List Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Your Payment Cards',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            TextButton(
              onPressed: () => context.push('/cards-list'),
              child: const Text('View All'),
            ),
          ],
        ),
        const SizedBox(height: 8),

        cardsAsync.when(
          data: (cards) {
            if (cards.isEmpty) {
              return EmptyStateView(
                icon: Icons.credit_card_outlined,
                title: 'No payment cards saved yet',
                message: 'Store credit and debit cards with offline AES-256-GCM encryption. Never stores CVVs or ATM PINs.',
                mascotPose: MascotPose.saving,
                actionLabel: 'Add First Card',
                onAction: () => context.push('/add-card'),
              );
            }

            return Column(
              children: cards
                  .map(
                    (card) => Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: PaymentCardWidget(
                        card: card,
                        onTap: () => context.push('/card/${card.id}'),
                        onFavoriteToggle: () async {
                          final repo = ref.read(cardRepositoryProvider);
                          await repo.toggleFavorite(card.id, !card.isFavorite);
                          ref.invalidate(allPaymentCardsProvider);
                          ref.invalidate(favoritePaymentCardsProvider);
                        },
                      ),
                    ),
                  )
                  .toList(),
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
      ],
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
          border: Border.all(color: colors.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 8),
            Text(
              count,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: TextStyle(fontSize: 11, color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountRow(
    BuildContext context,
    BankAccountModel a,
    AppThemeColors colors,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.cardBorder),
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
            child: Icon(
              Icons.account_balance_rounded,
              color: colors.primaryAccent,
              size: 22,
            ),
          ),
        ),
        title: Text(
          a.bankName,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        subtitle: Text(
          '${a.nickname != null ? '${a.nickname} • ' : ''}${a.maskedAccountNumber}',
          style: TextStyle(fontSize: 12.5, color: colors.textSecondary),
        ),
        trailing: a.isFavorite
            ? const Icon(Icons.star_rounded, color: Colors.amber, size: 20)
            : const Icon(Icons.chevron_right_rounded, size: 20),
        onTap: () => context.push('/bank-account/${a.id}'),
      ),
    );
  }
}
