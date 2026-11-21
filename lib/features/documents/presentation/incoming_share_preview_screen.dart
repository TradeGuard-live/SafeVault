import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdfx/pdfx.dart' as pfx;

import '../../../core/constants/category_constants.dart';
import '../../../core/routes/app_router.dart';
import '../../../core/services/native_saf_and_share_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../../core/widgets/error_dialog.dart';
import '../../../core/widgets/status_badge.dart';
import '../../authentication/presentation/auth_providers.dart';
import '../../categories/domain/category_model.dart';
import '../../ocr/data/document_text_extractor.dart';
import '../../ocr/data/offline_ocr_service.dart';
import '../domain/document_file_model.dart';
import '../domain/document_model.dart';

class IncomingShareItemState {
  final SafFileItem item;
  String customName;
  String selectedCategoryId;
  int pageCount;
  Uint8List? thumbnailBytes;
  String status; // 'pending', 'importing', 'extracting', 'completed', 'failed'
  String? errorMessage;

  IncomingShareItemState({
    required this.item,
    required this.customName,
    this.selectedCategoryId = 'personal_identity',
    this.pageCount = 1,
    this.thumbnailBytes,
    this.status = 'pending',
    this.errorMessage,
  });
}

class IncomingSharePreviewScreen extends ConsumerStatefulWidget {
  final List<SafFileItem> incomingFiles;

  const IncomingSharePreviewScreen({super.key, required this.incomingFiles});

  @override
  ConsumerState<IncomingSharePreviewScreen> createState() =>
      _IncomingSharePreviewScreenState();
}

class _IncomingSharePreviewScreenState
    extends ConsumerState<IncomingSharePreviewScreen> {
  final List<IncomingShareItemState> _items = [];
  final List<DocumentModel> _importedDocuments = [];
  bool _isProcessingAll = false;
  bool _allImportsCompleted = false;

  @override
  void initState() {
    super.initState();
    _initializeItems();
  }

  Future<void> _initializeItems() async {
    for (final file in widget.incomingFiles) {
      final nameWithoutExt = file.name.contains('.')
          ? file.name.substring(0, file.name.lastIndexOf('.'))
          : file.name;

      final state = IncomingShareItemState(
        item: file,
        customName: nameWithoutExt.replaceAll('_', ' '),
      );
      _items.add(state);

      // Asynchronously load thumbnail and page count
      _loadItemMetadata(state);
    }
    setState(() {});
  }

  Future<void> _loadItemMetadata(IncomingShareItemState state) async {
    try {
      final file = File(state.item.path);
      if (!await file.exists()) return;

      if (state.item.isPdf) {
        final pdfDoc = await pfx.PdfDocument.openFile(state.item.path);
        state.pageCount = pdfDoc.pagesCount;
        final firstPage = await pdfDoc.getPage(1);
        final rendered = await firstPage.render(
          width: 200,
          height: 200,
          format: pfx.PdfPageImageFormat.png,
        );
        await firstPage.close();
        await pdfDoc.close();
        if (rendered != null && mounted) {
          setState(() => state.thumbnailBytes = rendered.bytes);
        }
      } else if (state.item.isImage) {
        final bytes = await file.readAsBytes();
        if (mounted) {
          setState(() => state.thumbnailBytes = bytes);
        }
      }
    } catch (_) {}
  }

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
    });
    if (_items.isEmpty && mounted) {
      NativeSafAndShareService.instance.clearPendingIncomingShares();
      context.go('/all-documents');
    }
  }

  Future<void> _importItem(IncomingShareItemState itemState) async {
    final session = ref.read(vaultSessionProvider);
    if (!session.isUnlocked || session.masterKey == null) {
      if (mounted) context.go('/pin-unlock');
      return;
    }

    setState(() {
      itemState.status = 'importing';
      itemState.errorMessage = null;
    });

    try {
      final repo = ref.read(documentRepositoryProvider);
      final storage = ref.read(storageServiceProvider);
      final rawFile = File(itemState.item.path);
      final fileBytes = await rawFile.readAsBytes();

      // 1. Encrypt and save original file
      final encryptedPath = await storage.saveEncryptedFile(
        plainBytes: fileBytes,
        masterKey: session.masterKey!,
      );

      final docFile = DocumentFileModel(
        id: '',
        documentId: '',
        encryptedFilePath: encryptedPath,
        originalFileName: itemState.item.name,
        mimeType: itemState.item.mimeType,
        fileSize: itemState.item.size,
        pageNumber: 1,
        createdAt: DateTime.now(),
      );

      // 2. Create document record
      final newDoc = await repo.addDocument(
        name: itemState.customName.trim().isEmpty
            ? itemState.item.name
            : itemState.customName.trim(),
        categoryId: itemState.selectedCategoryId,
        files: [docFile],
        masterKey: session.masterKey!,
      );
      _importedDocuments.add(newDoc);

      // 3. Automatic Text & Information Extraction Pipeline
      if (mounted) {
        setState(() => itemState.status = 'extracting');
      }
      try {
        final extractor = DocumentTextExtractor();
        final extractionResult = await extractor.processDocumentBytes(
          bytes: fileBytes,
          fileName: itemState.item.name,
          mimeType: itemState.item.mimeType,
        );

        // Generate formatted human-readable TXT file
        final formattedTxt = DocumentTextExtractor.generateFormattedTextRecord(
          documentType: extractionResult.classification.documentType,
          categoryName: itemState.selectedCategoryId,
          sourceFileName: itemState.item.name,
          fullText: extractionResult.fullText,
          fields: extractionResult.fields,
          engine: extractionResult.extractionEngine,
          language: extractionResult.language,
          pageCount: extractionResult.pageCount,
        );

        // Save encrypted TXT companion record
        final encTxtPath = await repo.saveExtractedTxtFile(
          documentId: newDoc.id,
          textContent: formattedTxt,
          masterKey: session.masterKey!,
        );

        // Save structured database extraction
        await repo.saveExtraction(
          documentId: newDoc.id,
          extractedText: extractionResult.fullText,
          fields: extractionResult.fields,
          engine: extractionResult.extractionEngine,
          language: extractionResult.language,
          pageCount: extractionResult.pageCount,
          encryptedTxtFilePath: encTxtPath,
          masterKey: session.masterKey!,
        );

        // Update document with recognized metadata
        await repo.updateDocumentMetadata(
          documentId: newDoc.id,
          name: newDoc.name,
          categoryId: itemState.selectedCategoryId,
          documentType: extractionResult.classification.documentType,
          documentNumber: extractionResult.fields
              .where(
                (f) =>
                    f.fieldName.contains('Number') ||
                    f.fieldName.contains('Licence') ||
                    f.fieldName.contains('Aadhaar'),
              )
              .map((f) => f.value)
              .firstOrNull,
          ownerName: extractionResult.fields
              .where(
                (f) =>
                    f.fieldName.contains('Name') &&
                    !f.fieldName.contains('Father'),
              )
              .map((f) => f.value)
              .firstOrNull,
          masterKey: session.masterKey!,
        );
      } catch (ocrError) {
        debugPrint('OCR extraction failed during import: $ocrError');
        // Document itself remains safely stored
      }

      if (mounted) {
        setState(() {
          itemState.status = 'completed';
          if (_items.every((i) => i.status == 'completed')) {
            _allImportsCompleted = true;
          }
        });
        if (_allImportsCompleted) {
          await NativeSafAndShareService.instance.clearPendingIncomingShares();
          ref.read(pendingIncomingShareProvider.notifier).state = [];
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          itemState.status = 'failed';
          itemState.errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _importAll() async {
    setState(() => _isProcessingAll = true);
    for (final item in _items) {
      if (item.status != 'completed') {
        await _importItem(item);
      }
    }
    if (mounted) {
      setState(() => _isProcessingAll = false);
    }

    final completedCount = _items.where((i) => i.status == 'completed').length;
    if (completedCount == _items.length && completedCount > 0) {
      await NativeSafAndShareService.instance.clearPendingIncomingShares();
      ref.read(pendingIncomingShareProvider.notifier).state = [];
      if (mounted) {
        setState(() => _allImportsCompleted = true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.themeColors;

    if (_allImportsCompleted) {
      return Scaffold(
        backgroundColor: theme.background,
        appBar: AppBar(
          title: const Text('Import Successful'),
          backgroundColor: theme.surface,
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () => context.go('/dashboard'),
            ),
          ],
        ),
        body: SafeArea(child: _buildPostImportSuccessView(theme)),
      );
    }

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        title: const Text('Import Shared Documents'),
        backgroundColor: theme.surface,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () {
            NativeSafAndShareService.instance.clearPendingIncomingShares();
            context.go('/all-documents');
          },
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.surfaceElevated,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.cardBorder),
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
                      Icons.download_for_offline_rounded,
                      color: theme.primaryAccent,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_items.length} incoming file(s) from Sharesheet',
                          style: TextStyle(
                            color: theme.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Files will be encrypted with AES-256-GCM and processed offline.',
                          style: TextStyle(
                            color: theme.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final itemState = _items[index];
                  return _buildItemCard(theme, itemState, index);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isProcessingAll
                          ? null
                          : () {
                              NativeSafAndShareService.instance
                                  .clearPendingIncomingShares();
                              context.go('/all-documents');
                            },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Cancel All'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _isProcessingAll ? null : _importAll,
                      icon: _isProcessingAll
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.lock_rounded, size: 18),
                      label: Text(
                        _isProcessingAll
                            ? 'Importing...'
                            : 'Import All (${_items.length})',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.primaryAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemCard(
    AppThemeColors theme,
    IncomingShareItemState itemState,
    int index,
  ) {
    final sizeKb = (itemState.item.size / 1024).toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 60,
                  height: 60,
                  color: theme.surfaceElevated,
                  child: itemState.thumbnailBytes != null
                      ? Image.memory(
                          itemState.thumbnailBytes!,
                          fit: BoxFit.cover,
                        )
                      : Icon(
                          itemState.item.isPdf
                              ? Icons.picture_as_pdf_rounded
                              : Icons.image_rounded,
                          color: itemState.item.isPdf
                              ? Colors.redAccent
                              : theme.primaryAccent,
                          size: 32,
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      initialValue: itemState.customName,
                      style: TextStyle(
                        color: theme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 4),
                        border: InputBorder.none,
                        hintText: 'Enter document name',
                      ),
                      onChanged: (val) => itemState.customName = val,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${itemState.item.isPdf ? "PDF • ${itemState.pageCount} page(s)" : "Image"} • ${sizeKb} KB',
                      style: TextStyle(
                        color: theme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _buildStatusBadge(itemState),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.close_rounded,
                  color: theme.textSecondary,
                  size: 20,
                ),
                onPressed: () => _removeItem(index),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: itemState.selectedCategoryId,
                  dropdownColor: theme.surface,
                  style: TextStyle(color: theme.textPrimary, fontSize: 12),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: theme.cardBorder),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'personal_identity',
                      child: Text('Personal Identity'),
                    ),
                    DropdownMenuItem(
                      value: 'vehicle_documents',
                      child: Text('Vehicle Documents'),
                    ),
                    DropdownMenuItem(
                      value: 'financial_documents',
                      child: Text('Financial'),
                    ),
                    DropdownMenuItem(
                      value: 'education',
                      child: Text('Education'),
                    ),
                    DropdownMenuItem(
                      value: 'property',
                      child: Text('Property'),
                    ),
                    DropdownMenuItem(value: 'medical', child: Text('Medical')),
                    DropdownMenuItem(value: 'other', child: Text('Other')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => itemState.selectedCategoryId = val);
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed:
                    itemState.status == 'completed' ||
                        itemState.status == 'importing' ||
                        itemState.status == 'extracting'
                    ? null
                    : () => _importItem(itemState),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.primaryAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(
                  itemState.status == 'completed' ? 'Imported' : 'Import',
                ),
              ),
            ],
          ),
          if (itemState.errorMessage != null) ...[
            const SizedBox(height: 6),
            Text(
              itemState.errorMessage!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusBadge(IncomingShareItemState itemState) {
    switch (itemState.status) {
      case 'importing':
        return const Row(
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 6),
            Text(
              'Encrypting...',
              style: TextStyle(fontSize: 11, color: Colors.amber),
            ),
          ],
        );
      case 'extracting':
        return const Row(
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 6),
            Text(
              'Extracting Text...',
              style: TextStyle(fontSize: 11, color: Colors.blueAccent),
            ),
          ],
        );
      case 'completed':
        return const Row(
          children: [
            Icon(Icons.check_circle_rounded, size: 14, color: Colors.green),
            SizedBox(width: 4),
            Text(
              'Saved & Extracted',
              style: TextStyle(fontSize: 11, color: Colors.green),
            ),
          ],
        );
      case 'failed':
        return const Row(
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 14,
              color: Colors.redAccent,
            ),
            SizedBox(width: 4),
            Text(
              'Failed',
              style: TextStyle(fontSize: 11, color: Colors.redAccent),
            ),
          ],
        );
      default:
        return const Text(
          'Ready to import',
          style: TextStyle(fontSize: 11, color: Colors.grey),
        );
    }
  }

  Widget _buildPostImportSuccessView(AppThemeColors theme) {
    final firstDoc = _importedDocuments.isNotEmpty
        ? _importedDocuments.first
        : null;
    final count = _importedDocuments.length;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Success Icon
            Center(
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  size: 52,
                  color: Colors.green,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Title
            Text(
              count == 1
                  ? 'Document securely saved to Vault'
                  : '$count Documents securely saved to Vault',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: theme.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Encrypted with AES-256-GCM and stored completely offline on this device.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: theme.textSecondary),
            ),
            const SizedBox(height: 24),

            // Summary Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.surfaceElevated,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.cardBorder),
              ),
              child: Column(
                children: [
                  for (final doc in _importedDocuments)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Icon(
                            Icons.description_rounded,
                            color: theme.primaryAccent,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              doc.name,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: theme.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Saved',
                              style: TextStyle(
                                color: Colors.green,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.lock_outline_rounded,
                            size: 16,
                            color: Colors.green,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'AES-256-GCM',
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          const Icon(
                            Icons.auto_awesome_rounded,
                            size: 16,
                            color: Colors.teal,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Smart OCR',
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          const Icon(
                            Icons.wifi_off_rounded,
                            size: 16,
                            color: Colors.blueAccent,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '100% Offline',
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Button 1: View Document
            ElevatedButton.icon(
              onPressed: firstDoc != null
                  ? () {
                      context.push('/document/${firstDoc.id}?tab=0');
                    }
                  : null,
              icon: const Icon(Icons.visibility_rounded),
              label: const Text('View Document'),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primaryAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Button 2: View Extracted Information
            OutlinedButton.icon(
              onPressed: firstDoc != null
                  ? () {
                      context.push('/document/${firstDoc.id}?tab=1');
                    }
                  : null,
              icon: const Icon(Icons.auto_awesome_rounded),
              label: const Text('View Extracted Information'),
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.primaryAccent,
                side: BorderSide(color: theme.primaryAccent),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Button 3: Return to Dashboard
            FilledButton.tonalIcon(
              onPressed: () {
                context.go('/dashboard');
              },
              icon: const Icon(Icons.dashboard_rounded),
              label: const Text('Return to Dashboard'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
