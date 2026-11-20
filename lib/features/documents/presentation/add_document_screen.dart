import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import '../../../core/constants/category_constants.dart';
import '../../../core/security/file_validator.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/error_dialog.dart';
import '../../authentication/presentation/auth_providers.dart';
import '../../categories/domain/category_model.dart';
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

    _selectedCategoryId = edit?.categoryId ??
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
  }

  @override
  void dispose() {
    _nameController.dispose();
    _docNumberController.dispose();
    _ownerNameController.dispose();
    _authorityController.dispose();
    _notesController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _pickAdditionalFile() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      );

      if (files.isEmpty) return;

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
    } catch (e) {
      if (mounted) {
        ErrorDialog.show(context, title: 'Attach Error', message: e.toString());
      }
    }
  }

  Future<void> _pickDate({required bool isIssueDate}) async {
    final now = DateTime.now();
    final initial = isIssueDate ? (_issueDate ?? now) : (_expiryDate ?? now.add(const Duration(days: 365)));

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
          documentNumber: _docNumberController.text.trim().isEmpty ? null : _docNumberController.text.trim(),
          ownerName: _ownerNameController.text.trim().isEmpty ? null : _ownerNameController.text.trim(),
          issuingAuthority: _authorityController.text.trim().isEmpty ? null : _authorityController.text.trim(),
          issueDate: _issueDate,
          expiryDate: _expiryDate,
          notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
          tags: tags,
          documentType: _selectedDocumentType,
          masterKey: session.masterKey!,
        );
      } else {
        // Create new document & encrypt files
        final List<DocumentFileModel> encryptedFiles = [];
        for (int i = 0; i < _attachedFiles.length; i++) {
          final fileInfo = _attachedFiles[i];
          final rawFile = File(fileInfo['path'] as String);
          final plainBytes = await rawFile.readAsBytes();

          final encPath = await storage.saveEncryptedFile(
            plainBytes: plainBytes,
            masterKey: session.masterKey!,
          );

          // Securely wipe ephemeral scanner/OCR temp files from cache
          final rawPath = fileInfo['path'] as String;
          final fileName = p.basename(rawPath);
          if (fileName.startsWith('scan_') || fileName.startsWith('ocr_')) {
            await storage.securelyDeleteFile(rawPath);
          }

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

        await repo.addDocument(
          name: _nameController.text.trim(),
          categoryId: _selectedCategoryId,
          documentNumber: _docNumberController.text.trim().isEmpty ? null : _docNumberController.text.trim(),
          ownerName: _ownerNameController.text.trim().isEmpty ? null : _ownerNameController.text.trim(),
          issuingAuthority: _authorityController.text.trim().isEmpty ? null : _authorityController.text.trim(),
          issueDate: _issueDate,
          expiryDate: _expiryDate,
          notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
          tags: tags,
          documentType: _selectedDocumentType,
          files: encryptedFiles,
          masterKey: session.masterKey!,
        );
      }

      ref.invalidate(activeDocumentsProvider);
      ref.invalidate(expiringDocumentsProvider);

      if (mounted) {
        context.pop();
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

    return Scaffold(
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
            // Name Field
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Document Name *',
                hintText: 'e.g. My Aadhaar Card, Driving Licence',
                prefixIcon: Icon(Icons.title_rounded),
              ),
              validator: (v) => v == null || v.trim().isEmpty ? 'Please enter a document name' : null,
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
                    return DropdownMenuItem(
                      value: c.id,
                      child: Text(c.name),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedCategoryId = val);
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
                        prefixIcon: Icon(Icons.calendar_today_outlined, size: 18),
                      ),
                      child: Text(
                        _issueDate != null ? DateFormatter.formatDisplay(_issueDate) : 'Select date',
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
                        _expiryDate != null ? DateFormatter.formatDisplay(_expiryDate) : 'Select date',
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
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
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
                      style: TextStyle(fontSize: 13, color: colors.textTertiary),
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
                      leading: Icon(Icons.attachment_rounded, color: colors.primaryAccent),
                      title: Text(
                        'Page ${idx + 1}: ${item['name']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
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
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      widget.editDocument != null ? 'Update Metadata' : 'Encrypt & Save Document',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
