import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdfx/pdfx.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../../core/widgets/error_dialog.dart';
import '../../authentication/presentation/auth_providers.dart';

class DocumentViewerScreen extends ConsumerStatefulWidget {
  final String documentName;
  final String encryptedFilePath;
  final String mimeType;
  final String fileName;

  const DocumentViewerScreen({
    super.key,
    required this.documentName,
    required this.encryptedFilePath,
    required this.mimeType,
    required this.fileName,
  });

  @override
  ConsumerState<DocumentViewerScreen> createState() =>
      _DocumentViewerScreenState();
}

class _DocumentViewerScreenState extends ConsumerState<DocumentViewerScreen> {
  Uint8List? _decryptedBytes;
  PdfDocument? _pdfDocument;
  PdfController? _pdfController;
  int _pdfTotalPages = 0;
  int _pdfCurrentPage = 1;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _decryptAndLoad();
  }

  @override
  void dispose() {
    _pdfController?.dispose();
    _pdfDocument?.close();
    // Wipe ephemeral memory buffer
    if (_decryptedBytes != null) {
      _decryptedBytes!.fillRange(0, _decryptedBytes!.length, 0);
      _decryptedBytes = null;
    }
    // Clean up any ephemeral temp files
    ref.read(storageServiceProvider).wipeEphemeralFiles();
    super.dispose();
  }

  Future<void> _decryptAndLoad() async {
    final session = ref.read(vaultSessionProvider);
    if (!session.isUnlocked || session.masterKey == null) {
      if (mounted) context.go('/pin-unlock');
      return;
    }

    Uint8List? bytes;
    try {
      final storage = ref.read(storageServiceProvider);
      if (widget.encryptedFilePath.isEmpty) {
        throw Exception('No encrypted file path provided.');
      }
      bytes = await storage.readDecryptedFile(
        filePath: widget.encryptedFilePath,
        masterKey: session.getMasterKeyOrThrow(),
      );

      if (bytes.isEmpty) {
        throw Exception('Decrypted file is empty.');
      }

      if (widget.mimeType == 'application/pdf') {
        final pdf = await PdfDocument.openData(bytes);
        // Reuse the same PdfDocument instance instead of opening it twice.
        final controller = PdfController(document: Future.value(pdf));

        if (!mounted) {
          // Loading completed after disposal: close resources.
          controller.dispose();
          pdf.close();
          bytes.fillRange(0, bytes.length, 0);
          return;
        }
        setState(() {
          _decryptedBytes = bytes;
          _pdfDocument = pdf;
          _pdfController = controller;
          _pdfTotalPages = pdf.pagesCount;
          _isLoading = false;
        });
      } else {
        if (!mounted) {
          bytes.fillRange(0, bytes.length, 0);
          return;
        }
        setState(() {
          _decryptedBytes = bytes;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (bytes != null) {
        try {
          bytes.fillRange(0, bytes.length, 0);
        } catch (_) {}
      }
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage =
              'Decryption failed: Data may be corrupted or tampered.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.documentName,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            Text(
              widget.fileName,
              style: const TextStyle(fontSize: 11, color: Colors.white60),
            ),
          ],
        ),
        actions: [
          if (_pdfTotalPages > 0)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$_pdfCurrentPage / $_pdfTotalPages',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: colors.primaryAccent),
                    const SizedBox(height: 16),
                    const Text(
                      'Decrypting Document in Memory...',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              )
            : _errorMessage != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.lock_clock_outlined,
                        size: 48,
                        color: colors.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : widget.mimeType == 'application/pdf' && _pdfController != null
            ? PdfView(
                controller: _pdfController!,
                onPageChanged: (page) {
                  setState(() => _pdfCurrentPage = page);
                },
              )
            : InteractiveViewer(
                panEnabled: true,
                minScale: 0.8,
                maxScale: 4.0,
                child: Center(
                  child: Image.memory(_decryptedBytes!, fit: BoxFit.contain),
                ),
              ),
      ),
    );
  }
}
