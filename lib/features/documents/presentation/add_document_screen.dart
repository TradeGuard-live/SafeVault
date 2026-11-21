import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../../core/constants/category_constants.dart';
import '../../../core/errors/exceptions.dart';
import '../../../core/security/file_validator.dart';
import '../../../core/services/native_saf_and_share_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/error_dialog.dart';
import '../../authentication/presentation/auth_providers.dart';
import '../../categories/domain/category_model.dart';
import '../../ocr/data/document_text_extractor.dart';
import '../data/document_draft_repository.dart';
import '../domain/document_draft_model.dart';
import '../domain/document_file_model.dart';
import '../domain/document_model.dart';

class AddDocumentScreen extends ConsumerStatefulWidget {
  final String? initialFilePath;
  final String? mimeType;
  final String? initialFileName;
  final String? defaultCategoryId;
  final DocumentModel? editDocument;
  final Map<String, dynamic>? ocrData;

  const AddDocumentScreen({
    super.key,
    this.initialFilePath,
    this.mimeType,
    this.initialFileName,
    this.defaultCategoryId,
    this.editDocument,
    this.ocrData,
  });

  @override
  ConsumerState<AddDocumentScreen> createState() => _AddDocumentScreenState();
}

class _AddDocumentScreenState extends ConsumerState<AddDocumentScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _docNumberController;
  late TextEditingController _ownerNameController;
  late TextEditingController _authorityController;
  late TextEditingController _notesController;
  late TextEditingController _tagsController;

  String _selectedCategoryId = 'personal_identity';
  String? _selectedDocumentType;
  DateTime? _issueDate;
  DateTime? _expiryDate;

  final List<Map<String, dynamic>> _attachedFiles = [];
  bool _isSaving = false;
  bool _hasRestoredDraft = false;
  Timer? _draftAutoSaveTimer;

  @override
  void initState() {
    super.initState();

    final edit = widget.editDocument;
    final ocr = widget.ocrData;

    _nameController = TextEditingController(
      text: edit?.name ?? ocr?['name'] ?? widget.initialFileName ?? '',
    );
    _docNumberController = TextEditingController(
      text: edit?.documentNumber ?? ocr?['documentNumber'] ?? '',
    );
    _ownerNameController = TextEditingController(
      text: edit?.ownerName ?? ocr?['ownerName'] ?? '',
    );
    _authorityController = TextEditingController(
      text: edit?.issuingAuthority ?? ocr?['issuingAuthority'] ?? '',
    );
    _notesController = TextEditingController(text: edit?.notes ?? '');
    _tagsController = TextEditingController(text: edit?.tags.join(', ') ?? '');

    _selectedCategoryId =
        edit?.categoryId ??
        ocr?['categoryId'] ??
        widget.defaultCategoryId ??
        'personal_identity';

    _selectedDocumentType = edit?.documentType ?? ocr?['documentType'];
    _issueDate = edit?.issueDate ?? ocr?['issueDate'];
    _expiryDate = edit?.expiryDate ?? ocr?['expiryDate'];

    if (widget.initialFilePath != null) {
      _attachedFiles.add({
        'path': widget.initialFilePath,
        'mimeType': widget.mimeType ?? 'application/octet-stream',
        'name': widget.initialFileName ?? 'Imported Document',
      });
    }

    _nameController.addListener(_scheduleDraftAutoSave);
    _docNumberController.addListener(_scheduleDraftAutoSave);
    _ownerNameController.addListener(_scheduleDraftAutoSave);
    _authorityController.addListener(_scheduleDraftAutoSave);
    _notesController.addListener(_scheduleDraftAutoSave);
    _tagsController.addListener(_scheduleDraftAutoSave);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreDraftIfAvailable();
    });
  }

  @override
  void dispose() {
    _draftAutoSaveTimer?.cancel();
    _nameController.removeListener(_scheduleDraftAutoSave);
    _docNumberController.removeListener(_scheduleDraftAutoSave);
    _ownerNameController.removeListener(_scheduleDraftAutoSave);
    _authorityController.removeListener(_scheduleDraftAutoSave);
    _notesController.removeListener(_scheduleDraftAutoSave);
    _tagsController.removeListener(_scheduleDraftAutoSave);

    _nameController.dispose();
    _docNumberController.dispose();
    _ownerNameController.dispose();
    _authorityController.dispose();
    _notesController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  void _scheduleDraftAutoSave() {
    if (widget.editDocument != null) return;
    _draftAutoSaveTimer?.cancel();
    _draftAutoSaveTimer = Timer(const Duration(milliseconds: 600), () {
      _saveCurrentDraft();
    });
  }

  Future<void> _saveCurrentDraft() async {
    if (widget.editDocument != null) return;
    final session = ref.read(vaultSessionProvider);
    if (!session.isUnlocked || session.masterKey == null) return;

    final tags = _tagsController.text
        .split(',')
        .map((t) => t.trim().replaceAll('#', ''))
        .where((t) => t.isNotEmpty)
        .toList();

    final draft = DocumentDraftModel(
      title: _nameController.text,
      categoryId: _selectedCategoryId,
      documentType: _selectedDocumentType,
      documentNumber: _docNumberController.text,
      ownerName: _ownerNameController.text,
      issuingAuthority: _authorityController.text,
      issueDate: _issueDate,
      expiryDate: _expiryDate,
      notes: _notesController.text,
      tags: tags,
      attachedFiles: List.from(_attachedFiles),
      updatedAt: DateTime.now(),
    );

    if (draft.isEmpty) {
      await ref.read(documentDraftRepositoryProvider).deleteDraft();
    } else {
      await ref
          .read(documentDraftRepositoryProvider)
          .saveDraft(draft, session.masterKey!);
    }
  }

  Future<void> _restoreDraftIfAvailable() async {
    // A draft belongs only to a blank manual add flow. It must never replace
    // metadata or attachments supplied by a newly scanned, shared, or OCR'd
    // document.
    if (!mounted ||
        widget.editDocument != null ||
        widget.initialFilePath != null ||
        widget.ocrData != null ||
        widget.defaultCategoryId != null) {
      return;
    }
    final session = ref.read(vaultSessionProvider);
    if (!session.isUnlocked || session.masterKey == null) return;

    try {
      final draft = await ref
          .read(documentDraftRepositoryProvider)
          .getDraft(session.masterKey!);
      if (draft != null && draft.isNotEmpty && mounted) {
        setState(() {
          if (_nameController.text.isEmpty && draft.title.isNotEmpty) {
            _nameController.text = draft.title;
          }
          if (_docNumberController.text.isEmpty &&
              draft.documentNumber != null) {
            _docNumberController.text = draft.documentNumber!;
          }
          if (_ownerNameController.text.isEmpty && draft.ownerName != null) {
            _ownerNameController.text = draft.ownerName!;
          }
          if (_authorityController.text.isEmpty &&
              draft.issuingAuthority != null) {
            _authorityController.text = draft.issuingAuthority!;
          }
          if (_notesController.text.isEmpty && draft.notes != null) {
            _notesController.text = draft.notes!;
          }
          if (_tagsController.text.isEmpty && draft.tags.isNotEmpty) {
            _tagsController.text = draft.tags.join(', ');
          }
          if (draft.categoryId.isNotEmpty) {
            _selectedCategoryId = draft.categoryId;
          }
          if (draft.documentType != null) {
            _selectedDocumentType = draft.documentType;
          }
          if (draft.issueDate != null) {
            _issueDate = draft.issueDate;
          }
          if (draft.expiryDate != null) {
            _expiryDate = draft.expiryDate;
          }

          // Restore attached files that still exist on disk
          for (final f in draft.attachedFiles) {
            final path = f['path'] as String?;
            if (path != null && File(path).existsSync()) {
              if (!_attachedFiles.any((existing) => existing['path'] == path)) {
                _attachedFiles.add(Map<String, dynamic>.from(f));
              }
            }
          }
          _hasRestoredDraft = true;
        });
      }
    } catch (e) {
      debugPrint('Failed to restore document draft: $e');
    }
  }

  bool _hasDraftContent() {
    return _nameController.text.trim().isNotEmpty ||
        _docNumberController.text.trim().isNotEmpty ||
        _ownerNameController.text.trim().isNotEmpty ||
        _authorityController.text.trim().isNotEmpty ||
        _notesController.text.trim().isNotEmpty ||
        _tagsController.text.trim().isNotEmpty ||
        _attachedFiles.isNotEmpty;
  }

  Future<void> _discardDraft() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard Draft?'),
        content: const Text(
          'Are you sure you want to discard this draft? All entered information and attached files will be cleared.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep Draft'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(documentDraftRepositoryProvider).deleteDraft();
      if (mounted) {
        setState(() {
          _nameController.clear();
          _docNumberController.clear();
          _ownerNameController.clear();
          _authorityController.clear();
          _notesController.clear();
          _tagsController.clear();
          _attachedFiles.clear();
          _hasRestoredDraft = false;
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Draft discarded.')));
      }
    }
  }

  Future<bool> _onWillPop() async {
    if (widget.editDocument != null || !_hasDraftContent()) {
      return true;
    }

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Unsaved Document'),
        content: const Text(
          'You have unsaved document changes. Would you like to keep the draft for later or discard it?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('cancel'),
            child: const Text('Continue Editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('discard'),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop('keep'),
            child: const Text('Keep Draft & Exit'),
          ),
        ],
      ),
    );

    if (action == 'discard') {
      await ref.read(documentDraftRepositoryProvider).deleteDraft();
      return true;
    } else if (action == 'keep') {
      await _saveCurrentDraft();
      return true;
    }
    return false;
  }

  Future<void> _pickAdditionalFile() async {
    // Persist current draft before launching file picker
    await _saveCurrentDraft();

    try {
      final safItems = await NativeSafAndShareService.instance.pickDocuments(
        allowMultiple: true,
      );

      if (safItems.isNotEmpty) {
        for (final item in safItems) {
          final file = File(item.path);
          if (await file.exists()) {
            final validation = await FileValidator.validateFile(file);
            setState(() {
              _attachedFiles.add({
                'path': item.path,
                'mimeType': validation.mimeType,
                'name': item.name,
              });
            });
          }
        }
        await _saveCurrentDraft();
        return;
      }

      // Fallback for non-Android / test platforms
      final session = ref.read(vaultSessionProvider);
      session.beginSystemActivity('FILE_PICKER_FALLBACK');
      List<PlatformFile> files;
      try {
        final res = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
        );
        files = res;
      } finally {
        Future.microtask(() => session.endSystemActivity());
      }

      if (files.isNotEmpty) {
        for (final pf in files) {
          if (pf.path != null) {
            final file = File(pf.path!);
            final validation = await FileValidator.validateFile(file);
            setState(() {
              _attachedFiles.add({
                'path': pf.path,
                'mimeType': validation.mimeType,
                'name': pf.name,
              });
            });
          }
        }
        await _saveCurrentDraft();
      }
    } catch (e) {
      if (mounted) {
        ErrorDialog.show(context, title: 'Attach Error', message: e.toString());
      }
    }
  }

  Future<void> _pickDate({required bool isIssueDate}) async {
    final now = DateTime.now();
    final initial = isIssueDate
        ? (_issueDate ?? now)
        : (_expiryDate ?? now.add(const Duration(days: 365)));

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1960),
      lastDate: DateTime(2065),
      builder: (ctx, child) {
        final colors = context.themeColors;
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme(
              brightness: colors.isDark ? Brightness.dark : Brightness.light,
              primary: colors.primaryAccent,
              onPrimary: colors.onPrimaryAccent,
              secondary: colors.primaryPeach,
              onSecondary: colors.onPrimaryAccent,
              error: colors.error,
              onError: colors.onError,
              surface: colors.cardElevated,
              onSurface: colors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        if (isIssueDate) {
          _issueDate = picked;
        } else {
          _expiryDate = picked;
        }
      });
    }
  }

  Future<void> _saveDocument() async {
    if (!_formKey.currentState!.validate()) return;

    if (widget.editDocument == null && _attachedFiles.isEmpty) {
      ErrorDialog.show(
        context,
        title: 'Missing File',
        message: 'Please attach at least one document file or scan page.',
      );
      return;
    }

    final session = ref.read(vaultSessionProvider);
    if (!session.isUnlocked || session.masterKey == null) {
      context.go('/pin-unlock');
      return;
    }

    // Validate the selected category before any encryption/file work so we
    // never create orphan encrypted files for an invalid category.
    final knownCategories =
        ref.read(categoriesProvider).valueOrNull ?? const [];
    if (knownCategories.isNotEmpty &&
        !knownCategories.any((c) => c.id == _selectedCategoryId)) {
      ErrorDialog.show(
        context,
        title: 'Invalid Category',
        message: 'The selected category is no longer available. Please choose another category.',
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final storage = ref.read(storageServiceProvider);
      final repo = ref.read(documentRepositoryProvider);

      final tags = _tagsController.text
          .split(',')
          .map((t) => t.trim().replaceAll('#', ''))
          .where((t) => t.isNotEmpty)
          .toList();

      if (widget.editDocument != null) {
        // Update existing document metadata
        await repo.updateDocumentMetadata(
          documentId: widget.editDocument!.id,
          name: _nameController.text.trim(),
          categoryId: _selectedCategoryId,
          documentNumber: _docNumberController.text.trim().isEmpty
              ? null
              : _docNumberController.text.trim(),
          ownerName: _ownerNameController.text.trim().isEmpty
              ? null
              : _ownerNameController.text.trim(),
          issuingAuthority: _authorityController.text.trim().isEmpty
              ? null
              : _authorityController.text.trim(),
          issueDate: _issueDate,
          expiryDate: _expiryDate,
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
          tags: tags,
          documentType: _selectedDocumentType,
          masterKey: session.masterKey!,
        );
      } else {
        // Create new document & encrypt files
        final List<DocumentFileModel> encryptedFiles = [];
        final List<String> encryptedPaths = [];
        try {
          for (int i = 0; i < _attachedFiles.length; i++) {
            if (!session.isUnlocked) throw const VaultLockedException();
            final masterKey = session.getMasterKeyOrThrow();

            final fileInfo = _attachedFiles[i];
            final rawFile = File(fileInfo['path'] as String);
            if (!await rawFile.exists()) {
              throw Exception('Source file no longer exists: ${rawFile.path}');
            }
            final plainBytes = await rawFile.readAsBytes();

            final encPath = await storage.saveEncryptedFile(
              plainBytes: plainBytes,
              masterKey: masterKey,
            );
            encryptedPaths.add(encPath);

            encryptedFiles.add(
              DocumentFileModel(
                id: '',
                documentId: '',
                encryptedFilePath: encPath,
                originalFileName: fileInfo['name'] as String,
                mimeType: fileInfo['mimeType'] as String,
                fileSize: plainBytes.length,
                pageNumber: i + 1,
                createdAt: DateTime.now(),
              ),
            );
          }

          if (!session.isUnlocked) throw const VaultLockedException();
          final masterKey = session.getMasterKeyOrThrow();

          final newDoc = await repo.addDocument(
            name: _nameController.text.trim(),
            categoryId: _selectedCategoryId,
            documentNumber: _docNumberController.text.trim().isEmpty
                ? null
                : _docNumberController.text.trim(),
            ownerName: _ownerNameController.text.trim().isEmpty
                ? null
                : _ownerNameController.text.trim(),
            issuingAuthority: _authorityController.text.trim().isEmpty
                ? null
                : _authorityController.text.trim(),
            issueDate: _issueDate,
            expiryDate: _expiryDate,
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
            tags: tags,
            documentType: _selectedDocumentType,
            files: encryptedFiles,
            masterKey: masterKey,
          );

          // Automatic Text Extraction Pipeline (Offline)
          if (encryptedFiles.isNotEmpty) {
            try {
              final firstFile = encryptedFiles.first;
              final plainBytes = await storage.readDecryptedFile(
                filePath: firstFile.encryptedFilePath,
                masterKey: session.getMasterKeyOrThrow(),
              );
              final extractor = DocumentTextExtractor();
              final result = await extractor.processDocumentBytes(
                bytes: plainBytes,
                fileName: firstFile.originalFileName,
                mimeType: firstFile.mimeType,
              );
              final formattedTxt =
                  DocumentTextExtractor.generateFormattedTextRecord(
                    documentType: result.classification.documentType,
                    categoryName: _selectedCategoryId,
                    sourceFileName: firstFile.originalFileName,
                    fullText: result.fullText,
                    fields: result.fields,
                    engine: result.extractionEngine,
                    language: result.language,
                    pageCount: result.pageCount,
                  );
              final encTxtPath = await repo.saveExtractedTxtFile(
                documentId: newDoc.id,
                textContent: formattedTxt,
                masterKey: session.getMasterKeyOrThrow(),
              );
              await repo.saveExtraction(
                documentId: newDoc.id,
                documentType: result.classification.documentType,
                extractedText: result.fullText,
                fields: result.fields,
                engine: result.extractionEngine,
                language: result.language,
                pageCount: result.pageCount,
                encryptedTxtFilePath: encTxtPath,
                masterKey: session.getMasterKeyOrThrow(),
              );
            } catch (ocrError) {
              debugPrint(
                'Auto text extraction during add document error: $ocrError',
              );
              // Keep the document with an honest extraction-failed status.
              await repo.updateExtractionStatus(newDoc.id, 'failed');
            }
          }

          // Only now that DB document creation succeeded, securely wipe raw
          // scan/OCR temp inputs.
          for (int i = 0; i < _attachedFiles.length; i++) {
            final rawPath = _attachedFiles[i]['path'] as String;
            final fileName = p.basename(rawPath);
            if (fileName.startsWith('scan_') || fileName.startsWith('ocr_')) {
              await storage.securelyDeleteFile(rawPath);
            }
          }
        } catch (e) {
          // Compensating cleanup: remove orphan encrypted files if DB insert
          // or any later step failed.
          for (final path in encryptedPaths) {
            try {
              await storage.securelyDeleteFile(path);
            } catch (_) {}
          }
          rethrow;
        }
      }

      // Successful save: delete persisted draft
      await ref.read(documentDraftRepositoryProvider).deleteDraft();

      ref.invalidate(activeDocumentsProvider);
      ref.invalidate(expiringDocumentsProvider);
      ref.invalidate(favoriteDocumentsProvider);

      if (mounted) {
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
    final catsAsync = ref.watch(categoriesProvider);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          context.pop();
        }
      },
      child: Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(
          title: Text(
            widget.editDocument != null ? 'Edit Document' : 'Add Document',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            children: [
              if (_hasRestoredDraft) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: colors.primaryAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: colors.primaryAccent.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.restore_page_rounded,
                        color: colors.primaryAccent,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Restored unsaved draft from your previous session.',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _discardDraft,
                        child: Text(
                          'Discard',
                          style: TextStyle(
                            color: colors.error,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              // Name Field
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Document Name *',
                  hintText: 'e.g. My Aadhaar Card, Driving Licence',
                  prefixIcon: Icon(Icons.title_rounded),
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Please enter a document name'
                    : null,
              ),
              const SizedBox(height: 14),

              // Category Dropdown
              catsAsync.when(
                data: (categories) {
                  return DropdownButtonFormField<String>(
                    value: categories.any((c) => c.id == _selectedCategoryId)
                        ? _selectedCategoryId
                        : categories.first.id,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      prefixIcon: Icon(Icons.category_outlined),
                    ),
                    items: categories.map((c) {
                      return DropdownMenuItem(value: c.id, child: Text(c.name));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedCategoryId = val);
                      }
                    },
                  );
                },
                loading: () => const LinearProgressIndicator(),
                error: (_, __) => const SizedBox.shrink(),
              ),
              const SizedBox(height: 14),

              // Document Number
              TextFormField(
                controller: _docNumberController,
                decoration: const InputDecoration(
                  labelText: 'Document Number (Encrypted at Rest)',
                  hintText: 'e.g. 1234 5678 9012, DL-1420110012345',
                  prefixIcon: Icon(Icons.tag_rounded),
                ),
              ),
              const SizedBox(height: 14),

              // Owner Name
              TextFormField(
                controller: _ownerNameController,
                decoration: const InputDecoration(
                  labelText: 'Owner / Name on Document',
                  hintText: 'e.g. John Doe',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
              ),
              const SizedBox(height: 14),

              // Issuing Authority
              TextFormField(
                controller: _authorityController,
                decoration: const InputDecoration(
                  labelText: 'Issuing Authority',
                  hintText: 'e.g. UIDAI, Transport Dept, Income Tax',
                  prefixIcon: Icon(Icons.account_balance_outlined),
                ),
              ),
              const SizedBox(height: 14),

              // Dates Row
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => _pickDate(isIssueDate: true),
                      borderRadius: BorderRadius.circular(12),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Issue Date',
                          prefixIcon: Icon(
                            Icons.calendar_today_outlined,
                            size: 18,
                          ),
                        ),
                        child: Text(
                          _issueDate != null
                              ? DateFormatter.formatDisplay(_issueDate)
                              : 'Select date',
                          style: TextStyle(
                            fontSize: 13.5,
                            color: _issueDate != null
                                ? colors.textPrimary
                                : colors.textTertiary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () => _pickDate(isIssueDate: false),
                      borderRadius: BorderRadius.circular(12),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Expiry Date',
                          prefixIcon: Icon(Icons.event_busy_outlined, size: 18),
                        ),
                        child: Text(
                          _expiryDate != null
                              ? DateFormatter.formatDisplay(_expiryDate)
                              : 'Select date',
                          style: TextStyle(
                            fontSize: 13.5,
                            color: _expiryDate != null
                                ? colors.textPrimary
                                : colors.textTertiary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Tags
              TextFormField(
                controller: _tagsController,
                decoration: const InputDecoration(
                  labelText: 'Tags (comma separated)',
                  hintText: 'identity, official, renewed',
                  prefixIcon: Icon(Icons.tag_outlined),
                ),
              ),
              const SizedBox(height: 14),

              // Notes
              TextFormField(
                controller: _notesController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Secure Notes (Encrypted at Rest)',
                  hintText: 'Confidential remarks or details...',
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
              ),
              const SizedBox(height: 20),

              // Attached Files Section (only for new docs)
              if (widget.editDocument == null) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Attached Pages (${_attachedFiles.length})',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _pickAdditionalFile,
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add File/Page'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_attachedFiles.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colors.cardBackground,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colors.cardBorder),
                    ),
                    child: Center(
                      child: Text(
                        'No files attached yet. Tap "+ Add File/Page" above.',
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.textTertiary,
                        ),
                      ),
                    ),
                  )
                else
                  ..._attachedFiles.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final item = entry.value;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: colors.cardBackground,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colors.cardBorder),
                      ),
                      child: ListTile(
                        dense: true,
                        leading: Icon(
                          Icons.attachment_rounded,
                          color: colors.primaryAccent,
                        ),
                        title: Text(
                          'Page ${idx + 1}: ${item['name']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () {
                            setState(() {
                              _attachedFiles.removeAt(idx);
                            });
                          },
                        ),
                      ),
                    );
                  }),
                const SizedBox(height: 24),
              ],

              // Save Button
              ElevatedButton(
                onPressed: _isSaving ? null : _saveDocument,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        widget.editDocument != null
                            ? 'Update Metadata'
                            : 'Encrypt & Save Document',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
