import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/masked_text_formatter.dart';
import '../../../core/widgets/empty_state_view.dart';
import '../../../core/widgets/status_badge.dart';
import '../../authentication/presentation/auth_providers.dart';
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final docsAsync = ref.watch(activeDocumentsProvider);
    final catsAsync = ref.watch(categoriesProvider);

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.lightBackground,
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
            hintStyle: TextStyle(
              color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
              fontSize: 15,
            ),
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
                  backgroundColor: isDark ? AppColors.darkCard : AppColors.lightCardElevated,
                  selectedColor: Colors.amber.withOpacity(0.2),
                  checkmarkColor: Colors.amber,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    color: _onlyFavorites ? Colors.amber : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
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
                        backgroundColor: isDark ? AppColors.darkCard : AppColors.lightCardElevated,
                        selectedColor: AppColors.primaryTeal.withOpacity(0.2),
                        checkmarkColor: AppColors.primaryTeal,
                        labelStyle: TextStyle(
                          fontSize: 12,
                          color: isSel ? AppColors.primaryTeal : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
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
                  results = results.where((d) => d.categoryId == _selectedCategory).toList();
                }

                if (_query.isNotEmpty) {
                  results = results.where((doc) {
                    if (doc.name.toLowerCase().contains(_query)) return true;
                    if (doc.documentType?.toLowerCase().contains(_query) ?? false) return true;
                    if (doc.documentNumber?.toLowerCase().contains(_query) ?? false) return true;
                    if (doc.ownerName?.toLowerCase().contains(_query) ?? false) return true;
                    if (doc.issuingAuthority?.toLowerCase().contains(_query) ?? false) return true;
                    if (doc.notes?.toLowerCase().contains(_query) ?? false) return true;
                    if (doc.tags.any((t) => t.toLowerCase().contains(_query))) return true;
                    return false;
                  }).toList();
                }

                if (results.isEmpty) {
                  return const EmptyStateView(
                    icon: Icons.search_off_rounded,
                    title: 'No Matching Documents',
                    description: 'No documents match your search criteria. Try a different query or adjust your filters.',
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: results.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (ctx, i) {
                    final doc = results[i];

                    return Container(
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkCard : AppColors.lightCard,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                        ),
                      ),
                      child: ListTile(
                        onTap: () => context.push('/document/${doc.id}'),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        leading: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.primaryTeal.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.description_outlined, color: AppColors.primaryTeal, size: 22),
                        ),
                        title: Text(
                          doc.name,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                          ),
                        ),
                        subtitle: Text(
                          doc.documentNumber != null
                              ? MaskedTextFormatter.maskDocumentNumber(doc.documentNumber)
                              : (doc.documentType ?? 'Document'),
                          style: TextStyle(
                            fontSize: 12.5,
                            color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                          ),
                        ),
                        trailing: StatusBadge.fromExpiry(doc.expiryDate),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primaryTeal)),
              error: (e, _) => Center(child: Text('Error searching: $e')),
            ),
          ),
        ],
      ),
    );
  }
}

