import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../../core/security/clipboard_security_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../../core/widgets/error_dialog.dart';
import '../../authentication/presentation/auth_providers.dart';
import '../../documents/data/document_repository.dart';
import '../../documents/domain/document_model.dart';
import '../domain/document_extraction_model.dart';

enum FieldFilterMode {
  all,
  selectedOnly,
  recommendedOnly,
  highConfidenceOnly,
}

class ExtractionReviewScreen extends ConsumerStatefulWidget {
  final String documentId;

  const ExtractionReviewScreen({
    super.key,
    required this.documentId,
  });

  @override
  ConsumerState<ExtractionReviewScreen> createState() => _ExtractionReviewScreenState();
}

class _ExtractionReviewScreenState extends ConsumerState<ExtractionReviewScreen> {
  final Uuid _uuid = const Uuid();
  bool _isLoading = true;
  bool _isSaving = false;
  DocumentModel? _document;
  DocumentExtractionModel? _extraction;
  List<ExtractedFieldModel> _editableFields = [];

  String _searchQuery = '';
  FieldFilterMode _filterMode = FieldFilterMode.all;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadExtractionData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadExtractionData() async {
    final session = ref.read(vaultSessionProvider);
    if (!session.isUnlocked || session.masterKey == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final repo = ref.read(documentRepositoryProvider);
      final doc = await repo.getDocumentById(widget.documentId, session.masterKey!);
      final ext = await repo.getExtractionForDocument(widget.documentId, session.masterKey!);

      if (mounted) {
        setState(() {
          _document = doc;
          _extraction = ext;
          _editableFields = ext?.fields.map((f) => f.copyWith()).toList() ?? [];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ErrorDialog.show(context, title: 'Error', message: 'Failed to load extraction details.');
      }
    }
  }

  List<ExtractedFieldModel> get _filteredFields {
    return _editableFields.where((field) {
      // 1. Filter by category mode
      if (_filterMode == FieldFilterMode.selectedOnly && !field.isSelected) {
        return false;
      }
      if (_filterMode == FieldFilterMode.recommendedOnly && !field.isRecommended) {
        return false;
      }
      if (_filterMode == FieldFilterMode.highConfidenceOnly && field.confidenceCategory != 'High') {
        return false;
      }

      // 2. Search query filter
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final nameMatches = field.fieldName.toLowerCase().contains(query);
        final valMatches = (field.plainValue ?? '').toLowerCase().contains(query);
        if (!nameMatches && !valMatches) return false;
      }

      return true;
    }).toList();
  }

  void _selectAll() {
    setState(() {
      for (int i = 0; i < _editableFields.length; i++) {
        _editableFields[i] = _editableFields[i].copyWith(isSelected: true);
      }
    });
  }

  void _deselectAll() {
    setState(() {
      for (int i = 0; i < _editableFields.length; i++) {
        _editableFields[i] = _editableFields[i].copyWith(isSelected: false);
      }
    });
  }

  void _selectRecommended() {
    setState(() {
      for (int i = 0; i < _editableFields.length; i++) {
        final isRec = _editableFields[i].isRecommended;
        _editableFields[i] = _editableFields[i].copyWith(isSelected: isRec);
      }
    });
  }

  void _toggleField(String fieldId) {
    setState(() {
      final index = _editableFields.indexWhere((f) => f.id == fieldId);
      if (index != -1) {
        final current = _editableFields[index];
        _editableFields[index] = current.copyWith(isSelected: !current.isSelected);
      }
    });
  }

  Future<void> _editField(ExtractedFieldModel field) async {
    final colors = context.themeColors;
    final nameCtrl = TextEditingController(text: field.fieldName);
    final valCtrl = TextEditingController(text: field.plainValue ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.cardBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.cardBorder),
        ),
        title: Text(
          'Edit Extracted Field',
          style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: 'Field Label',
                labelStyle: TextStyle(color: colors.textSecondary),
                filled: true,
                fillColor: colors.inputBackground,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              style: TextStyle(color: colors.textPrimary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: valCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Field Value',
                labelStyle: TextStyle(color: colors.textSecondary),
                filled: true,
                fillColor: colors.inputBackground,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              style: TextStyle(color: colors.textPrimary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameCtrl.text.trim().isNotEmpty) {
                Navigator.pop(ctx, true);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.primaryAccent,
              foregroundColor: colors.onPrimaryAccent,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      setState(() {
        final index = _editableFields.indexWhere((f) => f.id == field.id);
        if (index != -1) {
          _editableFields[index] = _editableFields[index].copyWith(
            fieldName: nameCtrl.text.trim(),
            plainValue: valCtrl.text.trim(),
            verificationStatus: 'edited',
            isVerified: true,
            isSelected: true,
          );
        }
      });
    }
  }

  void _deleteField(String fieldId) {
    setState(() {
      _editableFields.removeWhere((f) => f.id == fieldId);
    });
  }

  Future<void> _addCustomField() async {
    final colors = context.themeColors;
    final nameCtrl = TextEditingController();
    final valCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.cardBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.cardBorder),
        ),
        title: Text(
          'Add Custom Field',
          style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Field Label (e.g. Chassis No, Engine No)',
                labelStyle: TextStyle(color: colors.textSecondary),
                filled: true,
                fillColor: colors.inputBackground,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              style: TextStyle(color: colors.textPrimary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: valCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Field Value',
                labelStyle: TextStyle(color: colors.textSecondary),
                filled: true,
                fillColor: colors.inputBackground,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              style: TextStyle(color: colors.textPrimary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameCtrl.text.trim().isNotEmpty && valCtrl.text.trim().isNotEmpty) {
                Navigator.pop(ctx, true);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.primaryAccent,
              foregroundColor: colors.onPrimaryAccent,
            ),
            child: const Text('Add Field'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      final now = DateTime.now();
      final newField = ExtractedFieldModel(
        id: _uuid.v4(),
        extractionId: _extraction?.id ?? _uuid.v4(),
        documentId: widget.documentId,
        fieldName: nameCtrl.text.trim(),
        encryptedValue: '', // Will be encrypted on save
        plainValue: valCtrl.text.trim(),
        confidence: 1.0,
        confidenceCategory: 'High',
        sourcePage: 1,
        verificationStatus: 'verified',
        isSelected: true,
        isVerified: true,
        createdAt: now,
        updatedAt: now,
      );

      setState(() {
        _editableFields.insert(0, newField);
      });
    }
  }

  void _showRawTextSheet() {
    final colors = context.themeColors;
    final rawText = _extraction?.extractedTextEncrypted ?? 'No extracted text available.';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.cardBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scrollController) => Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.textSecondary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.text_snippet_rounded, color: colors.primaryAccent),
                  const SizedBox(width: 8),
                  Text(
                    'Complete Raw Extracted Text',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.copy_rounded, color: colors.primaryAccent, size: 20),
                    tooltip: 'Copy Raw Text',
                    onPressed: () {
                      ClipboardSecurityService.instance.copySensitive(
                        context,
                        text: rawText,
                        label: 'Complete Raw Text',
                      );
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  rawText,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: colors.textPrimary,
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveSelectedFields() async {
    final session = ref.read(vaultSessionProvider);
    if (!session.isUnlocked || session.masterKey == null) return;
    if (_extraction == null) return;

    setState(() => _isSaving = true);

    try {
      final repo = ref.read(documentRepositoryProvider);
      await repo.saveExtractedFieldsList(
        extractionId: _extraction!.id,
        documentId: widget.documentId,
        fields: _editableFields,
        masterKey: session.masterKey!,
      );

      if (mounted) {
        final selectedCount = _editableFields.where((f) => f.isSelected).length;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved $selectedCount selected fields to encrypted vault.'),
            backgroundColor: AppColors.successGreen,
          ),
        );
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ErrorDialog.show(context, title: 'Save Failed', message: e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(
          title: const Text('Extraction Review'),
          backgroundColor: colors.surface,
        ),
        body: Center(
          child: CircularProgressIndicator(color: colors.primaryAccent),
        ),
      );
    }

    final selectedCount = _editableFields.where((f) => f.isSelected).length;
    final totalCount = _editableFields.length;
    final filtered = _filteredFields;
    final docType = _extraction?.documentType ?? _document?.documentType ?? 'Document';

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Intelligent Field Review', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text(
              _document?.name ?? 'Document',
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
          ],
        ),
        backgroundColor: colors.surface,
        actions: [
          IconButton(
            icon: const Icon(Icons.text_snippet_outlined),
            tooltip: 'View Raw Text',
            onPressed: _showRawTextSheet,
          ),
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Add Custom Field',
            onPressed: _addCustomField,
          ),
        ],
      ),
      body: Column(
        children: [
          // Header summary card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: colors.cardBackground,
              border: Border(bottom: BorderSide(color: colors.cardBorder)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: colors.primaryAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        docType,
                        style: TextStyle(
                          color: colors.primaryAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${_extraction?.pageCount ?? 1} Page(s) • ${_extraction?.extractionEngine ?? "Offline Engine"}',
                        style: TextStyle(color: colors.textSecondary, fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '$selectedCount of $totalCount Fields Selected',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: Icon(Icons.menu_book_rounded, size: 14, color: colors.primaryAccent),
                      label: Text('Raw Text', style: TextStyle(color: colors.primaryAccent, fontSize: 12)),
                      onPressed: _showRawTextSheet,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Search and Filter Strip
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            color: colors.background,
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search fields or values...',
                    hintStyle: TextStyle(color: colors.textSecondary, fontSize: 13),
                    prefixIcon: Icon(Icons.search_rounded, color: colors.textSecondary, size: 18),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 16),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: colors.inputBackground,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: colors.cardBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: colors.cardBorder),
                    ),
                  ),
                  style: TextStyle(color: colors.textPrimary, fontSize: 13),
                  onChanged: (val) => setState(() => _searchQuery = val),
                ),
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('All ($totalCount)', FieldFilterMode.all, colors),
                      const SizedBox(width: 6),
                      _buildFilterChip('Selected ($selectedCount)', FieldFilterMode.selectedOnly, colors),
                      const SizedBox(width: 6),
                      _buildFilterChip('Recommended', FieldFilterMode.recommendedOnly, colors),
                      const SizedBox(width: 6),
                      _buildFilterChip('High Confidence', FieldFilterMode.highConfidenceOnly, colors),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Selection Quick Actions Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                _buildActionPill(
                  label: 'Select All',
                  icon: Icons.check_box_outlined,
                  onTap: _selectAll,
                  colors: colors,
                ),
                const SizedBox(width: 8),
                _buildActionPill(
                  label: 'Deselect All',
                  icon: Icons.check_box_outline_blank,
                  onTap: _deselectAll,
                  colors: colors,
                ),
                const SizedBox(width: 8),
                _buildActionPill(
                  label: 'Recommended',
                  icon: Icons.star_outline_rounded,
                  onTap: _selectRecommended,
                  colors: colors,
                ),
              ],
            ),
          ),

          const Divider(height: 8),

          // Field List
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      'No fields match your search or filter.',
                      style: TextStyle(color: colors.textSecondary),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final field = filtered[index];
                      return _buildFieldCard(field, colors);
                    },
                  ),
          ),
        ],
      ),
      bottomSheet: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveSelectedFields,
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primaryAccent,
                foregroundColor: colors.onPrimaryAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check_circle_outline_rounded),
              label: Text(
                _isSaving ? 'Encrypting & Saving...' : 'Save $selectedCount Selected Fields',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, FieldFilterMode mode, AppThemeColors colors) {
    final isSelected = _filterMode == mode;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 11, color: isSelected ? colors.onPrimaryAccent : colors.textPrimary)),
      selected: isSelected,
      selectedColor: colors.primaryAccent,
      backgroundColor: colors.cardBackground,
      side: BorderSide(color: isSelected ? colors.primaryAccent : colors.cardBorder),
      visualDensity: VisualDensity.compact,
      onSelected: (_) => setState(() => _filterMode = mode),
    );
  }

  Widget _buildActionPill({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    required AppThemeColors colors,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: colors.cardBackground,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.cardBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: colors.textSecondary),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: colors.textSecondary, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldCard(ExtractedFieldModel field, AppThemeColors colors) {
    final isSelected = field.isSelected;
    final confidenceColor = field.confidence >= 0.85
        ? colors.success
        : field.confidence >= 0.70
            ? colors.warning
            : colors.error;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected ? colors.cardBackground : colors.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? colors.primaryAccent.withValues(alpha: 0.5) : colors.cardBorder,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _toggleField(field.id),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: field.isSelected,
                activeColor: colors.primaryAccent,
                checkColor: colors.onPrimaryAccent,
                onChanged: (_) => _toggleField(field.id),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            field.fieldName,
                            style: TextStyle(
                              color: isSelected ? colors.textPrimary : colors.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: confidenceColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${(field.confidence * 100).toInt()}% • ${field.confidenceCategory}',
                            style: TextStyle(
                              color: confidenceColor,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      field.plainValue ?? '—',
                      style: TextStyle(
                        color: isSelected ? colors.textPrimary : colors.textSecondary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          'Page ${field.sourcePage}',
                          style: TextStyle(color: colors.textSecondary, fontSize: 10),
                        ),
                        if (field.verificationStatus == 'edited') ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: colors.info.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              'Edited',
                              style: TextStyle(color: colors.info, fontSize: 9),
                            ),
                          ),
                        ],
                        const Spacer(),
                        InkWell(
                          onTap: () => _editField(field),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(Icons.edit_outlined, size: 16, color: colors.textSecondary),
                          ),
                        ),
                        const SizedBox(width: 6),
                        InkWell(
                          onTap: () {
                            ClipboardSecurityService.instance.copySensitive(
                              context,
                              text: field.plainValue ?? '',
                              label: field.fieldName,
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(Icons.copy_outlined, size: 16, color: colors.textSecondary),
                          ),
                        ),
                        const SizedBox(width: 6),
                        InkWell(
                          onTap: () => _deleteField(field.id),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(Icons.delete_outline, size: 16, color: colors.error),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
