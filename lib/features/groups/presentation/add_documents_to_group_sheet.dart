import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../authentication/presentation/auth_providers.dart';
import '../../documents/domain/document_model.dart';
import '../domain/document_group_model.dart';

class AddDocumentsToGroupSheet extends ConsumerStatefulWidget {
  final DocumentGroupModel group;
  final List<String> existingMemberDocIds;

  const AddDocumentsToGroupSheet({
    super.key,
    required this.group,
    required this.existingMemberDocIds,
  });

  static Future<List<String>?> show(
    BuildContext context, {
    required DocumentGroupModel group,
    required List<String> existingMemberDocIds,
  }) {
    return showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddDocumentsToGroupSheet(
        group: group,
        existingMemberDocIds: existingMemberDocIds,
      ),
    );
  }

  @override
  ConsumerState<AddDocumentsToGroupSheet> createState() =>
      _AddDocumentsToGroupSheetState();
}

class _AddDocumentsToGroupSheetState
    extends ConsumerState<AddDocumentsToGroupSheet> {
  final Set<String> _selectedIds = {};
  String _searchQuery = '';
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

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final docsAsync = ref.watch(activeDocumentsProvider);

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
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
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Add to "${widget.group.name}"',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: colors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Select documents to add to this group',
                        style: TextStyle(fontSize: 12, color: colors.textSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search documents...',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                isDense: true,
                filled: true,
                fillColor: colors.cardBackground,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colors.cardBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colors.cardBorder),
                ),
              ),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: docsAsync.when(
              data: (allDocs) {
                // Filter out documents that are already members of this group
                final availableDocs = allDocs
                    .where((d) => !widget.existingMemberDocIds.contains(d.id))
                    .where((d) {
                  if (_searchQuery.trim().isEmpty) return true;
                  final q = _searchQuery.trim().toLowerCase();
                  return d.name.toLowerCase().contains(q) ||
                      (d.documentType?.toLowerCase().contains(q) ?? false);
                }).toList();

                if (availableDocs.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _searchQuery.isNotEmpty
                            ? 'No documents match "$_searchQuery".'
                            : 'All documents are already in this group.',
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: availableDocs.length,
                  itemBuilder: (context, index) {
                    final doc = availableDocs[index];
                    final isSelected = _selectedIds.contains(doc.id);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: colors.cardBackground,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? colors.primaryAccent : colors.cardBorder,
                        ),
                      ),
                      child: CheckboxListTile(
                        value: isSelected,
                        activeColor: colors.primaryAccent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        title: Text(
                          doc.name,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          doc.documentType ?? 'Document',
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.textSecondary,
                          ),
                        ),
                        secondary: Icon(
                          doc.isTemporary
                              ? Icons.hourglass_top_rounded
                              : Icons.description_outlined,
                          color: doc.isTemporary
                              ? colors.warning
                              : colors.primaryAccent,
                        ),
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              _selectedIds.add(doc.id);
                            } else {
                              _selectedIds.remove(doc.id);
                            }
                          });
                        },
                      ),
                    );
                  },
                );
              },
              loading: () => Center(
                child: CircularProgressIndicator(color: colors.primaryAccent),
              ),
              error: (err, _) => Center(
                child: Text('Error: $err', style: TextStyle(color: colors.error)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _selectedIds.isEmpty
                    ? null
                    : () => Navigator.of(context).pop(_selectedIds.toList()),
                icon: const Icon(Icons.add_rounded),
                label: Text(
                  _selectedIds.isEmpty
                      ? 'Select Documents'
                      : 'Add ${_selectedIds.length} ${_selectedIds.length == 1 ? 'Document' : 'Documents'}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(widget.group.colorValue),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
