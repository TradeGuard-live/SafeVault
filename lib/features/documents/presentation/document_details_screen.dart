import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/security/authentication_gate.dart';
import '../../../core/security/clipboard_security_service.dart';
import '../../../core/security/file_validator.dart';
import '../../../core/services/native_saf_and_share_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/masked_text_formatter.dart';
import '../../../core/widgets/error_dialog.dart';
import '../../../core/widgets/status_badge.dart';
import '../../authentication/presentation/auth_providers.dart';
import '../../ocr/data/document_text_extractor.dart';
import '../../ocr/domain/document_extraction_model.dart';
import '../domain/document_file_model.dart';
import '../domain/document_model.dart';
import 'document_share_sheet.dart';

class DocumentDetailsScreen extends ConsumerStatefulWidget {
  final String documentId;
  final int initialTabIndex;

  const DocumentDetailsScreen({
    super.key,
    required this.documentId,
    this.initialTabIndex = 0,
  });

  @override
  ConsumerState<DocumentDetailsScreen> createState() =>
      _DocumentDetailsScreenState();
}

class _DocumentDetailsScreenState extends ConsumerState<DocumentDetailsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DocumentModel? _document;
  DocumentExtractionModel? _extraction;
  bool _isLoading = true;
  bool _isReprocessing = false;
  Timer? _visibilityTimer;
  bool _revealDocumentNumber = false;
  Uint8List? _firstPagePreviewBytes;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 1),
    );
    _loadDocument();
  }

  @override
  void deactivate() {
    _visibilityTimer?.cancel();
    _revealDocumentNumber = false;
    super.deactivate();
  }

  @override
  void dispose() {
    _visibilityTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadDocument() async {
    final session = ref.read(vaultSessionProvider);
    if (!session.isUnlocked || session.masterKey == null) {
      context.go('/pin-unlock');
      return;
    }

    try {
      final repo = ref.read(documentRepositoryProvider);
      final doc = await repo.getDocumentById(
        widget.documentId,
        session.masterKey!,
      );
      final extraction = await repo.getExtractionForDocument(
        widget.documentId,
        session.masterKey!,
      );

      if (mounted) {
        setState(() {
          _document = doc;
          _extraction = extraction;
          _isLoading = false;
        });

        // Load preview for image if available
        if (doc != null && doc.files.isNotEmpty) {
          final firstFile = doc.files.first;
          if (firstFile.mimeType.startsWith('image/')) {
            final storage = ref.read(storageServiceProvider);
            final bytes = await storage.readDecryptedFile(
              filePath: firstFile.encryptedFilePath,
              masterKey: session.masterKey!,
            );
            if (mounted) {
              setState(() => _firstPagePreviewBytes = bytes);
            }
          }
        }

        // Resume any pending action targeting this document
        final gate = ref.read(authenticationGateProvider);
        final pending = gate.consumePendingAction(widget.documentId);
        if (pending != null && mounted) {
          if (pending.type == VaultActionType.revealDocumentField) {
            setState(() => _revealDocumentNumber = true);
            _visibilityTimer?.cancel();
            _visibilityTimer = Timer(const Duration(seconds: 60), () {
              if (mounted) setState(() => _revealDocumentNumber = false);
            });
          } else if (pending.type == VaultActionType.copyAllFields) {
            _copyAllFields();
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ErrorDialog.show(
          context,
          title: 'Error',
          message: 'Failed to decrypt document details.',
        );
      }
    }
  }

  Future<void> _toggleRevealDocumentNumber() async {
    if (_revealDocumentNumber) {
      setState(() => _revealDocumentNumber = false);
      return;
    }
    final gate = ref.read(authenticationGateProvider);
    final verified = await gate.authenticateForAction(
      context,
      action: PendingVaultAction(
        type: VaultActionType.revealDocumentField,
        targetId: widget.documentId,
        targetName: _document?.name ?? 'Document',
        returnRoute: '/document/${widget.documentId}',
      ),
      title: 'Reveal Document Number',
      reason: 'Confirm with biometrics to reveal the masked document number.',
    );
    if (verified && mounted) {
      setState(() => _revealDocumentNumber = true);
      _visibilityTimer?.cancel();
      _visibilityTimer = Timer(const Duration(seconds: 60), () {
        if (mounted) {
          setState(() => _revealDocumentNumber = false);
        }
      });
    }
  }

  Future<void> _toggleFavorite() async {
    if (_document == null) return;
    final repo = ref.read(documentRepositoryProvider);
    final newStatus = await repo.toggleFavorite(
      _document!.id,
      _document!.isFavorite,
    );
    setState(() {
      _document = _document!.copyWith(isFavorite: newStatus);
    });
    ref.invalidate(favoriteDocumentsProvider);
    ref.invalidate(activeDocumentsProvider);
  }

  Future<void> _addPage() async {
    final pickedItems = await NativeSafAndShareService.instance.pickDocuments(
      allowMultiple: false,
    );
    if (pickedItems.isEmpty) return;

    final item = pickedItems.first;
    final file = File(item.path);
    if (!await file.exists()) return;

    final validation = await FileValidator.validateFile(file);
    final session = ref.read(vaultSessionProvider);
    final storage = ref.read(storageServiceProvider);
    final repo = ref.read(documentRepositoryProvider);

    final plainBytes = await file.readAsBytes();
    final encPath = await storage.saveEncryptedFile(
      plainBytes: plainBytes,
      masterKey: session.masterKey!,
    );

    final newFile = DocumentFileModel(
      id: '',
      documentId: widget.documentId,
      encryptedFilePath: encPath,
      originalFileName: item.name,
      mimeType: validation.mimeType,
      fileSize: validation.byteLength,
      createdAt: DateTime.now(),
    );

    await repo.addDocumentPageFile(
      documentId: widget.documentId,
      file: newFile,
    );
    ref.invalidate(activeDocumentsProvider);
    _loadDocument();

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Page added successfully.')));
    }
  }

  Future<void> _moveToTrash() async {
    final confirmed = await ErrorDialog.confirm(
      context,
      title: 'Move to Trash?',
      message:
          'This document will be moved to Trash. You can restore it anytime.',
      confirmLabel: 'Move to Trash',
      isDestructive: true,
    );

    if (confirmed && mounted) {
      final gate = ref.read(authenticationGateProvider);
      final verified = await gate.authenticateForAction(
        context,
        action: PendingVaultAction(
          type: VaultActionType.deleteDocument,
          targetId: widget.documentId,
          targetName: _document?.name ?? 'Document',
          returnRoute: '/dashboard',
        ),
        title: 'Authorize Move to Trash',
        reason: 'Confirm with biometrics to delete "${_document?.name}".',
      );
      if (!verified || !mounted) return;

      final repo = ref.read(documentRepositoryProvider);
      await repo.moveToTrash(widget.documentId);
      ref.invalidate(activeDocumentsProvider);
      ref.invalidate(trashDocumentsProvider);
      if (mounted) {
        context.pop();
      }
    }
  }

  Future<void> _reprocessDocument() async {
    final doc = _document;
    if (doc == null || doc.files.isEmpty) return;

    // Show language selector bottom sheet
    final selectedLang = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select OCR Language',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              const Text(
                'Choose bundled model for text recognition:',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.language_rounded),
                title: const Text('English (eng)'),
                subtitle: const Text('Default English model'),
                onTap: () => Navigator.pop(ctx, 'eng'),
              ),
              ListTile(
                leading: const Icon(Icons.translate_rounded),
                title: const Text('Hindi / Devanagari (hin)'),
                subtitle: const Text('Hindi & Sanskrit scripts'),
                onTap: () => Navigator.pop(ctx, 'hin'),
              ),
              ListTile(
                leading: const Icon(Icons.menu_book_rounded),
                title: const Text('Gujarati (guj)'),
                subtitle: const Text('Gujarati script bundled model'),
                onTap: () => Navigator.pop(ctx, 'guj'),
              ),
            ],
          ),
        ),
      ),
    );

    if (selectedLang == null || !mounted) return;

    setState(() => _isReprocessing = true);

    try {
      final session = ref.read(vaultSessionProvider);
      final storage = ref.read(storageServiceProvider);
      final repo = ref.read(documentRepositoryProvider);

      final firstFile = doc.files.first;
      final fileBytes = await storage.readDecryptedFile(
        filePath: firstFile.encryptedFilePath,
        masterKey: session.masterKey!,
      );

      final extractor = DocumentTextExtractor();
      final result = await extractor.processDocumentBytes(
        bytes: fileBytes,
        fileName: firstFile.originalFileName,
        mimeType: firstFile.mimeType,
        language: selectedLang,
      );

      final formattedTxt = DocumentTextExtractor.generateFormattedTextRecord(
        documentType: result.classification.documentType,
        categoryName: doc.categoryId,
        sourceFileName: firstFile.originalFileName,
        fullText: result.fullText,
        fields: result.fields,
        engine: result.extractionEngine,
        language: result.language,
        pageCount: result.pageCount,
      );

      final encTxtPath = await repo.saveExtractedTxtFile(
        documentId: doc.id,
        textContent: formattedTxt,
        masterKey: session.masterKey!,
      );

      await repo.saveExtraction(
        documentId: doc.id,
        documentType: result.classification.documentType,
        extractedText: result.fullText,
        fields: result.fields,
        engine: result.extractionEngine,
        language: result.language,
        pageCount: result.pageCount,
        encryptedTxtFilePath: encTxtPath,
        masterKey: session.masterKey!,
      );

      await _loadDocument();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Reprocessed successfully via ${result.extractionEngine}.',
            ),
            backgroundColor: AppColors.primaryTeal,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ErrorDialog.show(
          context,
          title: 'Reprocessing Failed',
          message: e.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => _isReprocessing = false);
    }
  }

  Future<void> _editField(ExtractedFieldModel field) async {
    final controller = TextEditingController(
      text: field.plainValue ?? field.encryptedValue,
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit ${field.fieldName}'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: field.fieldName,
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final session = ref.read(vaultSessionProvider);
      final repo = ref.read(documentRepositoryProvider);
      await repo.updateExtractedField(
        fieldId: field.id,
        newValue: controller.text,
        masterKey: session.masterKey!,
      );
      _loadDocument();
    }
  }

  void _copyField(String label, String value) {
    ClipboardSecurityService.instance.copySensitive(
      context,
      text: value,
      label: label,
    );
  }

  Future<void> _copyAllFields() async {
    final fields = _extraction?.fields ?? [];
    if (fields.isEmpty) return;

    final gate = ref.read(authenticationGateProvider);
    final verified = await gate.authenticateForAction(
      context,
      action: PendingVaultAction(
        type: VaultActionType.copyAllFields,
        targetId: widget.documentId,
        targetName: _document?.name ?? 'Document',
        returnRoute: '/document/${widget.documentId}',
      ),
      title: 'Authorize Copy All Fields',
      reason:
          'Confirm with biometrics to copy all structured fields to clipboard.',
    );
    if (!verified || !mounted) return;

    final buffer = StringBuffer();
    buffer.writeln('${_document?.name ?? "Document"} Summary:');
    for (final f in fields) {
      buffer.writeln('${f.fieldName}: ${f.plainValue ?? f.encryptedValue}');
    }

    await ClipboardSecurityService.instance.copySensitive(
      context,
      text: buffer.toString(),
      label: 'All Structured Fields',
    );
  }

  void _openViewer(DocumentFileModel file) {
    context.push(
      '/document-viewer',
      extra: {
        'documentName': _document?.name ?? 'Document',
        'encryptedFilePath': file.encryptedFilePath,
        'mimeType': file.mimeType,
        'fileName': file.originalFileName,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(title: const Text('Document')),
        body: Center(
          child: CircularProgressIndicator(color: colors.primaryAccent),
        ),
      );
    }

    if (_document == null) {
      return Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(title: const Text('Not Found')),
        body: const Center(child: Text('Document not found.')),
      );
    }

    final doc = _document!;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text(
          doc.name,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded),
            tooltip: 'Share Document',
            onPressed: () {
              DocumentShareSheet.show(
                context,
                document: doc,
                extractedText: _extraction?.extractedTextEncrypted,
              );
            },
          ),
          IconButton(
            icon: Icon(
              doc.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
              color: doc.isFavorite ? Colors.amber : null,
            ),
            tooltip: doc.isFavorite ? 'Remove Favorite' : 'Mark Favorite',
            onPressed: _toggleFavorite,
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit Metadata',
            onPressed: () =>
                context.push('/add-document', extra: {'editDocument': doc}),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Move to Trash',
            onPressed: _moveToTrash,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: colors.primaryAccent,
          unselectedLabelColor: colors.textSecondary,
          indicatorColor: colors.primaryAccent,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.preview_rounded, size: 18), text: 'Preview'),
            Tab(
              icon: Icon(Icons.auto_awesome_rounded, size: 18),
              text: 'Extracted Info',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // TAB 1: Preview
          _buildPreviewTab(doc, colors),

          // TAB 2: Extracted Information
          _buildExtractedInfoTab(doc, colors),
        ],
      ),
    );
  }

  // =========================================================================
  // TAB 1: PREVIEW
  // =========================================================================
  Widget _buildPreviewTab(DocumentModel doc, AppThemeColors colors) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      children: [
        _buildPreviewCard(doc, colors),
        const SizedBox(height: 18),
        _buildMetadataCard(doc, colors),
        const SizedBox(height: 18),
        _buildFilesSection(doc, colors),
        const SizedBox(height: 30),
      ],
    );
  }

  Widget _buildPreviewCard(DocumentModel doc, AppThemeColors colors) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.cardBorder),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          children: [
            if (_firstPagePreviewBytes != null)
              Center(
                child: Image.memory(
                  _firstPagePreviewBytes!,
                  fit: BoxFit.contain,
                  width: double.infinity,
                  height: double.infinity,
                ),
              )
            else
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      doc.files.any((f) => f.mimeType == 'application/pdf')
                          ? Icons.picture_as_pdf_outlined
                          : Icons.image_outlined,
                      size: 54,
                      color: colors.primaryAccent,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${doc.files.length} Encrypted File${doc.files.length == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            Positioned(
              top: 12,
              right: 12,
              child: StatusBadge.fromExpiry(doc.expiryDate),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetadataCard(DocumentModel doc, AppThemeColors colors) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Document Details',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
              const Spacer(),
              if (doc.documentType != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colors.primaryAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    doc.documentType!,
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.primaryAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const Divider(height: 24),
          if (doc.documentNumber != null)
            _buildMetaRow(
              'Document Number',
              _revealDocumentNumber
                  ? doc.documentNumber!
                  : MaskedTextFormatter.maskDocumentNumber(doc.documentNumber),
              colors,
              isSensitive: true,
              onReveal: _toggleRevealDocumentNumber,
              isRevealed: _revealDocumentNumber,
            ),
          if (doc.ownerName != null)
            _buildMetaRow('Owner Name', doc.ownerName!, colors),
          if (doc.issuingAuthority != null)
            _buildMetaRow('Authority', doc.issuingAuthority!, colors),
          if (doc.issueDate != null)
            _buildMetaRow(
              'Issue Date',
              DateFormatter.formatDisplay(doc.issueDate!),
              colors,
            ),
          if (doc.expiryDate != null)
            _buildMetaRow(
              'Expiry Date',
              DateFormatter.formatDisplay(doc.expiryDate!),
              colors,
            ),
          if (doc.notes != null) _buildMetaRow('Notes', doc.notes!, colors),
        ],
      ),
    );
  }

  Widget _buildMetaRow(
    String label,
    String value,
    AppThemeColors colors, {
    bool isSensitive = false,
    VoidCallback? onReveal,
    bool isRevealed = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                if (isSensitive && onReveal != null)
                  IconButton(
                    icon: Icon(
                      isRevealed
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18,
                      color: colors.primaryAccent,
                    ),
                    onPressed: onReveal,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                    Icons.copy_rounded,
                    size: 16,
                    color: colors.textSecondary,
                  ),
                  onPressed: () => _copyField(label, value),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilesSection(DocumentModel doc, AppThemeColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Attached Files (${doc.files.length})',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
            ),
            TextButton.icon(
              onPressed: _addPage,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add Page'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final file in doc.files)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.cardBackground,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.cardBorder),
            ),
            child: Row(
              children: [
                Icon(
                  file.mimeType.contains('pdf')
                      ? Icons.picture_as_pdf_rounded
                      : Icons.image_rounded,
                  color: file.mimeType.contains('pdf')
                      ? Colors.redAccent
                      : colors.primaryAccent,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        file.originalFileName,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Page ${file.pageNumber} • ${(file.fileSize / 1024).toStringAsFixed(1)} KB',
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.visibility_rounded,
                    color: colors.primaryAccent,
                  ),
                  onPressed: () => _openViewer(file),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // =========================================================================
  // TAB 2: EXTRACTED INFORMATION
  // =========================================================================
  Widget _buildExtractedInfoTab(DocumentModel doc, AppThemeColors colors) {
    final fields = _extraction?.fields ?? [];

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      children: [
        // Engine & Status Header
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.cardBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colors.primaryAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      color: colors.primaryAccent,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _extraction?.extractionEngine ??
                              'Offline Extraction Engine',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: colors.textPrimary,
                          ),
                        ),
                        Text(
                          'Language: ${_extraction?.language ?? "eng"} • Version: ${_extraction?.version ?? 1}',
                          style: TextStyle(
                            color: colors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isReprocessing ? null : _reprocessDocument,
                      icon: _isReprocessing
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded, size: 16),
                      label: Text(
                        _isReprocessing ? 'Processing...' : 'Re-run OCR',
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: fields.isEmpty
                          ? null
                          : () async {
                              final changed = await context.push<bool>(
                                '/extraction-review/${widget.documentId}',
                              );
                              if (changed == true) {
                                _loadDocument();
                              }
                            },
                      icon: const Icon(Icons.fact_check_outlined, size: 16),
                      label: const Text('Review Fields'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.primaryAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: fields.isEmpty ? null : _copyAllFields,
                    icon: const Icon(Icons.copy_all_rounded, size: 20),
                    tooltip: 'Copy All Fields',
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (fields.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            alignment: Alignment.center,
            child: Column(
              children: [
                Icon(
                  Icons.text_fields_rounded,
                  size: 48,
                  color: colors.textSecondary.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 12),
                Text(
                  'No structured fields recognized yet.',
                  style: TextStyle(color: colors.textSecondary, fontSize: 14),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _reprocessDocument,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Run Text Extraction'),
                ),
              ],
            ),
          )
        else ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Saved Fields (${fields.where((f) => f.isSelected).length} of ${fields.length})',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
              TextButton.icon(
                onPressed: () async {
                  final changed = await context.push<bool>(
                    '/extraction-review/${widget.documentId}',
                  );
                  if (changed == true) {
                    _loadDocument();
                  }
                },
                icon: Icon(
                  Icons.tune_rounded,
                  size: 14,
                  color: colors.primaryAccent,
                ),
                label: Text(
                  'Edit / Select',
                  style: TextStyle(color: colors.primaryAccent, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final field in fields.where((f) => f.isSelected))
            _buildExtractedFieldCard(field, colors),
          if (fields.any((f) => !f.isSelected)) ...[
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: () async {
                  final changed = await context.push<bool>(
                    '/extraction-review/${widget.documentId}',
                  );
                  if (changed == true) {
                    _loadDocument();
                  }
                },
                child: Text(
                  '+ ${fields.where((f) => !f.isSelected).length} more unselected fields available in Review',
                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildExtractedFieldCard(
    ExtractedFieldModel field,
    AppThemeColors colors,
  ) {
    final value = field.plainValue ?? field.encryptedValue;
    final isMasked =
        field.fieldName.toLowerCase().contains('aadhaar') ||
        field.fieldName.toLowerCase().contains('pan') ||
        field.fieldName.toLowerCase().contains('number');

    final displayValue = isMasked && !_revealDocumentNumber
        ? MaskedTextFormatter.maskDocumentNumber(value)
        : value;

    Color badgeColor = Colors.green;
    if (field.confidenceCategory == 'Medium') {
      badgeColor = Colors.orange;
    } else if (field.confidenceCategory == 'Low') {
      badgeColor = Colors.redAccent;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                field.fieldName,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${field.confidenceCategory} (${(field.confidence * 100).toInt()}%)',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: badgeColor,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 16),
                color: colors.textSecondary,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Edit Field',
                onPressed: () => _editField(field),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  displayValue,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              if (isMasked)
                IconButton(
                  icon: Icon(
                    _revealDocumentNumber
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 18,
                    color: colors.primaryAccent,
                  ),
                  onPressed: _toggleRevealDocumentNumber,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              const SizedBox(width: 10),
              IconButton(
                icon: Icon(
                  Icons.copy_rounded,
                  size: 18,
                  color: colors.primaryAccent,
                ),
                onPressed: () => _copyField(field.fieldName, value),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
