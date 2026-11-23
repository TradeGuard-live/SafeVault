import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/security/authentication_gate.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/error_dialog.dart';
import '../../../core/widgets/status_badge.dart';
import '../../authentication/presentation/auth_providers.dart';
import '../../documents/domain/document_model.dart';
import '../domain/document_group_model.dart';
import 'add_documents_to_group_sheet.dart';
import 'add_edit_group_dialog.dart';
import 'group_picker_sheet.dart';

enum GroupDocSortOption { name, dateAdded, expiry }

class GroupDocumentsScreen extends ConsumerStatefulWidget {
  final String groupId;

  const GroupDocumentsScreen({
    super.key,
    required this.groupId,
  });

  @override
  ConsumerState<GroupDocumentsScreen> createState() =>
      _GroupDocumentsScreenState();
}

class _GroupDocumentsScreenState extends ConsumerState<GroupDocumentsScreen> {
  String _searchQuery = '';
  bool _isSearchActive = false;
  late TextEditingController _searchController;
  GroupDocSortOption _sortOption = GroupDocSortOption.dateAdded;

  bool _isMultiSelect = false;
  final Set<String> _selectedDocIds = {};

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
      ref.invalidate(groupDocumentsProvider(widget.groupId));
    }
  }

  Future<void> _deleteGroup(DocumentGroupModel group) async {
    final confirmed = await ErrorDialog.confirm(
      context,
      title: 'Delete Group?',
      message:
          'Are you sure you want to delete "${group.name}"?\n\n'
          'Documents in this group will NOT be deleted.',
      confirmLabel: 'Delete Group',
      isDestructive: true,
    );

    if (confirmed && mounted) {
      final repo = ref.read(documentGroupRepositoryProvider);
      await repo.deleteGroup(group.id);
      ref.invalidate(documentGroupsProvider);
      ref.invalidate(activeDocumentsProvider);
      if (mounted) {
        context.pop();
      }
    }
  }

  Future<void> _addDocuments(DocumentGroupModel group, List<DocumentModel> currentDocs) async {
    final existingIds = currentDocs.map((d) => d.id).toList();
    final selectedDocIds = await AddDocumentsToGroupSheet.show(
      context,
      group: group,
      existingMemberDocIds: existingIds,
    );

    if (selectedDocIds != null && selectedDocIds.isNotEmpty && mounted) {
      final repo = ref.read(documentGroupRepositoryProvider);
      await repo.addDocumentsToGroup(
        documentIds: selectedDocIds,
        groupId: group.id,
      );
      ref.invalidate(groupDocumentsProvider(widget.groupId));
      ref.invalidate(documentGroupsProvider);
      ref.invalidate(activeDocumentsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Added ${selectedDocIds.length} document${selectedDocIds.length == 1 ? '' : 's'} to "${group.name}".',
            ),
          ),
        );
      }
    }
  }

  Future<void> _removeDocFromGroup(DocumentModel doc, DocumentGroupModel group) async {
    final repo = ref.read(documentGroupRepositoryProvider);
    await repo.removeDocumentsFromGroup(
      documentIds: [doc.id],
      groupId: group.id,
    );
    ref.invalidate(groupDocumentsProvider(widget.groupId));
    ref.invalidate(documentGroupsProvider);
    ref.invalidate(activeDocumentsProvider);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Removed "${doc.name}" from "${group.name}".')),
      );
    }
  }

  Future<void> _moveToTrash(DocumentModel doc) async {
    final confirmed = await ErrorDialog.confirm(
      context,
      title: 'Move to Trash?',
      message: 'Move "${doc.name}" to Trash?',
      confirmLabel: 'Move to Trash',
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;

    final gate = ref.read(authenticationGateProvider);
    final verified = await gate.authenticateForAction(
      context,
      action: PendingVaultAction(
        type: VaultActionType.deleteDocument,
        targetId: doc.id,
        targetName: doc.name,
        returnRoute: '/group-documents/${widget.groupId}',
      ),
      title: 'Authorize Move to Trash',
      reason: 'Confirm to delete "${doc.name}".',
    );
    if (!verified || !mounted) return;

    final repo = ref.read(documentRepositoryProvider);
    await repo.moveToTrash(doc.id);
    ref.invalidate(groupDocumentsProvider(widget.groupId));
    ref.invalidate(documentGroupsProvider);
    ref.invalidate(activeDocumentsProvider);
    ref.invalidate(trashDocumentsProvider);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${doc.name}" moved to Trash.')),
      );
    }
  }

  // Batch actions
  Future<void> _batchRemoveFromGroup(DocumentGroupModel group) async {
    if (_selectedDocIds.isEmpty) return;
    final repo = ref.read(documentGroupRepositoryProvider);
    await repo.removeDocumentsFromGroup(
      documentIds: _selectedDocIds.toList(),
      groupId: group.id,
    );
    final count = _selectedDocIds.length;
    setState(() {
      _selectedDocIds.clear();
      _isMultiSelect = false;
    });
    ref.invalidate(groupDocumentsProvider(widget.groupId));
    ref.invalidate(documentGroupsProvider);
    ref.invalidate(activeDocumentsProvider);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Removed $count documents from "${group.name}".')),
      );
    }
  }

  Future<void> _batchMoveToTrash() async {
    if (_selectedDocIds.isEmpty) return;
    final confirmed = await ErrorDialog.confirm(
      context,
      title: 'Move Selected to Trash?',
      message: 'Move ${_selectedDocIds.length} documents to Trash?',
      confirmLabel: 'Move to Trash',
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;

    final repo = ref.read(documentRepositoryProvider);
    for (final id in _selectedDocIds) {
      await repo.moveToTrash(id);
    }
    final count = _selectedDocIds.length;
    setState(() {
      _selectedDocIds.clear();
      _isMultiSelect = false;
    });
    ref.invalidate(groupDocumentsProvider(widget.groupId));
    ref.invalidate(documentGroupsProvider);
    ref.invalidate(activeDocumentsProvider);
    ref.invalidate(trashDocumentsProvider);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Moved $count documents to Trash.')),
      );
    }
  }

  Future<void> _batchAssignToAnotherGroup() async {
    if (_selectedDocIds.isEmpty) return;
    final newGroupIds = await GroupPickerSheet.show(
      context,
      initialSelectedGroupIds: [widget.groupId],
    );
    if (newGroupIds != null && newGroupIds.isNotEmpty && mounted) {
      final repo = ref.read(documentGroupRepositoryProvider);
      for (final targetGroupId in newGroupIds) {
        if (targetGroupId != widget.groupId) {
          await repo.addDocumentsToGroup(
            documentIds: _selectedDocIds.toList(),
            groupId: targetGroupId,
          );
        }
      }
      final count = _selectedDocIds.length;
      setState(() {
        _selectedDocIds.clear();
        _isMultiSelect = false;
      });
      ref.invalidate(groupDocumentsProvider(widget.groupId));
      ref.invalidate(documentGroupsProvider);
      ref.invalidate(activeDocumentsProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Assigned $count documents to selected groups.')),
        );
      }
    }
  }

  List<DocumentModel> _processDocs(List<DocumentModel> docs) {
    var filtered = docs;
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      filtered = filtered.where((d) {
        final nameMatch = d.name.toLowerCase().contains(q);
        final notesMatch = d.notes?.toLowerCase().contains(q) ?? false;
        final docNumMatch = d.documentNumber?.toLowerCase().contains(q) ?? false;
        return nameMatch || notesMatch || docNumMatch;
      }).toList();
    }

    switch (_sortOption) {
      case GroupDocSortOption.name:
        filtered.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case GroupDocSortOption.dateAdded:
        filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case GroupDocSortOption.expiry:
        filtered.sort((a, b) {
          if (a.expiresAt == null && b.expiresAt == null) return 0;
          if (a.expiresAt == null) return 1;
          if (b.expiresAt == null) return -1;
          return a.expiresAt!.compareTo(b.expiresAt!);
        });
        break;
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final groupsAsync = ref.watch(documentGroupsProvider);
    final docsAsync = ref.watch(groupDocumentsProvider(widget.groupId));

    // Find the current group
    final currentGroup = groupsAsync.maybeWhen(
      data: (groups) => groups.where((g) => g.id == widget.groupId).firstOrNull,
      orElse: () => null,
    );

    final groupColor = currentGroup != null
        ? Color(currentGroup.colorValue)
        : colors.primaryAccent;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: _isSearchActive
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search inside group...',
                  hintStyle: TextStyle(color: colors.textSecondary),
                  border: InputBorder.none,
                ),
                style: TextStyle(color: colors.textPrimary),
                onChanged: (val) => setState(() => _searchQuery = val),
              )
            : Text(
                _isMultiSelect
                    ? '${_selectedDocIds.length} Selected'
                    : (currentGroup?.name ?? 'Group Documents'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
        actions: [
          if (_isMultiSelect) ...[
            IconButton(
              icon: const Icon(Icons.drive_file_move_outlined),
              tooltip: 'Assign to Another Group',
              onPressed: _batchAssignToAnotherGroup,
            ),
            IconButton(
              icon: const Icon(Icons.folder_off_outlined),
              tooltip: 'Remove from Group',
              onPressed: currentGroup != null
                  ? () => _batchRemoveFromGroup(currentGroup)
                  : null,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: 'Move to Trash',
              onPressed: _batchMoveToTrash,
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded),
              tooltip: 'Cancel',
              onPressed: () {
                setState(() {
                  _isMultiSelect = false;
                  _selectedDocIds.clear();
                });
              },
            ),
          ] else ...[
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
            PopupMenuButton<GroupDocSortOption>(
              icon: const Icon(Icons.sort_rounded),
              tooltip: 'Sort Documents',
              onSelected: (val) => setState(() => _sortOption = val),
              itemBuilder: (context) => [
                CheckedPopupMenuItem(
                  value: GroupDocSortOption.dateAdded,
                  checked: _sortOption == GroupDocSortOption.dateAdded,
                  child: const Text('Recently Added'),
                ),
                CheckedPopupMenuItem(
                  value: GroupDocSortOption.name,
                  checked: _sortOption == GroupDocSortOption.name,
                  child: const Text('Name (A-Z)'),
                ),
                CheckedPopupMenuItem(
                  value: GroupDocSortOption.expiry,
                  checked: _sortOption == GroupDocSortOption.expiry,
                  child: const Text('Expiry Date'),
                ),
              ],
            ),
            if (currentGroup != null)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (val) {
                  if (val == 'edit') {
                    _editGroup(currentGroup);
                  } else if (val == 'delete') {
                    _deleteGroup(currentGroup);
                  }
                },
                itemBuilder: (context) => [
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
        ],
      ),
      body: Column(
        children: [
          // Group Header Banner
          if (currentGroup != null)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              decoration: BoxDecoration(
                color: groupColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: groupColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: groupColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: groupColor, width: 1.5),
                    ),
                    child: Icon(
                      _getIconData(currentGroup.icon),
                      color: groupColor,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          currentGroup.name,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: colors.textPrimary,
                          ),
                        ),
                        if (currentGroup.description != null &&
                            currentGroup.description!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            currentGroup.description!,
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  docsAsync.maybeWhen(
                    data: (docs) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: groupColor,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${docs.length} ${docs.length == 1 ? 'doc' : 'docs'}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    orElse: () => const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          Expanded(
            child: docsAsync.when(
              data: (rawDocs) {
                final docs = _processDocs(rawDocs);
                if (docs.isEmpty) {
                  return _buildEmptyState(currentGroup, rawDocs, colors);
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final isSelected = _selectedDocIds.contains(doc.id);

                    return _buildDocCard(
                      doc,
                      currentGroup,
                      isSelected,
                      colors,
                    );
                  },
                );
              },
              loading: () => Center(
                child: CircularProgressIndicator(color: groupColor),
              ),
              error: (err, _) => Center(
                child: Text('Error: $err', style: TextStyle(color: colors.error)),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: currentGroup != null
          ? FloatingActionButton.extended(
              onPressed: () {
                final currentDocs = docsAsync.maybeWhen(
                  data: (docs) => docs,
                  orElse: () => <DocumentModel>[],
                );
                _addDocuments(currentGroup, currentDocs);
              },
              backgroundColor: groupColor,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Documents'),
            )
          : null,
    );
  }

  Widget _buildEmptyState(
    DocumentGroupModel? group,
    List<DocumentModel> allGroupDocs,
    AppThemeColors colors,
  ) {
    if (_searchQuery.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.search_off_rounded,
                size: 56,
                color: colors.textSecondary.withValues(alpha: 0.4),
              ),
              const SizedBox(height: 12),
              Text(
                'No Matching Documents',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'No documents in this group matched "$_searchQuery".',
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
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
              Icons.folder_open_rounded,
              size: 68,
              color: colors.textSecondary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              'No Documents in this Group',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add existing vault documents to organize them inside this custom group.',
              style: TextStyle(fontSize: 13, color: colors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            if (group != null)
              ElevatedButton.icon(
                onPressed: () => _addDocuments(group, allGroupDocs),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add Documents to Group'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(group.colorValue),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocCard(
    DocumentModel doc,
    DocumentGroupModel? group,
    bool isSelected,
    AppThemeColors colors,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelected ? colors.primaryAccent : colors.cardBorder,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onLongPress: () {
          setState(() {
            _isMultiSelect = true;
            _selectedDocIds.add(doc.id);
          });
        },
        onTap: () {
          if (_isMultiSelect) {
            setState(() {
              if (isSelected) {
                _selectedDocIds.remove(doc.id);
                if (_selectedDocIds.isEmpty) _isMultiSelect = false;
              } else {
                _selectedDocIds.add(doc.id);
              }
            });
          } else {
            context.push('/document/${doc.id}');
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              if (_isMultiSelect) ...[
                Checkbox(
                  value: isSelected,
                  activeColor: colors.primaryAccent,
                  onChanged: (val) {
                    setState(() {
                      if (val == true) {
                        _selectedDocIds.add(doc.id);
                      } else {
                        _selectedDocIds.remove(doc.id);
                        if (_selectedDocIds.isEmpty) _isMultiSelect = false;
                      }
                    });
                  },
                ),
                const SizedBox(width: 8),
              ],
              Container(
                width: 42,
                height: 42,
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
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doc.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text(
                          doc.documentType ?? 'Document',
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.textSecondary,
                          ),
                        ),
                        if (doc.isTemporary && doc.expiresAt != null) ...[
                          Text(
                            ' • ${doc.temporaryStatusLabel}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: colors.warning,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (!_isMultiSelect && group != null)
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert_rounded, color: colors.textSecondary),
                  onSelected: (val) {
                    if (val == 'open') {
                      context.push('/document/${doc.id}');
                    } else if (val == 'remove') {
                      _removeDocFromGroup(doc, group);
                    } else if (val == 'trash') {
                      _moveToTrash(doc);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'open',
                      child: Row(
                        children: [
                          Icon(Icons.visibility_outlined, size: 18),
                          SizedBox(width: 10),
                          Text('Open Document'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'remove',
                      child: Row(
                        children: [
                          Icon(Icons.folder_off_outlined, size: 18),
                          SizedBox(width: 10),
                          Text('Remove from Group'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'trash',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                          SizedBox(width: 10),
                          Text('Move to Trash', style: TextStyle(color: Colors.red)),
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
  }
}
