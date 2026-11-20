import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/security/file_validator.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/masked_text_formatter.dart';
import '../../../core/widgets/error_dialog.dart';
import '../../../core/widgets/status_badge.dart';
import '../../authentication/presentation/auth_providers.dart';
import '../domain/document_file_model.dart';
import '../domain/document_model.dart';

class DocumentDetailsScreen extends ConsumerStatefulWidget {
  final String documentId;

  const DocumentDetailsScreen({super.key, required this.documentId});

  @override
  ConsumerState<DocumentDetailsScreen> createState() => _DocumentDetailsScreenState();
}

class _DocumentDetailsScreenState extends ConsumerState<DocumentDetailsScreen> {
  DocumentModel? _document;
  bool _isLoading = true;
  bool _revealDocumentNumber = false;
  Uint8List? _firstPagePreviewBytes;

  @override
  void initState() {
    super.initState();
    _loadDocument();
  }

  Future<void> _loadDocument() async {
    final session = ref.read(vaultSessionProvider);
    if (!session.isUnlocked || session.masterKey == null) {
      context.go('/pin-unlock');
      return;
    }

    try {
      final repo = ref.read(documentRepositoryProvider);
      final doc = await repo.getDocumentById(widget.documentId, session.masterKey!);
      if (mounted) {
        setState(() {
          _document = doc;
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
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ErrorDialog.show(context, title: 'Error', message: 'Failed to decrypt document details.');
      }
    }
  }

  Future<void> _toggleFavorite() async {
    if (_document == null) return;
    final repo = ref.read(documentRepositoryProvider);
    final newStatus = await repo.toggleFavorite(_document!.id, _document!.isFavorite);
    setState(() {
      _document = _document!.copyWith(isFavorite: newStatus);
    });
    ref.invalidate(favoriteDocumentsProvider);
    ref.invalidate(activeDocumentsProvider);
  }

  Future<void> _addPage() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      );
      if (files.isEmpty) return;
      final path = files.first.path;
      if (path == null) return;

      final file = File(path);
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
        originalFileName: files.first.name,
        mimeType: validation.mimeType,
        fileSize: validation.byteLength,
        createdAt: DateTime.now(),
      );

      await repo.addDocumentPageFile(documentId: widget.documentId, file: newFile);
      ref.invalidate(activeDocumentsProvider);
      _loadDocument();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Page added successfully.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ErrorDialog.show(context, title: 'Add Page Error', message: e.toString());
      }
    }
  }

  Future<void> _moveToTrash() async {
    final confirmed = await ErrorDialog.confirm(
      context,
      title: 'Move to Trash?',
      message: 'This document will be moved to Trash. You can restore it anytime or permanently delete it.',
      confirmLabel: 'Move to Trash',
      isDestructive: true,
    );

    if (confirmed && mounted) {
      final repo = ref.read(documentRepositoryProvider);
      await repo.moveToTrash(widget.documentId);
      ref.invalidate(activeDocumentsProvider);
      ref.invalidate(trashDocumentsProvider);
      if (mounted) {
        context.pop();
      }
    }
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
        body: Center(child: CircularProgressIndicator(color: colors.primaryAccent)),
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
        title: Text(doc.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: [
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
            onPressed: () => context.push(
              '/add-document',
              extra: {'editDocument': doc},
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Move to Trash',
            onPressed: _moveToTrash,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        children: [
          // 1. Preview Card
          _buildPreviewCard(doc, colors),
          const SizedBox(height: 18),

          // 2. Metadata Cards
          _buildMetadataCard(doc, colors),
          const SizedBox(height: 18),

          // 3. Document Files / Pages Section
          _buildFilesSection(doc, colors),
          const SizedBox(height: 30),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(
            top: BorderSide(
              color: colors.cardBorder,
            ),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _addPage,
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                label: const Text('Add Page'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  if (doc.files.isNotEmpty) {
                    _openViewer(doc.files.first);
                  }
                },
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: const Text('View Decrypted'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewCard(DocumentModel doc, AppThemeColors colors) {
    return Container(
      height: 180,
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
          const Text(
            'Document Information',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),

          // Document Number with Privacy Masking Toggle
          _buildDetailRow(
            label: 'Document Number',
            value: _revealDocumentNumber
                ? (doc.documentNumber ?? 'Not Provided')
                : MaskedTextFormatter.maskDocumentNumber(doc.documentNumber),
            colors: colors,
            actionWidget: doc.documentNumber != null
                ? IconButton(
                    icon: Icon(
                      _revealDocumentNumber ? Icons.visibility_off : Icons.visibility,
                      size: 20,
                      color: colors.primaryAccent,
                    ),
                    onPressed: () {
                      setState(() {
                        _revealDocumentNumber = !_revealDocumentNumber;
                      });
                    },
                  )
                : null,
          ),
          const Divider(height: 20),

          _buildDetailRow(
            label: 'Document Type',
            value: doc.documentType ?? 'General Document',
            colors: colors,
          ),
          const Divider(height: 20),

          _buildDetailRow(
            label: 'Owner / Name on Doc',
            value: doc.ownerName ?? 'Not Specified',
            colors: colors,
          ),
          const Divider(height: 20),

          _buildDetailRow(
            label: 'Issuing Authority',
            value: doc.issuingAuthority ?? 'Not Specified',
            colors: colors,
          ),
          const Divider(height: 20),

          _buildDetailRow(
            label: 'Issue Date',
            value: DateFormatter.formatDisplay(doc.issueDate),
            colors: colors,
          ),
          const Divider(height: 20),

          _buildDetailRow(
            label: 'Expiry Date',
            value: DateFormatter.formatDisplay(doc.expiryDate),
            valueColor: doc.expiryDate != null && DateFormatter.daysRemaining(doc.expiryDate!) <= 30
                ? colors.warning
                : null,
            colors: colors,
          ),
          if (doc.notes != null && doc.notes!.isNotEmpty) ...[
            const Divider(height: 20),
            _buildDetailRow(
              label: 'Secure Notes',
              value: doc.notes!,
              colors: colors,
            ),
          ],
          if (doc.tags.isNotEmpty) ...[
            const Divider(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 120,
                  child: Text(
                    'Tags',
                    style: TextStyle(color: colors.textSecondary, fontSize: 13),
                  ),
                ),
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: doc.tags.map((t) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: colors.primaryAccent.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '#$t',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: colors.primaryAccent,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ],
          const Divider(height: 20),
          _buildDetailRow(
            label: 'Date Added',
            value: DateFormatter.formatDateTimeDisplay(doc.createdAt),
            colors: colors,
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow({
    required String label,
    required String value,
    required AppThemeColors colors,
    Color? valueColor,
    Widget? actionWidget,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: valueColor ?? colors.textPrimary,
            ),
          ),
        ),
        if (actionWidget != null) actionWidget,
      ],
    );
  }

  Widget _buildFilesSection(DocumentModel doc, AppThemeColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Document Pages & Files (${doc.files.length})',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        ...doc.files.map((file) {
          final isPdf = file.mimeType == 'application/pdf';
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: colors.cardBackground,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.cardBorder),
            ),
            child: ListTile(
              onTap: () => _openViewer(file),
              leading: Icon(
                isPdf ? Icons.picture_as_pdf_outlined : Icons.image_outlined,
                color: colors.primaryAccent,
              ),
              title: Text(
                'Page ${file.pageNumber}: ${file.originalFileName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                '${(file.fileSize / 1024).toStringAsFixed(1)} KB • AES-256-GCM',
                style: TextStyle(
                  fontSize: 11.5,
                  color: colors.textTertiary,
                ),
              ),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
            ),
          );
        }),
      ],
    );
  }
}
