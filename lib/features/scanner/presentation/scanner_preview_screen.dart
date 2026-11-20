import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../../core/theme/app_colors.dart';
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
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _pages = [];
    _loadPages();
  }

  Future<void> _loadPages() async {
    for (final path in widget.pagePaths) {
      final file = File(path);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        _pages.add(ScannerPage(
          originalPath: path,
          currentBytes: bytes,
        ));
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _applyRotation() async {
    if (_pages.isEmpty) return;
    setState(() => _isProcessing = true);

    final page = _pages[_currentPageIndex];
    page.rotationDegrees = (page.rotationDegrees + 90) % 360;

    final processed = await _scannerService.processImageBytes(
      await File(page.originalPath).readAsBytes(),
      rotationDegrees: page.rotationDegrees,
      filter: page.filter,
    );

    setState(() {
      page.currentBytes = processed;
      _isProcessing = false;
    });
  }

  Future<void> _applyFilter(ImageFilterType filter) async {
    if (_pages.isEmpty) return;
    setState(() => _isProcessing = true);

    final page = _pages[_currentPageIndex];
    page.filter = filter;

    final processed = await _scannerService.processImageBytes(
      await File(page.originalPath).readAsBytes(),
      rotationDegrees: page.rotationDegrees,
      filter: filter,
    );

    setState(() {
      page.currentBytes = processed;
      _isProcessing = false;
    });
  }

  Future<void> _runOcr() async {
    if (_pages.isEmpty) return;
    final page = _pages[_currentPageIndex];

    // Write current processed image to temp cache file for OCR
    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/ocr_${_uuid.v4()}.jpg');
    await tempFile.writeAsBytes(page.currentBytes);

    if (mounted) {
      context.push(
        '/ocr-review',
        extra: {
          'imagePath': tempFile.path,
          'allPageBytes': _pages.map((p) => p.currentBytes).toList(),
        },
      );
    }
  }

  Future<void> _saveAsPdf() async {
    if (_pages.isEmpty) return;
    setState(() => _isProcessing = true);

    try {
      final images = _pages.map((p) => p.currentBytes).toList();
      final pdfBytes = await _scannerService.compileToPdf(images);

      final tempDir = await getTemporaryDirectory();
      final pdfFile = File('${tempDir.path}/scan_${_uuid.v4()}.pdf');
      await pdfFile.writeAsBytes(pdfBytes);

      setState(() => _isProcessing = false);

      if (mounted) {
        context.push(
          '/add-document',
          extra: {
            'initialFilePath': pdfFile.path,
            'mimeType': 'application/pdf',
            'initialFileName': 'Scanned Document.pdf',
          },
        );
      }
    } catch (e) {
      setState(() => _isProcessing = false);
      if (mounted) {
        ErrorDialog.show(context, title: 'PDF Compilation Error', message: e.toString());
      }
    }
  }

  Future<void> _saveAsImages() async {
    if (_pages.isEmpty) return;
    setState(() => _isProcessing = true);

    try {
      final tempDir = await getTemporaryDirectory();
      final page = _pages.first;
      final imgFile = File('${tempDir.path}/scan_${_uuid.v4()}.jpg');
      await imgFile.writeAsBytes(page.currentBytes);

      setState(() => _isProcessing = false);

      if (mounted) {
        context.push(
          '/add-document',
          extra: {
            'initialFilePath': imgFile.path,
            'mimeType': 'image/jpeg',
            'initialFileName': 'Scanned Image.jpg',
          },
        );
      }
    } catch (e) {
      setState(() => _isProcessing = false);
      if (mounted) {
        ErrorDialog.show(context, title: 'Image Export Error', message: e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_pages.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Review Scans')),
        body: const Center(child: CircularProgressIndicator(color: AppColors.primaryTeal)),
      );
    }

    final currentPage = _pages[_currentPageIndex];

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.lightBackground,
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
            onPressed: _runOcr,
          ),
          if (_pages.length > 1)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: 'Delete Page',
              onPressed: () {
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
                    ? const CircularProgressIndicator(color: AppColors.primaryTeal)
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
                    _buildFilterChip('Original', ImageFilterType.original, currentPage.filter),
                    const SizedBox(width: 8),
                    _buildFilterChip('Grayscale', ImageFilterType.grayscale, currentPage.filter),
                    const SizedBox(width: 8),
                    _buildFilterChip('High Contrast', ImageFilterType.highContrast, currentPage.filter),
                    const SizedBox(width: 8),
                    _buildFilterChip('B&W Doc', ImageFilterType.documentBw, currentPage.filter),
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
                          color: isCurrent ? AppColors.primaryTeal : AppColors.darkTextTertiary,
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
                color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                border: Border(
                  top: BorderSide(
                    color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _runOcr,
                      icon: const Icon(Icons.manage_search_rounded, size: 18),
                      label: const Text('Extract OCR'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _saveAsPdf,
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                      label: Text(_pages.length > 1 ? 'Save as PDF (${_pages.length}p)' : 'Save as PDF'),
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

  Widget _buildFilterChip(String label, ImageFilterType type, ImageFilterType activeType) {
    final isSelected = type == activeType;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => _applyFilter(type),
      backgroundColor: isDark ? AppColors.darkCard : AppColors.lightCardElevated,
      selectedColor: AppColors.primaryTeal.withOpacity(0.2),
      labelStyle: TextStyle(
        color: isSelected
            ? AppColors.primaryTeal
            : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isSelected ? AppColors.primaryTeal : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
        ),
      ),
    );
  }
}

