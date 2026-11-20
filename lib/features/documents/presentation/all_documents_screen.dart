import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/masked_text_formatter.dart';
import '../../../core/widgets/empty_state_view.dart';
import '../../../core/widgets/status_badge.dart';
import '../../authentication/presentation/auth_providers.dart';
import '../../documents/domain/document_model.dart';

class AllDocumentsScreen extends ConsumerStatefulWidget {
  const AllDocumentsScreen({super.key});

  @override
  ConsumerState<AllDocumentsScreen> createState() => _AllDocumentsScreenState();
}

class _AllDocumentsScreenState extends ConsumerState<AllDocumentsScreen> {
  String _selectedCategoryFilter = 'all';
  String _sortBy = 'updated_desc'; // updated_desc, name_asc, expiry_asc

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final docsAsync = ref.watch(activeDocumentsProvider);
    final catsAsync = ref.watch(categoriesProvider);

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.lightBackground,
      appBar: AppBar(
        title: const Text('All Documents', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            onPressed: () => context.push('/search'),
          ),
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Add Document',
            onPressed: () => context.push('/add-document'),
          ),
        ],
      ),
      body: docsAsync.when(
        data: (allDocs) {
          final categories = catsAsync.valueOrNull ?? [];

          // Apply category filter
          var filtered = _selectedCategoryFilter == 'all'
              ? allDocs
              : allDocs.where((d) => d.categoryId == _selectedCategoryFilter).toList();

          // Apply sorting
          if (_sortBy == 'name_asc') {
            filtered.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
          } else if (_sortBy == 'expiry_asc') {
            filtered.sort((a, b) {
              if (a.expiryDate == null) return 1;
              if (b.expiryDate == null) return -1;
              return a.expiryDate!.compareTo(b.expiryDate!);
            });
          } else {
            // updated_desc
            filtered.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
          }

          return Column(
            children: [
              // Filter & Sort Bar
              Container(
                height: 52,
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    _buildFilterChip('All', 'all'),
                    ...categories.map((c) => _buildFilterChip(c.name, c.id)),
                  ],
                ),
              ),
              const Divider(height: 1),

              // Documents List or Empty State
              Expanded(
                child: filtered.isEmpty
                    ? EmptyStateView(
                        icon: Icons.folder_open_rounded,
                        title: 'No Documents Found',
                        description: _selectedCategoryFilter == 'all'
                            ? 'Your vault is currently empty. Tap below to scan or import your first document.'
                            : 'No documents found in this category.',
                        actionLabel: 'Add Document',
                        onAction: () => context.push('/add-document'),
                      )
                    : RefreshIndicator(
                        color: AppColors.primaryTeal,
                        onRefresh: () async {
                          ref.invalidate(activeDocumentsProvider);
                        },
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (ctx, i) {
                            return _buildDocCard(filtered[i]);
                          },
                        ),
                      ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primaryTeal)),
        error: (e, _) => Center(child: Text('Error loading documents: $e')),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primaryTeal,
        foregroundColor: Colors.white,
        onPressed: () => context.push('/add-document'),
        child: const Icon(Icons.add_rounded),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedCategoryFilter == value;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (selected) {
          setState(() {
            _selectedCategoryFilter = value;
          });
        },
        backgroundColor: isDark ? AppColors.darkCard : AppColors.lightCardElevated,
        selectedColor: AppColors.primaryTeal.withOpacity(0.2),
        checkmarkColor: AppColors.primaryTeal,
        labelStyle: TextStyle(
          color: isSelected
              ? AppColors.primaryTeal
              : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
          fontSize: 12.5,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: isSelected ? AppColors.primaryTeal : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
          ),
        ),
      ),
    );
  }

  Widget _buildDocCard(DocumentModel doc) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
        title: Row(
          children: [
            Expanded(
              child: Text(
                doc.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                ),
              ),
            ),
            if (doc.isFavorite)
              const Icon(Icons.star_rounded, color: Colors.amber, size: 18),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 3),
            Text(
              doc.documentNumber != null
                  ? MaskedTextFormatter.maskDocumentNumber(doc.documentNumber)
                  : (doc.documentType ?? 'Document'),
              style: TextStyle(
                fontSize: 12.5,
                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                StatusBadge.fromExpiry(doc.expiryDate),
                const SizedBox(width: 8),
                Text(
                  '${doc.files.length} page${doc.files.length == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_right_rounded, size: 20),
      ),
    );
  }
}

