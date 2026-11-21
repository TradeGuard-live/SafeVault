import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/masked_text_formatter.dart';
import '../../../core/widgets/empty_state_view.dart';
import '../../../core/widgets/rupee_bunny_mascot.dart';
import '../../../core/widgets/status_badge.dart';
import '../../authentication/presentation/auth_providers.dart';
import '../../cards/domain/payment_card_model.dart';
import '../../documents/domain/document_model.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  bool _onlyFavorites = false;
  String? _selectedCategory;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final docsAsync = ref.watch(activeDocumentsProvider);
    final catsAsync = ref.watch(categoriesProvider);
    final cardsAsync = ref.watch(allPaymentCardsProvider);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Search by name, number, owner, tags...',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            hintStyle: TextStyle(color: colors.textTertiary, fontSize: 15),
          ),
          onChanged: (val) {
            setState(() => _query = val.trim().toLowerCase());
          },
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_rounded),
              onPressed: () {
                _searchController.clear();
                setState(() => _query = '');
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // Filter Chips
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                FilterChip(
                  label: const Text('Favorites Only'),
                  selected: _onlyFavorites,
                  onSelected: (val) => setState(() => _onlyFavorites = val),
                  backgroundColor: colors.cardBackground,
                  selectedColor: Colors.amber.withOpacity(0.2),
                  checkmarkColor: Colors.amber,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    color: _onlyFavorites ? Colors.amber : colors.textSecondary,
                  ),
                ),
                const SizedBox(width: 8),
                if (catsAsync.valueOrNull != null)
                  ...catsAsync.valueOrNull!.map((c) {
                    final isSel = _selectedCategory == c.id;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: FilterChip(
                        label: Text(c.name),
                        selected: isSel,
                        onSelected: (val) {
                          setState(() => _selectedCategory = val ? c.id : null);
                        },
                        backgroundColor: colors.cardBackground,
                        selectedColor: colors.primaryAccent.withOpacity(0.2),
                        checkmarkColor: colors.primaryAccent,
                        labelStyle: TextStyle(
                          fontSize: 12,
                          color: isSel
                              ? colors.primaryAccent
                              : colors.textSecondary,
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ),
          const Divider(height: 1),

          // Search Results
          Expanded(
            child: docsAsync.when(
              data: (allDocs) {
                var results = allDocs;

                if (_onlyFavorites) {
                  results = results.where((d) => d.isFavorite).toList();
                }

                if (_selectedCategory != null) {
                  results = results
                      .where((d) => d.categoryId == _selectedCategory)
                      .toList();
                }

                if (_query.isNotEmpty) {
                  results = results.where((doc) {
                    if (doc.name.toLowerCase().contains(_query)) return true;
                    if (doc.documentType?.toLowerCase().contains(_query) ??
                        false) {
                      return true;
                    }
                    if (doc.documentNumber?.toLowerCase().contains(_query) ??
                        false) {
                      return true;
                    }
                    if (doc.ownerName?.toLowerCase().contains(_query) ??
                        false) {
                      return true;
                    }
                    if (doc.issuingAuthority?.toLowerCase().contains(_query) ??
                        false) {
                      return true;
                    }
                    if (doc.notes?.toLowerCase().contains(_query) ?? false) {
                      return true;
                    }
                    if (doc.tags.any((t) => t.toLowerCase().contains(_query))) {
                      return true;
                    }
                    return false;
                  }).toList();
                }

                List<PaymentCardModel> matchingCards = [];
                if (_selectedCategory == null &&
                    cardsAsync.valueOrNull != null) {
                  matchingCards = cardsAsync.valueOrNull!.where((card) {
                    if (_onlyFavorites && !card.isFavorite) return false;
                    if (_query.isEmpty) return false;
                    final q = _query.toLowerCase();
                    return card.bankName.toLowerCase().contains(q) ||
                        card.cardNickname.toLowerCase().contains(q) ||
                        card.lastFourDigits.contains(q) ||
                        (card.decryptedCardholderName?.toLowerCase().contains(
                              q,
                            ) ??
                            false);
                  }).toList();
                }

                if (results.isEmpty && matchingCards.isEmpty) {
                  return const EmptyStateView(
                    icon: Icons.search_off_rounded,
                    title: 'No Matching Items',
                    description: 'No documents or payment cards match your search criteria. Try a different query or adjust your filters.',
                    mascotPose: MascotPose.thinking,
                  );
                }

                return ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  children: [
                    if (matchingCards.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8, top: 4),
                        child: Text(
                          'Payment Cards (${matchingCards.length})',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: colors.primaryAccent,
                          ),
                        ),
                      ),
                      ...matchingCards.map(
                        (card) => Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: colors.cardBackground,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: colors.cardBorder),
                          ),
                          child: ListTile(
                            onTap: () => context.push('/card/${card.id}'),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 4,
                            ),
                            leading: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: colors.primaryAccent.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.credit_card_rounded,
                                color: colors.primaryAccent,
                                size: 22,
                              ),
                            ),
                            title: Text(
                              card.bankName,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: colors.textPrimary,
                              ),
                            ),
                            subtitle: Text(
                              '${card.cardNickname} • ${card.maskedCardNumber}',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: colors.textSecondary,
                              ),
                            ),
                            trailing: card.isFavorite
                                ? const Icon(
                                    Icons.star_rounded,
                                    color: Colors.amber,
                                    size: 20,
                                  )
                                : const Icon(
                                    Icons.chevron_right_rounded,
                                    size: 20,
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (results.isNotEmpty) ...[
                      if (matchingCards.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8, top: 4),
                          child: Text(
                            'Documents (${results.length})',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: colors.primaryAccent,
                            ),
                          ),
                        ),
                      ...results.map(
                        (doc) => Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: colors.cardBackground,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: colors.cardBorder),
                          ),
                          child: ListTile(
                            onTap: () => context.push('/document/${doc.id}'),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 6,
                            ),
                            leading: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: colors.primaryAccent.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.description_outlined,
                                color: colors.primaryAccent,
                                size: 22,
                              ),
                            ),
                            title: Text(
                              doc.name,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: colors.textPrimary,
                              ),
                            ),
                            subtitle: Text(
                              doc.documentNumber != null
                                  ? MaskedTextFormatter.maskDocumentNumber(
                                      doc.documentNumber,
                                    )
                                  : (doc.documentType ?? 'Document'),
                              style: TextStyle(
                                fontSize: 12.5,
                                color: colors.textSecondary,
                              ),
                            ),
                            trailing: StatusBadge.fromExpiry(doc.expiryDate),
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
              loading: () => Center(
                child: CircularProgressIndicator(color: colors.primaryAccent),
              ),
              error: (e, _) => Center(child: Text('Error searching: $e')),
            ),
          ),
        ],
      ),
    );
  }
}
