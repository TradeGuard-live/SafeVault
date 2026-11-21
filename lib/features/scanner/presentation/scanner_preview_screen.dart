import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../../core/widgets/error_dialog.dart';
import '../data/scanner_service.dart';

class ScannerPreviewScreen extends StatefulWidget {
  final List<String> pagePaths;

  const ScannerPreviewScreen({super.key, required this.pagePaths});

  @override
  State<ScannerPreviewScreen> createState() => _ScannerPreviewScreenState();
}

class _ScannerPreviewScreenState extends State<ScannerPreviewScreen> {
  final ScannerService _scannerService = ScannerService();
  final Uuid _uuid = const Uuid();

  late List<ScannerPage> _pages;
  int _currentPageIndex = 0;
  bool _isLoadingPages = true;
  bool _isProcessing = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _pages = [];
    _loadPages();
  }

  Future<void> _loadPages() async {
    try {
      final pages = <ScannerPage>[];
      for (final path in widget.pagePaths) {
        final file = File(path);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          if (bytes.isNotEmpty) {
            pages.add(ScannerPage(originalPath: path, currentBytes: bytes));
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _pages = pages;
        _isLoadingPages = false;
        _loadError = pages.isEmpty
            ? 'The selected scan files are unavailable or empty.'
            : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingPages = false;
        _loadError = 'Unable to load the selected scan files.';
      });
    }
  }

  void _showProcessingError(String title, Object error) {
    if (!mounted) return;
    setState(() => _isProcessing = false);
    ErrorDialog.show(context, title: title, message: error.toString());
  }

  Future<void> _applyRotation() async {
    if (_pages.isEmpty || _isProcessing) return;
    final page = _pages[_currentPageIndex];
    final nextRotation = (page.rotationDegrees + 90) % 360;
    setState(() => _isProcessing = true);

    try {
      final processed = await _scannerService.processImageBytes(
        await File(page.originalPath).readAsBytes(),
        rotationDegrees: nextRotation,
        filter: page.filter,
      );

      if (!mounted) return;
      setState(() {
        page.rotationDegrees = nextRotation;
        page.currentBytes = processed;
        _isProcessing = false;
      });
    } catch (error) {
      _showProcessingError('Image Rotation Error', error);
    }
  }

  Future<void> _applyFilter(ImageFilterType filter) async {
    if (_pages.isEmpty || _isProcessing) return;
    final page = _pages[_currentPageIndex];
    setState(() => _isProcessing = true);

    try {
      final processed = await _scannerService.processImageBytes(
        await File(page.originalPath).readAsBytes(),
        rotationDegrees: page.rotationDegrees,
        filter: filter,
      );

      if (!mounted) return;
      setState(() {
        page.filter = filter;
        page.currentBytes = processed;
        _isProcessing = false;
      });
    } catch (error) {
      _showProcessingError('Image Filter Error', error);
    }
  }

  Future<void> _runOcr() async {
    if (_pages.isEmpty || _isProcessing) return;
    final page = _pages[_currentPageIndex];
    setState(() => _isProcessing = true);

    try {
      // Write current processed image to temp cache file for OCR.
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/ocr_${_uuid.v4()}.jpg');
      await tempFile.writeAsBytes(page.currentBytes);

      if (!mounted) return;
      setState(() => _isProcessing = false);
      context.push(
        '/ocr-review',
        extra: {
          'imagePath': tempFile.path,
          'allPageBytes': _pages.map((p) => p.currentBytes).toList(),
        },
      );
    } catch (error) {
      _showProcessingError('OCR Preparation Error', error);
    }
  }

  Future<void> _saveAsPdf() async {
    if (_pages.isEmpty || _isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      final images = _pages.map((p) => p.currentBytes).toList();
      final pdfBytes = await _scannerService.compileToPdf(images);

      final tempDir = await getTemporaryDirectory();
      final pdfFile = File('${tempDir.path}/scan_${_uuid.v4()}.pdf');
      await pdfFile.writeAsBytes(pdfBytes);

      if (!mounted) return;
      setState(() => _isProcessing = false);
      context.push(
        '/add-document',
        extra: {
          'initialFilePath': pdfFile.path,
          'mimeType': 'application/pdf',
          'initialFileName': 'Scanned Document.pdf',
        },
      );
    } catch (error) {
      _showProcessingError('PDF Compilation Error', error);
    }
  }

  Future<void> _saveAsImages() async {
    if (_pages.isEmpty || _isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      final tempDir = await getTemporaryDirectory();
      final page = _pages.first;
      final imgFile = File('${tempDir.path}/scan_${_uuid.v4()}.jpg');
      await imgFile.writeAsBytes(page.currentBytes);

      if (!mounted) return;
      setState(() => _isProcessing = false);
      context.push(
        '/add-document',
        extra: {
          'initialFilePath': imgFile.path,
          'mimeType': 'image/jpeg',
          'initialFileName': 'Scanned Image.jpg',
        },
      );
    } catch (error) {
      _showProcessingError('Image Export Error', error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;

    if (_isLoadingPages) {
      return Scaffold(
        appBar: AppBar(title: const Text('Review Scans')),
        body: Center(
          child: CircularProgressIndicator(color: colors.primaryAccent),
        ),
      );
    }

    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Review Scans')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  color: colors.error,
                  size: 48,
                ),
                const SizedBox(height: 12),
                Text(_loadError!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () => context.pop(),
                  child: const Text('Back to Scanner'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final currentPage = _pages[_currentPageIndex];

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text(
          'Page ${_currentPageIndex + 1} of ${_pages.length}',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.rotate_right_rounded),
            tooltip: 'Rotate 90°',
            onPressed: _isProcessing ? null : _applyRotation,
          ),
          IconButton(
            icon: const Icon(Icons.document_scanner_outlined),
            tooltip: 'Run Offline OCR',
            onPressed: _isProcessing ? null : _runOcr,
          ),
          if (_pages.length > 1)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: 'Delete Page',
              onPressed: _isProcessing
                  ? null
                  : () {
                setState(() {
                  _pages.removeAt(_currentPageIndex);
                  if (_currentPageIndex >= _pages.length) {
                    _currentPageIndex = _pages.length - 1;
                  }
                });
              },
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Current Page Image Preview
            Expanded(
              child: Center(
                child: _isProcessing
                    ? CircularProgressIndicator(color: colors.primaryAccent)
                    : Container(
                        margin: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.15),
                              blurRadius: 14,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.memory(
                            currentPage.currentBytes,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
              ),
            ),

            // Filter Selector Chips
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterChip(
                      'Original',
                      ImageFilterType.original,
                      currentPage.filter,
                      colors,
                    ),
                    const SizedBox(width: 8),
                    _buildFilterChip(
                      'Grayscale',
                      ImageFilterType.grayscale,
                      currentPage.filter,
                      colors,
                    ),
                    const SizedBox(width: 8),
                    _buildFilterChip(
                      'High Contrast',
                      ImageFilterType.highContrast,
                      currentPage.filter,
                      colors,
                    ),
                    const SizedBox(width: 8),
                    _buildFilterChip(
                      'B&W Doc',
                      ImageFilterType.documentBw,
                      currentPage.filter,
                      colors,
                    ),
                  ],
                ),
              ),
            ),

            // Multi-page navigation dots / thumbnails
            if (_pages.length > 1)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_pages.length, (i) {
                    final isCurrent = i == _currentPageIndex;
                    return GestureDetector(
                      onTap: () => setState(() => _currentPageIndex = i),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: isCurrent ? 12 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          color: isCurrent
                              ? colors.primaryAccent
                              : colors.textTertiary,
                        ),
                      ),
                    );
                  }),
                ),
              ),

            // Bottom Save Actions
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.surface,
                border: Border(top: BorderSide(color: colors.cardBorder)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isProcessing ? null : _runOcr,
                      icon: const Icon(Icons.manage_search_rounded, size: 18),
                      label: const Text('Extract OCR'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isProcessing ? null : _saveAsPdf,
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                      label: Text(
                        _pages.length > 1
                            ? 'Save as PDF (${_pages.length}p)'
                            : 'Save as PDF',
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

  Widget _buildFilterChip(
    String label,
    ImageFilterType type,
    ImageFilterType activeType,
    AppThemeColors colors,
  ) {
    final isSelected = type == activeType;

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: _isProcessing ? null : (_) => _applyFilter(type),
      backgroundColor: colors.cardBackground,
      selectedColor: colors.primaryAccent.withOpacity(0.2),
      labelStyle: TextStyle(
        color: isSelected ? colors.primaryAccent : colors.textSecondary,
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isSelected ? colors.primaryAccent : colors.cardBorder,
        ),
      ),
    );
  }
}
