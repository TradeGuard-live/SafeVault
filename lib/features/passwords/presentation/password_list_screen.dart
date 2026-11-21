import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../../core/widgets/empty_state_view.dart';
import '../../../core/widgets/rupee_bunny_mascot.dart';
import '../../authentication/presentation/auth_providers.dart';
import '../domain/password_entry_model.dart';

class PasswordListScreen extends ConsumerStatefulWidget {
  final String? initialCategory;
  final bool filterFavorites;

  const PasswordListScreen({
    super.key,
    this.initialCategory,
    this.filterFavorites = false,
  });

  @override
  ConsumerState<PasswordListScreen> createState() => _PasswordListScreenState();
}

class _PasswordListScreenState extends ConsumerState<PasswordListScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String? _selectedCategory;
  bool _onlyFavorites = false;

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory;
    _onlyFavorites = widget.filterFavorites;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final passwordsAsync = ref.watch(allPasswordsProvider);
    final categoriesAsync = ref.watch(passwordCategoriesProvider);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text(
          'Saved Passwords',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: Icon(
              _onlyFavorites ? Icons.star_rounded : Icons.star_border_rounded,
              color: _onlyFavorites ? Colors.amber : null,
            ),
            tooltip: 'Filter Favorites',
            onPressed: () {
              setState(() => _onlyFavorites = !_onlyFavorites);
            },
          ),
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Add Password',
            onPressed: () => context.push('/add-password'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search Field
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (val) =>
                  setState(() => _searchQuery = val.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search by title, username, or website...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 0,
                  horizontal: 16,
                ),
              ),
            ),
          ),

          // Category Chips Row
          categoriesAsync.when(
            data: (cats) {
              return SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: const Text('All'),
                        selected: _selectedCategory == null,
                        onSelected: (_) =>
                            setState(() => _selectedCategory = null),
                      ),
                    ),
                    ...cats.map((c) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(c.name),
                          selected: _selectedCategory == c.id,
                          onSelected: (sel) {
                            setState(
                              () => _selectedCategory = sel ? c.id : null,
                            );
                          },
                        ),
                      );
                    }),
                  ],
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 8),

          // Passwords List
          Expanded(
            child: passwordsAsync.when(
              data: (list) {
                var filtered = list;
                if (_onlyFavorites) {
                  filtered = filtered.where((p) => p.isFavorite).toList();
                }
                if (_selectedCategory != null) {
                  filtered = filtered
                      .where((p) => p.categoryId == _selectedCategory)
                      .toList();
                }
                if (_searchQuery.isNotEmpty) {
                  filtered = filtered.where((p) {
                    final t = p.title.toLowerCase();
                    final u = (p.decryptedUsername ?? '').toLowerCase();
                    final e = (p.decryptedEmail ?? '').toLowerCase();
                    final w = (p.websiteUrl ?? '').toLowerCase();
                    return t.contains(_searchQuery) ||
                        u.contains(_searchQuery) ||
                        e.contains(_searchQuery) ||
                        w.contains(_searchQuery);
                  }).toList();
                }

                if (filtered.isEmpty) {
                  return EmptyStateView(
                    icon: Icons.search_off_rounded,
                    title: 'No matching credentials',
                    message: 'Try clearing filters or search query.',
                    mascotPose: MascotPose.thinking,
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final item = filtered[i];
                    return _buildListItem(context, item, colors);
                  },
                );
              },
              loading: () => Center(
                child: CircularProgressIndicator(color: colors.primaryAccent),
              ),
              error: (err, _) => Center(child: Text('Error: $err')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListItem(
    BuildContext context,
    PasswordEntryModel item,
    AppThemeColors colors,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.cardBorder),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: colors.primaryAccent.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Icon(
              Icons.key_rounded,
              color: colors.primaryAccent,
              size: 22,
            ),
          ),
        ),
        title: Text(
          item.title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        subtitle: Text(
          item.decryptedUsername ?? item.decryptedEmail ?? 'No username',
          style: TextStyle(fontSize: 13, color: colors.textSecondary),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item.isFavorite)
              const Icon(Icons.star_rounded, color: Colors.amber, size: 20),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, size: 20),
          ],
        ),
        onTap: () => context.push('/password/${item.id}'),
      ),
    );
  }
}
