import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../../core/widgets/empty_state_view.dart';
import '../../../core/widgets/rupee_bunny_mascot.dart';
import '../../authentication/presentation/auth_providers.dart';
import '../domain/payment_card_model.dart';
import 'widgets/payment_card_widget.dart';

class CardsListScreen extends ConsumerStatefulWidget {
  final String? initialFilter;
  final String? initialType;

  const CardsListScreen({super.key, this.initialFilter, this.initialType});

  @override
  ConsumerState<CardsListScreen> createState() => _CardsListScreenState();
}

class _CardsListScreenState extends ConsumerState<CardsListScreen> {
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String _selectedFilter =
      'all'; // all, credit, debit, favorites, expiring, expired
  CardNetwork? _selectedNetwork;
  String _sortBy = 'bank'; // bank, expiry, recent

  @override
  void initState() {
    super.initState();
    if (widget.initialType != null) {
      if (widget.initialType == 'credit') _selectedFilter = 'credit';
      if (widget.initialType == 'debit') _selectedFilter = 'debit';
    } else if (widget.initialFilter != null) {
      _selectedFilter = widget.initialFilter!;
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<PaymentCardModel> _applyFiltersAndSorting(List<PaymentCardModel> cards) {
    var filtered = cards.where((card) {
      // 1. Text Search Query
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchesBank = card.bankName.toLowerCase().contains(q);
        final matchesNickname = card.cardNickname.toLowerCase().contains(q);
        final matchesLast4 = card.lastFourDigits.contains(q);
        final matchesHolder =
            card.decryptedCardholderName?.toLowerCase().contains(q) ?? false;
        if (!matchesBank &&
            !matchesNickname &&
            !matchesLast4 &&
            !matchesHolder) {
          return false;
        }
      }

      // 2. Type / Status Filter
      switch (_selectedFilter) {
        case 'credit':
          if (card.cardType != CardType.credit) return false;
          break;
        case 'debit':
          if (card.cardType != CardType.debit) return false;
          break;
        case 'favorites':
          if (!card.isFavorite) return false;
          break;
        case 'expiring':
          if (!card.isExpiringSoon()) return false;
          break;
        case 'expired':
          if (!card.isExpired()) return false;
          break;
        case 'all':
        default:
          break;
      }

      // 3. Network Filter
      if (_selectedNetwork != null && card.network != _selectedNetwork) {
        return false;
      }

      return true;
    }).toList();

    // 4. Sorting
    switch (_sortBy) {
      case 'expiry':
        filtered.sort((a, b) {
          final dateA = DateTime(a.expiryYear, a.expiryMonth);
          final dateB = DateTime(b.expiryYear, b.expiryMonth);
          return dateA.compareTo(dateB);
        });
        break;
      case 'recent':
        filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case 'bank':
      default:
        filtered.sort(
          (a, b) =>
              a.bankName.toLowerCase().compareTo(b.bankName.toLowerCase()),
        );
        break;
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final cardsAsync = ref.watch(allPaymentCardsProvider);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text(
          'Payment Cards',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort_rounded),
            tooltip: 'Sort by',
            onSelected: (val) => setState(() => _sortBy = val),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'bank',
                child: Row(
                  children: [
                    Icon(
                      _sortBy == 'bank'
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      size: 18,
                      color: colors.primaryAccent,
                    ),
                    const SizedBox(width: 8),
                    const Text('Bank Name (A-Z)'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'expiry',
                child: Row(
                  children: [
                    Icon(
                      _sortBy == 'expiry'
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      size: 18,
                      color: colors.primaryAccent,
                    ),
                    const SizedBox(width: 8),
                    const Text('Expiry Date (Soonest first)'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'recent',
                child: Row(
                  children: [
                    Icon(
                      _sortBy == 'recent'
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      size: 18,
                      color: colors.primaryAccent,
                    ),
                    const SizedBox(width: 8),
                    const Text('Recently Added'),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Add Card',
            onPressed: () => context.push('/add-card'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: colors.primaryAccent,
        foregroundColor: colors.onPrimaryAccent,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Add Card',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        onPressed: () => context.push('/add-card'),
      ),
      body: RefreshIndicator(
        color: colors.primaryAccent,
        onRefresh: () async {
          ref.invalidate(allPaymentCardsProvider);
          ref.invalidate(favoritePaymentCardsProvider);
          ref.invalidate(expiringPaymentCardsProvider);
        },
        child: Column(
          children: [
            // Search Input
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _searchQuery = v.trim()),
                decoration: InputDecoration(
                  hintText: 'Search by bank, nickname, holder, last 4...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: colors.cardBackground,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: colors.cardBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: colors.cardBorder),
                  ),
                ),
              ),
            ),

            // Horizontal Filter Chips
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _buildFilterChip('All Cards', 'all', colors),
                  _buildFilterChip('Credit Cards', 'credit', colors),
                  _buildFilterChip('Debit Cards', 'debit', colors),
                  _buildFilterChip('Favorites', 'favorites', colors),
                  _buildFilterChip('Expiring Soon', 'expiring', colors),
                  _buildFilterChip('Expired', 'expired', colors),
                ],
              ),
            ),
            const SizedBox(height: 6),

            // Network Filter Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    'Network:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<CardNetwork?>(
                    value: _selectedNetwork,
                    underline: const SizedBox.shrink(),
                    icon: const Icon(Icons.arrow_drop_down, size: 20),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('All Networks'),
                      ),
                      ...CardNetwork.values.map(
                        (n) => DropdownMenuItem(
                          value: n,
                          child: Text(n.displayName),
                        ),
                      ),
                    ],
                    onChanged: (net) => setState(() => _selectedNetwork = net),
                  ),
                ],
              ),
            ),
            const Divider(height: 12),

            // Cards Content
            Expanded(
              child: cardsAsync.when(
                data: (cards) {
                  final filtered = _applyFiltersAndSorting(cards);

                  if (cards.isEmpty) {
                    return EmptyStateView(
                      icon: Icons.credit_card_outlined,
                      title: 'No payment cards yet',
                      message: 'Safely store credit and debit cards with offline AES-256-GCM encryption. Never stores CVVs or ATM PINs.',
                      mascotPose: MascotPose.saving,
                      actionLabel: 'Add First Card',
                      onAction: () => context.push('/add-card'),
                    );
                  }

                  if (filtered.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.search_off_rounded,
                            size: 48,
                            color: colors.textSecondary,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No cards match your filter',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Try resetting your search query or filters',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: colors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton(
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() {
                                _searchQuery = '';
                                _selectedFilter = 'all';
                                _selectedNetwork = null;
                              });
                            },
                            child: const Text('Reset Filters'),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final card = filtered[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: PaymentCardWidget(
                          card: card,
                          onTap: () => context.push('/card/${card.id}'),
                          onFavoriteToggle: () async {
                            final repo = ref.read(cardRepositoryProvider);
                            await repo.toggleFavorite(
                              card.id,
                              !card.isFavorite,
                            );
                            ref.invalidate(allPaymentCardsProvider);
                            ref.invalidate(favoritePaymentCardsProvider);
                          },
                        ),
                      );
                    },
                  );
                },
                loading: () => Center(
                  child: CircularProgressIndicator(color: colors.primaryAccent),
                ),
                error: (err, _) =>
                    Center(child: Text('Error loading cards: $err')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, AppThemeColors colors) {
    final isSelected = _selectedFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? colors.onPrimaryAccent : colors.textPrimary,
          ),
        ),
        selected: isSelected,
        selectedColor: colors.primaryAccent,
        backgroundColor: colors.cardBackground,
        checkmarkColor: colors.onPrimaryAccent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: isSelected ? colors.primaryAccent : colors.cardBorder,
          ),
        ),
        onSelected: (_) => setState(() => _selectedFilter = value),
      ),
    );
  }
}
