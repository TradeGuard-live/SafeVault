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
import '../../groups/domain/document_group_model.dart';

class AllDocumentsScreen extends ConsumerStatefulWidget {
  const AllDocumentsScreen({super.key});

  @override
  ConsumerState<AllDocumentsScreen> createState() => _AllDocumentsScreenState();
}

class _AllDocumentsScreenState extends ConsumerState<AllDocumentsScreen> {
  String _selectedFilter = 'all'; // 'all', 'temporary', 'group:<id>', or categoryId
  String _sortBy = 'updated_desc'; // updated_desc, name_asc, expiry_asc

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final docsAsync = ref.watch(activeDocumentsProvider);
    final catsAsync = ref.watch(categoriesProvider);
    final groupsAsync = ref.watch(documentGroupsProvider);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text(
          'All Documents',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search_rounded),
            onPressed: () => context.push('/search'),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.folder_special_outlined),
            tooltip: 'Groups & Temporary',
            onSelected: (val) {
              if (val == 'groups') {
                context.push('/document-groups');
              } else if (val == 'temporary') {
                context.push('/temporary-documents');
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'groups',
                child: Row(
                  children: [
                    Icon(Icons.folder_special_rounded, size: 18),
                    SizedBox(width: 10),
                    Text('Manage Groups'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'temporary',
                child: Row(
                  children: [
                    Icon(Icons.hourglass_top_rounded, size: 18),
                    SizedBox(width: 10),
                    Text('Temporary Documents'),
                  ],
                ),
              ),
            ],
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort_rounded),
            tooltip: 'Sort Documents',
            onSelected: (val) => setState(() => _sortBy = val),
            itemBuilder: (context) => [
              CheckedPopupMenuItem(
                value: 'updated_desc',
                checked: _sortBy == 'updated_desc',
                child: const Text('Recently Updated'),
              ),
              CheckedPopupMenuItem(
                value: 'name_asc',
                checked: _sortBy == 'name_asc',
                child: const Text('Name (A-Z)'),
              ),
              CheckedPopupMenuItem(
                value: 'expiry_asc',
                checked: _sortBy == 'expiry_asc',
                child: const Text('Expiry Date'),
              ),
            ],
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
          final groups = groupsAsync.valueOrNull ?? [];

          // Apply filter
          var filtered = allDocs;
          if (_selectedFilter == 'all') {
            filtered = allDocs;
          } else if (_selectedFilter == 'temporary') {
            filtered = allDocs.where((d) => d.isTemporary).toList();
          } else if (_selectedFilter.startsWith('group:')) {
            final gid = _selectedFilter.replaceFirst('group:', '');
            filtered = allDocs.where((d) => d.groupIds.contains(gid)).toList();
          } else {
            filtered = allDocs.where((d) => d.categoryId == _selectedFilter).toList();
          }

          // Apply sorting
          if (_sortBy == 'name_asc') {
            filtered.sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );
          } else if (_sortBy == 'expiry_asc') {
            filtered.sort((a, b) {
              final aExp = a.isTemporary ? a.expiresAt : a.expiryDate;
              final bExp = b.isTemporary ? b.expiresAt : b.expiryDate;
              if (aExp == null) return 1;
              if (bExp == null) return -1;
              return aExp.compareTo(bExp);
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
                    _buildFilterChip(
                      'Temporary',
                      'temporary',
                      colors,
                      icon: Icons.hourglass_top_rounded,
                      activeColor: colors.warning,
                    ),
                    if (groups.isNotEmpty) ...[
                      ...groups.map(
                        (g) => _buildFilterChip(
                          g.name,
                          'group:${g.id}',
                          colors,
                          icon: Icons.folder_special_rounded,
                          activeColor: Color(g.colorValue),
                        ),
                      ),
                    ],
                    ...categories.map(
                      (c) => _buildFilterChip(c.name, c.id, colors),
                    ),
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
                        description: _selectedFilter == 'all'
                            ? 'Your vault is currently empty. Tap below to scan or import your first document.'
                            : (_selectedFilter == 'temporary'
                                ? 'No temporary documents found.'
                                : 'No documents match the selected filter.'),
                        mascotPose: MascotPose.friendly,
                        actionLabel: 'Add Document',
                        onAction: () => context.push('/add-document'),
                      )
                    : RefreshIndicator(
                        color: colors.primaryAccent,
                        onRefresh: () async {
                          ref.invalidate(activeDocumentsProvider);
                          ref.invalidate(documentGroupsProvider);
                        },
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (ctx, i) {
                            return _buildDocCard(filtered[i], colors);
                          },
                        ),
                      ),
              ),
            ],
          );
        },
        loading: () => Center(
          child: CircularProgressIndicator(color: colors.primaryAccent),
        ),
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

  Widget _buildFilterChip(
    String label,
    String value,
    AppThemeColors colors, {
    IconData? icon,
    Color? activeColor,
  }) {
    final isSelected = _selectedFilter == value;
    final accent = activeColor ?? colors.primaryAccent;

    return Padding(
      padding: const EdgeInsets.only(right: 8.0),
      child: FilterChip(
        avatar: icon != null
            ? Icon(
                icon,
                size: 14,
                color: isSelected ? accent : colors.textSecondary,
              )
            : null,
        label: Text(label),
        selected: isSelected,
        onSelected: (selected) {
          setState(() {
            _selectedFilter = value;
          });
        },
        backgroundColor: colors.cardBackground,
        selectedColor: accent.withValues(alpha: 0.18),
        checkmarkColor: accent,
        labelStyle: TextStyle(
          color: isSelected ? accent : colors.textSecondary,
          fontSize: 12.5,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: isSelected ? accent : colors.cardBorder,
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
          color: doc.isTemporary && doc.isExpired
              ? colors.error.withValues(alpha: 0.5)
              : (doc.isTemporary
                  ? colors.warning.withValues(alpha: 0.3)
                  : colors.cardBorder),
        ),
      ),
      child: ListTile(
        onTap: () => context.push('/document/${doc.id}'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: (doc.isTemporary ? colors.warning : colors.primaryAccent)
                .withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            doc.isTemporary
                ? Icons.hourglass_top_rounded
                : Icons.description_outlined,
            color: doc.isTemporary ? colors.warning : colors.primaryAccent,
            size: 22,
          ),
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
              style: TextStyle(fontSize: 12.5, color: colors.textSecondary),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                if (doc.isTemporary) ...[
                  StatusBadge.fromTemporary(
                    doc.expiresAt,
                    isTemporary: true,
                  ),
                  const SizedBox(width: 8),
                ] else if (doc.expiryDate != null) ...[
                  StatusBadge.fromExpiry(doc.expiryDate),
                  const SizedBox(width: 8),
                ],
                Text(
                  '${doc.files.length} page${doc.files.length == 1 ? '' : 's'}',
                  style: TextStyle(fontSize: 11, color: colors.textTertiary),
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
