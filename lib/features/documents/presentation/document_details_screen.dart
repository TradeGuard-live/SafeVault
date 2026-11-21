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
  Timer? _previewVisibilityTimer;
  bool _revealDocumentNumber = false;
  bool _isPreviewRevealed = false;
  bool _isLoadingPreview = false;
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
    _previewVisibilityTimer?.cancel();
    _revealDocumentNumber = false;
    _hidePreview();
    super.deactivate();
  }

  @override
  void dispose() {
    _visibilityTimer?.cancel();
    _previewVisibilityTimer?.cancel();
    _hidePreview();
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
          } else if (pending.type == VaultActionType.viewDocumentPreview) {
            _unlockPreview(alreadyAuthenticated: true);
          } else if (pending.type == VaultActionType.viewAttachedFile) {
            final encPath = pending.params['encryptedFilePath'] as String?;
            final mime = pending.params['mimeType'] as String?;
            final fName = pending.params['fileName'] as String?;
            if (encPath != null && mime != null && fName != null) {
              context.push(
                '/document-viewer',
                extra: {
                  'documentName': _document?.name ?? 'Document',
                  'encryptedFilePath': encPath,
                  'mimeType': mime,
                  'fileName': fName,
                },
              );
            }
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

  Future<void> _unlockPreview({bool alreadyAuthenticated = false}) async {
    final doc = _document;
    if (doc == null || doc.files.isEmpty) return;
    final firstFile = doc.files.first;
    if (!firstFile.mimeType.startsWith('image/')) return;

    if (!alreadyAuthenticated) {
      final gate = ref.read(authenticationGateProvider);
      final verified = await gate.authenticateForAction(
        context,
        action: PendingVaultAction(
          type: VaultActionType.viewDocumentPreview,
          targetId: widget.documentId,
          targetName: doc.name,
          returnRoute: '/document/${widget.documentId}',
        ),
        title: 'Unlock Document Preview',
        reason: 'Confirm with biometrics to decrypt and view document preview.',
      );
      if (!verified || !mounted) return;
    }

    setState(() => _isLoadingPreview = true);
    try {
      final session = ref.read(vaultSessionProvider);
      final storage = ref.read(storageServiceProvider);
      final bytes = await storage.readDecryptedFile(
        filePath: firstFile.encryptedFilePath,
        masterKey: session.masterKey!,
      );
      if (mounted) {
        setState(() {
          _firstPagePreviewBytes = bytes;
          _isPreviewRevealed = true;
          _isLoadingPreview = false;
        });
        _previewVisibilityTimer?.cancel();
        _previewVisibilityTimer = Timer(const Duration(seconds: 60), () {
          if (mounted) _hidePreview();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingPreview = false);
        ErrorDialog.show(
          context,
          title: 'Decryption Error',
          message: 'Failed to decrypt document preview: $e',
        );
      }
    }
  }

  void _hidePreview() {
    _previewVisibilityTimer?.cancel();
    if (_firstPagePreviewBytes != null) {
      _firstPagePreviewBytes!.fillRange(0, _firstPagePreviewBytes!.length, 0);
      _firstPagePreviewBytes = null;
    }
    if (mounted) {
      setState(() => _isPreviewRevealed = false);
    } else {
      _isPreviewRevealed = false;
    }
  }

  Future<void> _editDocument(DocumentModel doc) async {
    await context.push<bool>('/add-document', extra: {'editDocument': doc});
    if (mounted) {
      // Immediately reload document to reflect all saved changes
      await _loadDocument();
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

  Future<void> _toggleFieldOnPreview(ExtractedFieldModel field) async {
    final newSelected = !field.isSelected;
    final repo = ref.read(documentRepositoryProvider);
    await repo.updateFieldSelection(fieldId: field.id, isSelected: newSelected);

    if (mounted) {
      setState(() {
        if (_extraction != null) {
          final updatedFields = _extraction!.fields.map((f) {
            return f.id == field.id ? f.copyWith(isSelected: newSelected) : f;
          }).toList();
          _extraction = _extraction!.copyWith(fields: updatedFields);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newSelected
                ? '"${field.fieldName}" moved to Preview page.'
                : '"${field.fieldName}" removed from Preview page.',
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _moveAllToPreview(bool selectAll) async {
    if (_extraction == null) return;
    final repo = ref.read(documentRepositoryProvider);
    await repo.updateAllFieldsSelection(
      extractionId: _extraction!.id,
      isSelected: selectAll,
    );
    if (mounted) {
      setState(() {
        final updatedFields = _extraction!.fields.map((f) {
          return f.copyWith(isSelected: selectAll);
        }).toList();
        _extraction = _extraction!.copyWith(fields: updatedFields);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            selectAll
                ? 'All extracted details moved to Preview page.'
                : 'All extracted details removed from Preview page.',
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showMoveExtractedFieldsSheet() {
    final allFields = _extraction?.fields ?? [];
    if (allFields.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No extracted fields found for this document.'),
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (bottomSheetContext, setModalState) {
            final theme = context.themeColors;
            final currentFields = _extraction?.fields ?? [];
            final selectedCount =
                currentFields.where((f) => f.isSelected).length;

            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              decoration: BoxDecoration(
                color: theme.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: Column(
                children: [
                  Center(
                    child: Container(
                      margin: const EdgeInsets.only(top: 10, bottom: 8),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.cardBorder,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: theme.primaryAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.dashboard_customize_rounded,
                            color: theme.primaryAccent,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Move Info to Preview Page',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: theme.textPrimary,
                                ),
                              ),
                              Text(
                                '$selectedCount of ${currentFields.length} fields on preview',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        TextButton.icon(
                          onPressed: () async {
                            await _moveAllToPreview(true);
                            setModalState(() {});
                          },
                          icon: const Icon(Icons.select_all_rounded, size: 16),
                          label: const Text(
                            'Select All',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: () async {
                            await _moveAllToPreview(false);
                            setModalState(() {});
                          },
                          icon: const Icon(Icons.deselect_rounded, size: 16),
                          label: const Text(
                            'Clear All',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      itemCount: currentFields.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final field = currentFields[index];
                        final val = field.plainValue ?? field.encryptedValue;

                        return Container(
                          decoration: BoxDecoration(
                            color: field.isSelected
                                ? theme.primaryAccent.withValues(alpha: 0.08)
                                : theme.surfaceElevated,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: field.isSelected
                                  ? theme.primaryAccent
                                  : theme.cardBorder,
                              width: field.isSelected ? 1.5 : 1.0,
                            ),
                          ),
                          child: CheckboxListTile(
                            value: field.isSelected,
                            activeColor: theme.primaryAccent,
                            checkColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            title: Text(
                              field.fieldName,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: theme.textPrimary,
                              ),
                            ),
                            subtitle: Text(
                              val,
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.textSecondary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            secondary: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: theme.surface,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                field.isSelected
                                    ? Icons.push_pin_rounded
                                    : Icons.push_pin_outlined,
                                size: 18,
                                color: field.isSelected
                                    ? theme.primaryAccent
                                    : theme.textSecondary,
                              ),
                            ),
                            onChanged: (bool? checked) async {
                              await _toggleFieldOnPreview(field);
                              setModalState(() {});
                            },
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.primaryAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Done',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
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

  Future<void> _openViewer(DocumentFileModel file) async {
    final gate = ref.read(authenticationGateProvider);
    final verified = await gate.authenticateForAction(
      context,
      action: PendingVaultAction(
        type: VaultActionType.viewAttachedFile,
        targetId: widget.documentId,
        targetName: file.originalFileName,
        returnRoute: '/document/${widget.documentId}',
        params: {
          'fileId': file.id,
          'encryptedFilePath': file.encryptedFilePath,
          'mimeType': file.mimeType,
          'fileName': file.originalFileName,
        },
      ),
      title: 'Authorize File Access',
      reason:
          'Confirm with biometrics to decrypt and view "${file.originalFileName}".',
    );
    if (!verified || !mounted) return;

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
            onPressed: () => _editDocument(doc),
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
        if (_extraction != null && _extraction!.fields.isNotEmpty) ...[
          const SizedBox(height: 18),
          _buildExtractedDetailsPreviewCard(doc, colors),
        ],
        const SizedBox(height: 18),
        _buildFilesSection(doc, colors),
        const SizedBox(height: 30),
      ],
    );
  }

  Widget _buildPreviewCard(DocumentModel doc, AppThemeColors colors) {
    final hasImage = doc.files.any((f) => f.mimeType.startsWith('image/'));

    return Container(
      height: 220,
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.cardBorder),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          children: [
            if (_isPreviewRevealed && _firstPagePreviewBytes != null) ...[
              Center(
                child: Image.memory(
                  _firstPagePreviewBytes!,
                  fit: BoxFit.contain,
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),
              Positioned(
                top: 10,
                left: 10,
                child: Material(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: _hidePreview,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.visibility_off_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Hide',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 8,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Preview Unlocked • Auto-locks in 60s',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ),
                ),
              ),
            ] else if (hasImage) ...[
              // Biometric Protected Image Preview State
              InkWell(
                onTap: _isLoadingPreview ? null : () => _unlockPreview(),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colors.primaryAccent.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.lock_outline_rounded,
                            size: 32,
                            color: colors.primaryAccent,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Encrypted Image Preview',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Biometric authentication required to view preview',
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        if (_isLoadingPreview)
                          const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          ElevatedButton.icon(
                            onPressed: () => _unlockPreview(),
                            icon: const Icon(
                              Icons.fingerprint_rounded,
                              size: 18,
                            ),
                            label: const Text(
                              'Unlock Preview',
                              style: TextStyle(fontSize: 12),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colors.primaryAccent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ] else ...[
              // PDF or generic encrypted file preview state
              InkWell(
                onTap: doc.files.isNotEmpty
                    ? () => _openViewer(doc.files.first)
                    : null,
                child: Center(
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
                      const SizedBox(height: 6),
                      Text(
                        'Tap to Unlock with Biometrics',
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.primaryAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
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

  Widget _buildExtractedDetailsPreviewCard(
    DocumentModel doc,
    AppThemeColors colors,
  ) {
    final allFields = _extraction?.fields ?? [];
    final previewFields = allFields.where((f) => f.isSelected).toList();
    final unselectedCount = allFields.where((f) => !f.isSelected).length;

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
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: colors.primaryAccent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  color: colors.primaryAccent,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Extracted Details',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                    ),
                    Text(
                      '${previewFields.length} of ${allFields.length} fields shown on preview',
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: _showMoveExtractedFieldsSheet,
                icon: const Icon(Icons.tune_rounded, size: 16),
                label: const Text(
                  'Move / Select',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          if (previewFields.isEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(
                vertical: 16,
                horizontal: 14,
              ),
              decoration: BoxDecoration(
                color: colors.surface.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colors.cardBorder.withValues(alpha: 0.5),
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.dashboard_customize_outlined,
                    size: 36,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No extracted info moved to Preview yet',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Choose which OCR extracted details you want visible right here on the Preview page.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: _showMoveExtractedFieldsSheet,
                    icon: const Icon(Icons.add_to_photos_rounded, size: 16),
                    label: const Text('Move Extracted Info to Preview'),
                  ),
                ],
              ),
            ),
          ] else ...[
            for (final field in previewFields)
              _buildExtractedPreviewRow(field, colors),
            if (unselectedCount > 0) ...[
              const SizedBox(height: 4),
              Center(
                child: TextButton.icon(
                  onPressed: _showMoveExtractedFieldsSheet,
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: Text(
                    '+ Add $unselectedCount more extracted fields to Preview',
                    style: TextStyle(
                      color: colors.primaryAccent,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildExtractedPreviewRow(
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              field.fieldName,
              style: TextStyle(
                fontSize: 12,
                color: colors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    displayValue,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
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
                    tooltip: 'Reveal/Mask',
                  ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                    Icons.copy_rounded,
                    size: 16,
                    color: colors.textSecondary,
                  ),
                  onPressed: () => _copyField(field.fieldName, value),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Copy',
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
            decoration: BoxDecoration(
              color: colors.cardBackground,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.cardBorder),
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _openViewer(file),
                child: Padding(
                  padding: const EdgeInsets.all(12),
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
                        tooltip: 'Unlock file with biometrics',
                      ),
                    ],
                  ),
                ),
              ),
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
            children: [
              Text(
                'Extracted Fields (${fields.where((f) => f.isSelected).length} on Preview)',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () =>
                    _moveAllToPreview(fields.any((f) => !f.isSelected)),
                icon: Icon(
                  fields.any((f) => !f.isSelected)
                      ? Icons.select_all_rounded
                      : Icons.deselect_rounded,
                  size: 16,
                  color: colors.primaryAccent,
                ),
                label: Text(
                  fields.any((f) => !f.isSelected)
                      ? 'Move All to Preview'
                      : 'Remove All from Preview',
                  style: TextStyle(color: colors.primaryAccent, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final field in fields)
            _buildExtractedFieldCard(field, colors),
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
          const SizedBox(height: 10),
          Row(
            children: [
              ActionChip(
                avatar: Icon(
                  field.isSelected
                      ? Icons.check_circle_rounded
                      : Icons.add_circle_outline_rounded,
                  size: 14,
                  color: field.isSelected
                      ? colors.primaryAccent
                      : colors.textSecondary,
                ),
                label: Text(
                  field.isSelected ? 'Shown on Preview' : 'Move to Preview',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: field.isSelected
                        ? colors.primaryAccent
                        : colors.textSecondary,
                  ),
                ),
                backgroundColor: field.isSelected
                    ? colors.primaryAccent.withValues(alpha: 0.12)
                    : colors.surface.withValues(alpha: 0.5),
                side: BorderSide(
                  color: field.isSelected
                      ? colors.primaryAccent
                      : colors.cardBorder,
                ),
                onPressed: () => _toggleFieldOnPreview(field),
              ),
              const Spacer(),
              if (field.isVerified)
                Row(
                  children: [
                    Icon(
                      Icons.verified_rounded,
                      size: 14,
                      color: colors.primaryAccent,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Verified',
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.primaryAccent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}
