import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../../core/utils/masked_text_formatter.dart';
import '../../../core/widgets/empty_state_view.dart';
import '../../../core/widgets/rupee_bunny_mascot.dart';
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
    final colors = context.themeColors;
    final docsAsync = ref.watch(activeDocumentsProvider);
    final catsAsync = ref.watch(categoriesProvider);

    return Scaffold(
      backgroundColor: colors.background,
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
                    _buildFilterChip('All', 'all', colors),
                    ...categories.map((c) => _buildFilterChip(c.name, c.id, colors)),
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
                        mascotPose: MascotPose.friendly,
                        actionLabel: 'Add Document',
                        onAction: () => context.push('/add-document'),
                      )
                    : RefreshIndicator(
                        color: colors.primaryAccent,
                        onRefresh: () async {
                          ref.invalidate(activeDocumentsProvider);
                        },
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (ctx, i) {
                            return _buildDocCard(filtered[i], colors);
                          },
                        ),
                      ),
              ),
            ],
          );
        },
        loading: () => Center(child: CircularProgressIndicator(color: colors.primaryAccent)),
        error: (e, _) => Center(child: Text('Error loading documents: $e')),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: colors.primaryAccent,
        foregroundColor: colors.onPrimaryAccent,
        onPressed: () => context.push('/add-document'),
        child: const Icon(Icons.add_rounded),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, AppThemeColors colors) {
    final isSelected = _selectedCategoryFilter == value;

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
        backgroundColor: colors.cardBackground,
        selectedColor: colors.primaryAccent.withOpacity(0.18),
        checkmarkColor: colors.primaryAccent,
        labelStyle: TextStyle(
          color: isSelected
              ? colors.primaryAccent
              : colors.textSecondary,
          fontSize: 12.5,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: isSelected ? colors.primaryAccent : colors.cardBorder,
          ),
        ),
      ),
    );
  }

  Widget _buildDocCard(DocumentModel doc, AppThemeColors colors) {
    return Container(
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colors.cardBorder,
        ),
      ),
      child: ListTile(
        onTap: () => context.push('/document/${doc.id}'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: colors.primaryAccent.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.description_outlined, color: colors.primaryAccent, size: 22),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                doc.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
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
                color: colors.textSecondary,
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
                    color: colors.textTertiary,
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

