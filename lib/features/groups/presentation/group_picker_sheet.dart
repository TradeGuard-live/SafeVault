import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../authentication/presentation/auth_providers.dart';
import '../domain/document_group_model.dart';
import 'add_edit_group_dialog.dart';

class GroupPickerSheet extends ConsumerStatefulWidget {
  final List<String> initialSelectedGroupIds;

  const GroupPickerSheet({
    super.key,
    required this.initialSelectedGroupIds,
  });

  static Future<List<String>?> show(
    BuildContext context, {
    required List<String> initialSelectedGroupIds,
  }) {
    return showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => GroupPickerSheet(
        initialSelectedGroupIds: initialSelectedGroupIds,
      ),
    );
  }

  @override
  ConsumerState<GroupPickerSheet> createState() => _GroupPickerSheetState();
}

class _GroupPickerSheetState extends ConsumerState<GroupPickerSheet> {
  late Set<String> _selectedIds;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _selectedIds = Set.from(widget.initialSelectedGroupIds);
  }

  IconData _getIconData(String name) {
    switch (name) {
      case 'person_rounded':
        return Icons.person_rounded;
      case 'directions_car_rounded':
        return Icons.directions_car_rounded;
      case 'school_rounded':
        return Icons.school_rounded;
      case 'local_hospital_rounded':
        return Icons.local_hospital_rounded;
      case 'account_balance_rounded':
        return Icons.account_balance_rounded;
      case 'home_rounded':
        return Icons.home_rounded;
      case 'shield_rounded':
        return Icons.shield_rounded;
      case 'family_restroom_rounded':
        return Icons.family_restroom_rounded;
      case 'work_rounded':
        return Icons.work_rounded;
      case 'flight_rounded':
        return Icons.flight_rounded;
      case 'receipt_long_rounded':
        return Icons.receipt_long_rounded;
      case 'business_center_rounded':
        return Icons.business_center_rounded;
      case 'card_membership_rounded':
        return Icons.card_membership_rounded;
      case 'badge_rounded':
        return Icons.badge_rounded;
      default:
        return Icons.folder_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final groupsAsync = ref.watch(documentGroupsProvider);

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colors.cardBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.collections_bookmark_rounded, color: colors.primaryAccent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Assign to Groups',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final created = await AddEditGroupDialog.show(context);
                    if (created != null && mounted) {
                      setState(() => _selectedIds.add(created.id));
                    }
                  },
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('New Group'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search groups...',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                filled: true,
                fillColor: colors.cardBackground,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          Expanded(
            child: groupsAsync.when(
              data: (groups) {
                final filtered = _searchQuery.isEmpty
                    ? groups
                    : groups
                        .where((g) =>
                            g.name.toLowerCase().contains(_searchQuery) ||
                            (g.description?.toLowerCase().contains(_searchQuery) ?? false))
                        .toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.folder_off_outlined, size: 48, color: colors.textTertiary),
                          const SizedBox(height: 12),
                          Text(
                            groups.isEmpty
                                ? 'No custom groups created yet.'
                                : 'No groups matching "$_searchQuery"',
                            style: TextStyle(color: colors.textSecondary),
                          ),
                          const SizedBox(height: 16),
                          FilledButton.tonalIcon(
                            onPressed: () async {
                              final created = await AddEditGroupDialog.show(context);
                              if (created != null && mounted) {
                                setState(() => _selectedIds.add(created.id));
                              }
                            },
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Create First Group'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, i) {
                    final group = filtered[i];
                    final isChecked = _selectedIds.contains(group.id);

                    return InkWell(
                      onTap: () {
                        setState(() {
                          if (isChecked) {
                            _selectedIds.remove(group.id);
                          } else {
                            _selectedIds.add(group.id);
                          }
                        });
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isChecked
                              ? Color(group.colorValue).withOpacity(0.08)
                              : colors.cardBackground,
                          border: Border.all(
                            color: isChecked
                                ? Color(group.colorValue).withOpacity(0.4)
                                : colors.cardBorder,
                            width: isChecked ? 1.5 : 1,
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Color(group.colorValue).withOpacity(0.18),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                _getIconData(group.icon),
                                color: Color(group.colorValue),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    group.name,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                      color: colors.textPrimary,
                                    ),
                                  ),
                                  if (group.description != null && group.description!.isNotEmpty)
                                    Text(
                                      group.description!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: colors.textSecondary,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Checkbox(
                              value: isChecked,
                              activeColor: Color(group.colorValue),
                              onChanged: (val) {
                                setState(() {
                                  if (val == true) {
                                    _selectedIds.add(group.id);
                                  } else {
                                    _selectedIds.remove(group.id);
                                  }
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(_selectedIds.toList()),
                style: FilledButton.styleFrom(
                  backgroundColor: colors.primaryAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text('Done (${_selectedIds.length} Selected)'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
