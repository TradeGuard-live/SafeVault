import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../../core/widgets/empty_state_view.dart';
import '../../../core/widgets/rupee_bunny_mascot.dart';
import '../../authentication/presentation/auth_providers.dart';
import '../domain/bank_account_model.dart';

class BankAccountListScreen extends ConsumerStatefulWidget {
  final String? initialType;
  final bool filterFavorites;

  const BankAccountListScreen({
    super.key,
    this.initialType,
    this.filterFavorites = false,
  });

  @override
  ConsumerState<BankAccountListScreen> createState() =>
      _BankAccountListScreenState();
}

class _BankAccountListScreenState extends ConsumerState<BankAccountListScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String? _selectedType;
  bool _onlyFavorites = false;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.initialType;
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
    final accountsAsync = ref.watch(allBankAccountsProvider);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text(
          'Bank Accounts',
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
            tooltip: 'Add Account',
            onPressed: () => context.push('/add-bank-account'),
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
                hintText: 'Search by bank name, nickname, or branch...',
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

          // Account Type Filter Chips
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: const Text('All'),
                    selected: _selectedType == null,
                    onSelected: (_) => setState(() => _selectedType = null),
                  ),
                ),
                ...['savings', 'current', 'salary', 'other'].map((type) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(type[0].toUpperCase() + type.substring(1)),
                      selected: _selectedType == type,
                      onSelected: (sel) {
                        setState(() => _selectedType = sel ? type : null);
                      },
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Accounts List
          Expanded(
            child: accountsAsync.when(
              data: (list) {
                var filtered = list;
                if (_onlyFavorites) {
                  filtered = filtered.where((a) => a.isFavorite).toList();
                }
                if (_selectedType != null) {
                  filtered = filtered
                      .where((a) => a.accountType == _selectedType)
                      .toList();
                }
                if (_searchQuery.isNotEmpty) {
                  filtered = filtered.where((a) {
                    final b = a.bankName.toLowerCase();
                    final n = (a.nickname ?? '').toLowerCase();
                    final br = (a.decryptedBranch ?? '').toLowerCase();
                    return b.contains(_searchQuery) ||
                        n.contains(_searchQuery) ||
                        br.contains(_searchQuery);
                  }).toList();
                }

                if (filtered.isEmpty) {
                  return EmptyStateView(
                    icon: Icons.search_off_rounded,
                    title: 'No bank accounts match your search',
                    message: 'Try clearing the filters or search bar.',
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
    BankAccountModel item,
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
              Icons.account_balance_rounded,
              color: colors.primaryAccent,
              size: 22,
            ),
          ),
        ),
        title: Text(
          item.bankName,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        subtitle: Text(
          '${item.nickname != null ? '${item.nickname} • ' : ''}${item.maskedAccountNumber}',
          style: TextStyle(fontSize: 12.5, color: colors.textSecondary),
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
        onTap: () => context.push('/bank-account/${item.id}'),
      ),
    );
  }
}
