import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../../core/widgets/error_dialog.dart';
import '../../authentication/presentation/auth_providers.dart';
import '../domain/document_group_model.dart';
import 'add_edit_group_dialog.dart';

class DocumentGroupsScreen extends ConsumerStatefulWidget {
  const DocumentGroupsScreen({super.key});

  @override
  ConsumerState<DocumentGroupsScreen> createState() =>
      _DocumentGroupsScreenState();
}

class _DocumentGroupsScreenState extends ConsumerState<DocumentGroupsScreen> {
  String _searchQuery = '';
  bool _isSearchActive = false;
  late TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

  Future<void> _createGroup() async {
    final result = await AddEditGroupDialog.show(context);
    if (result != null && mounted) {
      final repo = ref.read(documentGroupRepositoryProvider);
      await repo.createGroup(
        name: result.name,
        description: result.description,
        icon: result.icon,
        colorValue: result.colorValue,
      );
      ref.invalidate(documentGroupsProvider);
      ref.invalidate(activeDocumentsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Group "${result.name}" created.')),
        );
      }
    }
  }

  Future<void> _editGroup(DocumentGroupModel group) async {
    final result = await AddEditGroupDialog.show(
      context,
      editGroup: group,
    );
    if (result != null && mounted) {
      final repo = ref.read(documentGroupRepositoryProvider);
      await repo.updateGroup(
        id: group.id,
        name: result.name,
        description: result.description,
        icon: result.icon,
        colorValue: result.colorValue,
      );
      ref.invalidate(documentGroupsProvider);
      ref.invalidate(activeDocumentsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Group "${result.name}" updated.')),
        );
      }
    }
  }

  Future<void> _deleteGroup(DocumentGroupModel group) async {
    final confirmed = await ErrorDialog.confirm(
      context,
      title: 'Delete Group?',
      message:
          'Are you sure you want to delete "${group.name}"?\n\n'
          'Documents inside this group will NOT be deleted.',
      confirmLabel: 'Delete Group',
      isDestructive: true,
    );

    if (confirmed && mounted) {
      final repo = ref.read(documentGroupRepositoryProvider);
      await repo.deleteGroup(group.id);
      ref.invalidate(documentGroupsProvider);
      ref.invalidate(activeDocumentsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Group "${group.name}" deleted.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final groupsAsync = ref.watch(documentGroupsProvider);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: _isSearchActive
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search groups...',
                  hintStyle: TextStyle(color: colors.textSecondary),
                  border: InputBorder.none,
                ),
                style: TextStyle(color: colors.textPrimary),
                onChanged: (val) => setState(() => _searchQuery = val),
              )
            : const Text(
                'Document Groups',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
        actions: [
          IconButton(
            icon: Icon(_isSearchActive ? Icons.close_rounded : Icons.search_rounded),
            tooltip: _isSearchActive ? 'Close' : 'Search',
            onPressed: () {
              setState(() {
                if (_isSearchActive) {
                  _isSearchActive = false;
                  _searchQuery = '';
                  _searchController.clear();
                } else {
                  _isSearchActive = true;
                }
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'New Group',
            onPressed: _createGroup,
          ),
        ],
      ),
      body: groupsAsync.when(
        data: (allGroups) {
          final groups = _searchQuery.trim().isEmpty
              ? allGroups
              : allGroups.where((g) {
                  final q = _searchQuery.trim().toLowerCase();
                  return g.name.toLowerCase().contains(q) ||
                      (g.description?.toLowerCase().contains(q) ?? false);
                }).toList();

          if (groups.isEmpty) {
            return _buildEmptyState(colors);
          }

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(documentGroupsProvider);
            },
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: groups.length,
              itemBuilder: (context, index) {
                final group = groups[index];
                final groupColor = Color(group.colorValue);

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: colors.cardBackground,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colors.cardBorder),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => context.push('/group-documents/${group.id}'),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: groupColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: groupColor.withValues(alpha: 0.4),
                                width: 1.5,
                              ),
                            ),
                            child: Icon(
                              _getIconData(group.icon),
                              color: groupColor,
                              size: 26,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        group.name,
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: colors.textPrimary,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: colors.surface,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: colors.cardBorder),
                                      ),
                                      child: Text(
                                        '${group.documentCount} ${group.documentCount == 1 ? 'doc' : 'docs'}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: colors.textSecondary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (group.description != null &&
                                    group.description!.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    group.description!,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: colors.textSecondary,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 4),
                          PopupMenuButton<String>(
                            icon: Icon(
                              Icons.more_vert_rounded,
                              color: colors.textSecondary,
                            ),
                            onSelected: (val) {
                              if (val == 'open') {
                                context.push('/group-documents/${group.id}');
                              } else if (val == 'edit') {
                                _editGroup(group);
                              } else if (val == 'delete') {
                                _deleteGroup(group);
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'open',
                                child: Row(
                                  children: [
                                    Icon(Icons.folder_open_rounded, size: 18),
                                    SizedBox(width: 10),
                                    Text('Open Group'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'edit',
                                child: Row(
                                  children: [
                                    Icon(Icons.edit_outlined, size: 18),
                                    SizedBox(width: 10),
                                    Text('Edit Group'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                                    SizedBox(width: 10),
                                    Text('Delete Group', style: TextStyle(color: Colors.red)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
        loading: () => Center(
          child: CircularProgressIndicator(color: colors.primaryAccent),
        ),
        error: (err, _) => Center(
          child: Text(
            'Failed to load groups: $err',
            style: TextStyle(color: colors.error),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createGroup,
        backgroundColor: colors.primaryAccent,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.create_new_folder_rounded),
        label: const Text('New Group'),
      ),
    );
  }

  Widget _buildEmptyState(AppThemeColors colors) {
    if (_searchQuery.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.search_off_rounded,
                size: 64,
                color: colors.textSecondary.withValues(alpha: 0.4),
              ),
              const SizedBox(height: 16),
              Text(
                'No Groups Found',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'No custom groups match "$_searchQuery".',
                style: TextStyle(fontSize: 13, color: colors.textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.folder_special_outlined,
              size: 68,
              color: colors.primaryAccent.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No Custom Groups Yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create custom groups to organize documents across projects, taxes, family, travel, and more.',
              style: TextStyle(fontSize: 13, color: colors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _createGroup,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Create First Group'),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primaryAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
