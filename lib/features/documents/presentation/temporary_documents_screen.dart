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
import '../../groups/domain/document_group_model.dart';
import '../domain/document_model.dart';
import 'edit_duration_dialog.dart';

enum TemporaryFilterTab { all, expiringSoon, expired }

class TemporaryDocumentsScreen extends ConsumerStatefulWidget {
  const TemporaryDocumentsScreen({super.key});

  @override
  ConsumerState<TemporaryDocumentsScreen> createState() =>
      _TemporaryDocumentsScreenState();
}

class _TemporaryDocumentsScreenState
    extends ConsumerState<TemporaryDocumentsScreen> {
  TemporaryFilterTab _selectedTab = TemporaryFilterTab.all;
  String _searchQuery = '';
  bool _isSearchActive = false;
  late TextEditingController _searchController;

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

  IconData _getGroupIcon(String name) {
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

  Future<void> _makePermanent(DocumentModel doc) async {
    final session = ref.read(vaultSessionProvider);
    if (!session.isUnlocked || session.masterKey == null) return;

    final repo = ref.read(documentRepositoryProvider);
    await repo.setPermanent(
      documentId: doc.id,
      masterKey: session.masterKey!,
    );
    ref.invalidate(temporaryDocumentsProvider);
    ref.invalidate(expiringSoonTemporaryDocumentsProvider);
    ref.invalidate(activeDocumentsProvider);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${doc.name}" converted to Permanent.')),
      );
    }
  }

  Future<void> _editDuration(DocumentModel doc) async {
    final session = ref.read(vaultSessionProvider);
    if (!session.isUnlocked || session.masterKey == null) return;

    await EditDurationDialog.show(
      context,
      document: doc,
      onSave: (isTemporary, expiresAt) async {
        final repo = ref.read(documentRepositoryProvider);
        if (isTemporary && expiresAt != null) {
          await repo.setTemporary(
            documentId: doc.id,
            expiresAt: expiresAt,
            masterKey: session.masterKey!,
          );
        } else {
          await repo.setPermanent(
            documentId: doc.id,
            masterKey: session.masterKey!,
          );
        }
        ref.invalidate(temporaryDocumentsProvider);
        ref.invalidate(expiringSoonTemporaryDocumentsProvider);
        ref.invalidate(activeDocumentsProvider);
      },
    );
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
        returnRoute: '/temporary-documents',
      ),
      title: 'Authorize Move to Trash',
      reason: 'Confirm to move "${doc.name}" to Trash.',
    );
    if (!verified || !mounted) return;

    final repo = ref.read(documentRepositoryProvider);
    await repo.moveToTrash(doc.id);
    ref.invalidate(temporaryDocumentsProvider);
    ref.invalidate(expiringSoonTemporaryDocumentsProvider);
    ref.invalidate(activeDocumentsProvider);
    ref.invalidate(trashDocumentsProvider);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${doc.name}" moved to Trash.')),
      );
    }
  }

  // Batch actions
  Future<void> _batchMakePermanent() async {
    if (_selectedDocIds.isEmpty) return;
    final session = ref.read(vaultSessionProvider);
    if (!session.isUnlocked || session.masterKey == null) return;

    final repo = ref.read(documentRepositoryProvider);
    for (final id in _selectedDocIds) {
      await repo.setPermanent(documentId: id, masterKey: session.masterKey!);
    }
    final count = _selectedDocIds.length;
    setState(() {
      _selectedDocIds.clear();
      _isMultiSelect = false;
    });
    ref.invalidate(temporaryDocumentsProvider);
    ref.invalidate(expiringSoonTemporaryDocumentsProvider);
    ref.invalidate(activeDocumentsProvider);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$count documents converted to Permanent.')),
      );
    }
  }

  Future<void> _batchMoveToTrash() async {
    if (_selectedDocIds.isEmpty) return;
    final confirmed = await ErrorDialog.confirm(
      context,
      title: 'Move Selected to Trash?',
      message:
          'Move ${_selectedDocIds.length} selected temporary documents to Trash?',
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
    ref.invalidate(temporaryDocumentsProvider);
    ref.invalidate(expiringSoonTemporaryDocumentsProvider);
    ref.invalidate(activeDocumentsProvider);
    ref.invalidate(trashDocumentsProvider);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$count documents moved to Trash.')),
      );
    }
  }

  List<DocumentModel> _filterDocs(List<DocumentModel> docs) {
    var filtered = docs;
    switch (_selectedTab) {
      case TemporaryFilterTab.all:
        break;
      case TemporaryFilterTab.expiringSoon:
        filtered = filtered.where((d) {
          if (d.expiresAt == null) return false;
          final days = d.remainingDays ?? 999;
          return days <= 7 && !d.isExpired;
        }).toList();
        break;
      case TemporaryFilterTab.expired:
        filtered = filtered.where((d) => d.isExpired || d.expiryStatus == 'EXPIRED').toList();
        break;
    }

    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      filtered = filtered.where((d) {
        final nameMatch = d.name.toLowerCase().contains(q);
        final notesMatch = d.notes?.toLowerCase().contains(q) ?? false;
        final docNumMatch = d.documentNumber?.toLowerCase().contains(q) ?? false;
        return nameMatch || notesMatch || docNumMatch;
      }).toList();
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final docsAsync = ref.watch(temporaryDocumentsProvider);
    final groupsAsync = ref.watch(documentGroupsProvider);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: _isSearchActive
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search temporary documents...',
                  hintStyle: TextStyle(color: colors.textSecondary),
                  border: InputBorder.none,
                ),
                style: TextStyle(color: colors.textPrimary),
                onChanged: (val) => setState(() => _searchQuery = val),
              )
            : Text(
                _isMultiSelect
                    ? '${_selectedDocIds.length} Selected'
                    : 'Temporary Documents',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
        actions: [
          if (_isMultiSelect) ...[
            IconButton(
              icon: const Icon(Icons.shield_outlined),
              tooltip: 'Make Permanent',
              onPressed: _batchMakePermanent,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: 'Move to Trash',
              onPressed: _batchMoveToTrash,
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded),
              tooltip: 'Cancel Selection',
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
              tooltip: _isSearchActive ? 'Close Search' : 'Search',
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
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Refresh',
              onPressed: () {
                ref.invalidate(temporaryDocumentsProvider);
                ref.invalidate(expiringSoonTemporaryDocumentsProvider);
              },
            ),
          ],
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildTabChip(TemporaryFilterTab.all, 'All Temporary', colors),
                  const SizedBox(width: 8),
                  _buildTabChip(TemporaryFilterTab.expiringSoon, 'Expiring Soon (≤7d)', colors),
                  const SizedBox(width: 8),
                  _buildTabChip(TemporaryFilterTab.expired, 'Expired', colors),
                ],
              ),
            ),
          ),
        ),
      ),
      body: docsAsync.when(
        data: (allDocs) {
          final docs = _filterDocs(allDocs);
          if (docs.isEmpty) {
            return _buildEmptyState(colors);
          }

          final groupsMap = groupsAsync.maybeWhen(
            data: (groups) => {for (var g in groups) g.id: g},
            orElse: () => <String, DocumentGroupModel>{},
          );

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final isSelected = _selectedDocIds.contains(doc.id);
              final docGroups = doc.groupIds
                  .map((gid) => groupsMap[gid])
                  .whereType<DocumentGroupModel>()
                  .toList();

              return _buildDocCard(doc, docGroups, isSelected, colors);
            },
          );
        },
        loading: () => Center(
          child: CircularProgressIndicator(color: colors.primaryAccent),
        ),
        error: (err, _) => Center(
          child: Text(
            'Error loading temporary documents: $err',
            style: TextStyle(color: colors.error),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/add-document'),
        backgroundColor: colors.primaryAccent,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Document'),
      ),
    );
  }

  Widget _buildTabChip(
    TemporaryFilterTab tab,
    String label,
    AppThemeColors colors,
  ) {
    final isSelected = _selectedTab == tab;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) setState(() => _selectedTab = tab);
      },
      selectedColor: colors.primaryAccent.withValues(alpha: 0.18),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
        color: isSelected ? colors.primaryAccent : colors.textSecondary,
      ),
    );
  }

  Widget _buildEmptyState(AppThemeColors colors) {
    String title = 'No Temporary Documents';
    String desc =
        'Temporary documents with automatic expiry will appear here.';
    IconData icon = Icons.hourglass_empty_rounded;

    if (_selectedTab == TemporaryFilterTab.expiringSoon) {
      title = 'No Documents Expiring Soon';
      desc = 'There are no temporary documents expiring within the next 7 days.';
      icon = Icons.event_available_rounded;
    } else if (_selectedTab == TemporaryFilterTab.expired) {
      title = 'No Expired Documents';
      desc = 'Expired temporary documents will be listed here before or after moving to Trash.';
      icon = Icons.done_all_rounded;
    } else if (_searchQuery.isNotEmpty) {
      title = 'No Matching Documents';
      desc = 'No temporary documents matched "$_searchQuery".';
      icon = Icons.search_off_rounded;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: colors.textSecondary.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              desc,
              style: TextStyle(fontSize: 13, color: colors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocCard(
    DocumentModel doc,
    List<DocumentGroupModel> groups,
    bool isSelected,
    AppThemeColors colors,
  ) {
    final remainingDays = doc.remainingDays;
    final isExpired = doc.isExpired || (remainingDays != null && remainingDays <= 0);
    final isUrgent = remainingDays != null && remainingDays <= 3 && !isExpired;

    Color badgeColor = colors.primaryAccent;
    if (isExpired) {
      badgeColor = colors.error;
    } else if (isUrgent) {
      badgeColor = colors.warning;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? colors.primaryAccent
              : (isExpired
                  ? colors.error.withValues(alpha: 0.4)
                  : isUrgent
                      ? colors.warning.withValues(alpha: 0.4)
                      : colors.cardBorder),
          width: isSelected || isUrgent || isExpired ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
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
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isExpired
                          ? Icons.event_busy_rounded
                          : (isUrgent
                              ? Icons.alarm_on_rounded
                              : Icons.hourglass_top_rounded),
                      color: badgeColor,
                      size: 24,
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
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: colors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          doc.documentType ?? 'Document',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!_isMultiSelect)
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert_rounded, color: colors.textSecondary),
                      onSelected: (val) {
                        if (val == 'open') {
                          context.push('/document/${doc.id}');
                        } else if (val == 'extend') {
                          _editDuration(doc);
                        } else if (val == 'permanent') {
                          _makePermanent(doc);
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
                          value: 'extend',
                          child: Row(
                            children: [
                              Icon(Icons.timer_outlined, size: 18),
                              SizedBox(width: 10),
                              Text('Extend Duration'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'permanent',
                          child: Row(
                            children: [
                              Icon(Icons.shield_outlined, size: 18),
                              SizedBox(width: 10),
                              Text('Make Permanent'),
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
              const SizedBox(height: 12),
              // Expiry details badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isExpired ? Icons.error_outline_rounded : Icons.schedule_rounded,
                      size: 15,
                      color: badgeColor,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      doc.temporaryStatusLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: badgeColor,
                      ),
                    ),
                    if (doc.expiresAt != null) ...[
                      Text(
                        ' • Expiry: ${DateFormatter.formatDisplay(doc.expiresAt!)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (groups.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: groups.map((g) {
                    final color = Color(g.colorValue);
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: color.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_getGroupIcon(g.icon), size: 12, color: color),
                          const SizedBox(width: 4),
                          Text(
                            g.name,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: color,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
