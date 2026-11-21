import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/security/authentication_gate.dart';
import '../../../core/security/clipboard_security_service.dart';
import '../../../core/security/two_factor_auth_coordinator.dart';
import '../../../core/services/native_saf_and_share_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../../core/widgets/error_dialog.dart';
import '../../authentication/presentation/auth_providers.dart';
import '../../authentication/presentation/two_factor_verification_dialog.dart';
import '../domain/document_model.dart';

class DocumentShareSheet extends ConsumerStatefulWidget {
  final DocumentModel document;
  final String? extractedText;

  const DocumentShareSheet({
    super.key,
    required this.document,
    this.extractedText,
  });

  static Future<void> show(
    BuildContext context, {
    required DocumentModel document,
    String? extractedText,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) =>
          DocumentShareSheet(document: document, extractedText: extractedText),
    );
  }

  @override
  ConsumerState<DocumentShareSheet> createState() => _DocumentShareSheetState();
}

class _DocumentShareSheetState extends ConsumerState<DocumentShareSheet> {
  bool _isProcessing = false;
  final Uuid _uuid = const Uuid();

  Future<bool> _authenticateForExport(String actionTitle) async {
    final gate = ref.read(authenticationGateProvider);
    return await gate.authenticateForAction(
      context,
      action: PendingVaultAction(
        type: VaultActionType.shareDocument,
        targetId: widget.document.id,
        targetName: widget.document.name,
        returnRoute: '/document/${widget.document.id}',
        params: {'action': actionTitle},
      ),
      title: 'Authorize Export',
      reason:
          'Biometric + PIN verification required before decrypting files for export: $actionTitle',
    );
  }

  Future<String> _decryptFileToSharedCache(
    String encryptedPath,
    String originalName,
  ) async {
    final session = ref.read(vaultSessionProvider);
    final storage = ref.read(storageServiceProvider);
    final cacheDir = await getTemporaryDirectory();
    final sharedDir = Directory('${cacheDir.path}/shared_exports');
    if (!sharedDir.existsSync()) {
      sharedDir.createSync(recursive: true);
    }

    final ext = originalName.contains('.')
        ? originalName.split('.').last
        : 'dat';
    final randomName = 'export_${_uuid.v4()}.$ext';
    final exportFile = File('${sharedDir.path}/$randomName');

    final decryptedBytes = await storage.readDecryptedFile(
      filePath: encryptedPath,
      masterKey: session.masterKey!,
    );
    await exportFile.writeAsBytes(decryptedBytes, flush: true);
    return exportFile.path;
  }

  Future<String> _writeTextToSharedCache(
    String textContent,
    String baseName,
  ) async {
    final cacheDir = await getTemporaryDirectory();
    final sharedDir = Directory('${cacheDir.path}/shared_exports');
    if (!sharedDir.existsSync()) {
      sharedDir.createSync(recursive: true);
    }
    final randomName = 'export_${_uuid.v4()}.txt';
    final exportFile = File('${sharedDir.path}/$randomName');
    await exportFile.writeAsString(textContent, flush: true);
    return exportFile.path;
  }

  Future<void> _shareOriginal() async {
    if (widget.document.files.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No attached files found in document.')),
        );
      }
      return;
    }

    final authenticated = await _authenticateForExport(
      'Share Original Document',
    );
    if (!authenticated || !mounted) return;

    setState(() => _isProcessing = true);
    try {
      final decryptedPaths = <String>[];
      final mimeTypes = <String>[];

      for (final file in widget.document.files) {
        final path = await _decryptFileToSharedCache(
          file.encryptedFilePath,
          file.originalFileName,
        );
        decryptedPaths.add(path);
        mimeTypes.add(file.mimeType);
      }

      if (mounted) Navigator.pop(context);
      await NativeSafAndShareService.instance.shareFiles(
        filePaths: decryptedPaths,
        mimeTypes: mimeTypes,
        title: 'Share ${widget.document.name}',
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ErrorDialog.show(
          context,
          title: 'Export Failed',
          message: e.toString(),
        );
      }
    }
  }

  Future<void> _shareExtractedTxtFile() async {
    final text = widget.extractedText;
    if (text == null || text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No extracted text available to share.'),
          ),
        );
      }
      return;
    }

    final authenticated = await _authenticateForExport('Share Extracted Text');
    if (!authenticated || !mounted) return;

    setState(() => _isProcessing = true);
    try {
      final txtPath = await _writeTextToSharedCache(text, widget.document.name);
      if (mounted) Navigator.pop(context);
      await NativeSafAndShareService.instance.shareFiles(
        filePaths: [txtPath],
        mimeTypes: ['text/plain'],
        title: 'Share Extracted Text',
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ErrorDialog.show(
          context,
          title: 'Export Failed',
          message: e.toString(),
        );
      }
    }
  }

  Future<void> _shareStructuredFields() async {
    final extraction = widget.document.extraction;
    if (extraction == null || extraction.fields.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No structured information available to share.'),
          ),
        );
      }
      return;
    }

    final authenticated = await _authenticateForExport(
      'Share Structured Information',
    );
    if (!authenticated || !mounted) return;

    setState(() => _isProcessing = true);
    try {
      final buffer = StringBuffer();
      buffer.writeln('VAULT DOCUMENT SUMMARY: ${widget.document.name}');
      buffer.writeln(
        'Category: ${widget.document.documentType ?? widget.document.categoryId}',
      );
      buffer.writeln('--------------------------------');
      for (final f in extraction.fields) {
        buffer.writeln('${f.fieldName}: ${f.plainValue ?? f.encryptedValue}');
      }
      buffer.writeln('--------------------------------');
      buffer.writeln('Exported securely from Vault');

      if (mounted) Navigator.pop(context);
      await NativeSafAndShareService.instance.shareText(
        text: buffer.toString(),
        title: 'Document Information: ${widget.document.name}',
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ErrorDialog.show(context, title: 'Share Failed', message: e.toString());
      }
    }
  }

  Future<void> _shareBothOriginalAndText() async {
    if (widget.document.files.isEmpty) {
      await _shareExtractedTxtFile();
      return;
    }

    final authenticated = await _authenticateForExport(
      'Share Original & Extracted Text',
    );
    if (!authenticated || !mounted) return;

    setState(() => _isProcessing = true);
    try {
      final decryptedPaths = <String>[];
      final mimeTypes = <String>[];

      for (final file in widget.document.files) {
        final path = await _decryptFileToSharedCache(
          file.encryptedFilePath,
          file.originalFileName,
        );
        decryptedPaths.add(path);
        mimeTypes.add(file.mimeType);
      }

      if (widget.extractedText != null &&
          widget.extractedText!.trim().isNotEmpty) {
        final txtPath = await _writeTextToSharedCache(
          widget.extractedText!,
          widget.document.name,
        );
        decryptedPaths.add(txtPath);
        mimeTypes.add('text/plain');
      }

      if (mounted) Navigator.pop(context);
      await NativeSafAndShareService.instance.shareFiles(
        filePaths: decryptedPaths,
        mimeTypes: mimeTypes,
        title: 'Share ${widget.document.name} & Text',
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ErrorDialog.show(
          context,
          title: 'Export Failed',
          message: e.toString(),
        );
      }
    }
  }

  Future<void> _saveExtractedTextViaSaf() async {
    final text = widget.extractedText;
    if (text == null || text.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No extracted text available to save.')),
        );
      }
      return;
    }

    final authenticated = await _authenticateForExport(
      'Save Extracted Text via SAF',
    );
    if (!authenticated || !mounted) return;

    // Sanitize default filename
    final safeName = widget.document.name
        .replaceAll(RegExp(r'[^\w\s-]'), '_')
        .replaceAll(' ', '_');
    final defaultFileName = '${safeName}_extracted.txt';

    if (mounted) Navigator.pop(context);
    final saved = await NativeSafAndShareService.instance.createAndSaveDocument(
      defaultFileName: defaultFileName,
      content: text,
      mimeType: 'text/plain',
    );

    if (mounted) {
      if (saved) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved $defaultFileName to storage.'),
            backgroundColor: AppColors.primaryTeal,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Save cancelled or not supported.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.themeColors;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: theme.cardBorder),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.textSecondary.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.primaryAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.share_rounded,
                    color: theme.primaryAccent,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Share Document',
                        style: TextStyle(
                          color: theme.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.document.name,
                        style: TextStyle(
                          color: theme.textSecondary,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.surfaceElevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.cardBorder),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.shield_outlined,
                    color: theme.primaryAccent,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Outgoing sharing creates a temporary decrypted file outside Vault. 2FA is required.',
                      style: TextStyle(
                        color: theme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_isProcessing)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: CircularProgressIndicator(),
                ),
              )
            else ...[
              _buildOptionTile(
                theme: theme,
                icon: Icons.file_present_rounded,
                title: 'Share Original Document',
                subtitle: 'Share PDF or original photos directly via WhatsApp, Gmail, etc.',
                onTap: _shareOriginal,
              ),
              _buildOptionTile(
                theme: theme,
                icon: Icons.description_rounded,
                title: 'Share Extracted Text (.txt)',
                subtitle: 'Share the generated plain-text document as a file attachment',
                onTap: _shareExtractedTxtFile,
              ),
              _buildOptionTile(
                theme: theme,
                icon: Icons.format_list_bulleted_rounded,
                title: 'Share Selected Information',
                subtitle:
                    'Share formatted structured fields as plain text message',
                onTap: _shareStructuredFields,
              ),
              _buildOptionTile(
                theme: theme,
                icon: Icons.all_inclusive_rounded,
                title: 'Share Both Original & Extracted Text',
                subtitle: 'Send original document file along with its companion .txt record',
                onTap: _shareBothOriginalAndText,
              ),
              const Divider(height: 24),
              _buildOptionTile(
                theme: theme,
                icon: Icons.save_alt_rounded,
                title: 'Save Extracted Text to Device',
                subtitle: 'Export .txt file to Downloads/Storage using native file picker',
                isHighlighted: true,
                onTap: _saveExtractedTextViaSaf,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOptionTile({
    required AppThemeColors theme,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isHighlighted = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isHighlighted
                ? theme.primaryAccent.withValues(alpha: 0.1)
                : theme.surfaceElevated,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isHighlighted
                  ? theme.primaryAccent.withValues(alpha: 0.3)
                  : theme.cardBorder,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isHighlighted
                      ? theme.primaryAccent.withValues(alpha: 0.2)
                      : theme.surface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: isHighlighted
                      ? theme.primaryAccent
                      : theme.textPrimary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: theme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: theme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: theme.textSecondary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
