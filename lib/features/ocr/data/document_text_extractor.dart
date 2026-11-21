import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart' as pfx;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:uuid/uuid.dart';

import 'document_field_extractor.dart';
import 'offline_ocr_service.dart';
import 'smart_document_classifier.dart';

class ExtractionPipelineResult {
  final String fullText;
  final int pageCount;
  final Map<int, String> pageTexts;
  final String extractionEngine;
  final String language;
  final bool hasSearchableText;
  final bool wasPasswordProtected;
  final ClassifiedDocumentInfo classification;
  final List<RawExtractedField> fields;

  const ExtractionPipelineResult({
    required this.fullText,
    required this.pageCount,
    required this.pageTexts,
    required this.extractionEngine,
    required this.language,
    required this.hasSearchableText,
    this.wasPasswordProtected = false,
    required this.classification,
    required this.fields,
  });
}

/// Core offline text extraction engine for PDFs and images.
/// Combines native searchable PDF parsing with bundled offline Tesseract OCR.
class DocumentTextExtractor {
  final OfflineOcrService _ocrService;
  final Uuid _uuid = const Uuid();

  DocumentTextExtractor({OfflineOcrService? ocrService})
    : _ocrService = ocrService ?? OfflineOcrService();

  /// Automatically processes imported or scanned document bytes.
  Future<ExtractionPipelineResult> processDocumentBytes({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
    String? password,
    String language = 'eng',
  }) async {
    final isPdf =
        mimeType.contains('pdf') || fileName.toLowerCase().endsWith('.pdf');

    if (isPdf) {
      return await _processPdf(
        bytes: bytes,
        fileName: fileName,
        password: password,
        language: language,
      );
    } else {
      return await _processImage(
        bytes: bytes,
        fileName: fileName,
        language: language,
      );
    }
  }

  // =========================================================================
  // PDF PROCESSING (SEARCHABLE + SCANNED HYBRID)
  // =========================================================================
  Future<ExtractionPipelineResult> _processPdf({
    required Uint8List bytes,
    required String fileName,
    String? password,
    required String language,
  }) async {
    final Map<int, String> pageTexts = {};
    int pageCount = 1;
    bool hasSearchable = false;
    bool wasEncrypted = false;
    bool usedOcr = false;

    PdfDocument? pdfDoc;
    try {
      if (password != null && password.isNotEmpty) {
        pdfDoc = PdfDocument(inputBytes: bytes, password: password);
        wasEncrypted = true;
      } else {
        try {
          pdfDoc = PdfDocument(inputBytes: bytes);
        } catch (e) {
          if (e.toString().toLowerCase().contains('password') ||
              e.toString().toLowerCase().contains('encrypted')) {
            wasEncrypted = true;
            rethrow;
          }
          pdfDoc = null;
        }
      }

      if (pdfDoc != null) {
        pageCount = pdfDoc.pages.count;
        final extractor = PdfTextExtractor(pdfDoc);

        for (int i = 0; i < pageCount; i++) {
          final pageNum = i + 1;
          try {
            final pageText = extractor.extractText(
              startPageIndex: i,
              endPageIndex: i,
            );
            if (pageText.trim().length > 15) {
              pageTexts[pageNum] = pageText.trim();
              hasSearchable = true;
            }
          } catch (_) {}
        }
        pdfDoc.dispose();
      }
    } catch (e) {
      debugPrint('Syncfusion PDF extraction note: $e');
    }

    // If any pages are scanned or image-based, fallback to rendering & OCR
    final tempDir = await getTemporaryDirectory();
    final tempPdfPath = '${tempDir.path}/temp_ocr_${_uuid.v4()}.pdf';
    final tempPdfFile = File(tempPdfPath);

    try {
      if (pageTexts.length < pageCount || !hasSearchable) {
        await tempPdfFile.writeAsBytes(bytes, flush: true);
        final pdfxDoc = await pfx.PdfDocument.openFile(tempPdfPath);
        pageCount = pdfxDoc.pagesCount;

        for (int i = 1; i <= pageCount; i++) {
          if (pageTexts.containsKey(i) && pageTexts[i]!.length > 30) {
            continue; // Already has searchable text
          }

          try {
            final page = await pdfxDoc.getPage(i);
            final pageImage = await page.render(
              width: page.width * 2,
              height: page.height * 2,
              format: pfx.PdfPageImageFormat.png,
            );
            await page.close();

            if (pageImage != null && pageImage.bytes.isNotEmpty) {
              final renderedPath = '${tempDir.path}/ocr_page_${_uuid.v4()}.png';
              final renderedFile = File(renderedPath);
              await renderedFile.writeAsBytes(pageImage.bytes, flush: true);

              final ocrText = await _ocrService.recognizeText(
                imagePath: renderedPath,
                language: language,
              );

              // Securely clean up rendered page image
              if (await renderedFile.exists()) {
                await renderedFile.delete();
              }

              if (ocrText.trim().isNotEmpty) {
                pageTexts[i] = ocrText.trim();
                usedOcr = true;
              }
            }
          } catch (e) {
            debugPrint('Failed to OCR PDF page $i: $e');
          }
        }
        await pdfxDoc.close();
      }
    } catch (e) {
      debugPrint('PDF rendering fallback error: $e');
    } finally {
      if (await tempPdfFile.exists()) {
        await tempPdfFile.delete();
      }
    }

    // Assemble complete text in page order
    final buffer = StringBuffer();
    final sortedPages = pageTexts.keys.toList()..sort();
    for (final page in sortedPages) {
      if (sortedPages.length > 1) {
        buffer.writeln('--- PAGE $page ---');
      }
      buffer.writeln(pageTexts[page]);
      buffer.writeln();
    }

    final fullText = buffer.toString().trim();
    final engine = hasSearchable && usedOcr
        ? 'Hybrid (Searchable PDF + Tesseract OCR)'
        : hasSearchable
        ? 'Searchable PDF Engine'
        : 'Tesseract OCR (Offline)';

    final classification = SmartDocumentClassifier.classify(
      fullText,
      originalFileName: fileName,
    );
    final fields = DocumentFieldExtractor.extractFields(
      fullText: fullText,
      documentType: classification.documentType,
      pageCount: pageCount,
    );

    return ExtractionPipelineResult(
      fullText: fullText,
      pageCount: pageCount,
      pageTexts: pageTexts,
      extractionEngine: engine,
      language: language,
      hasSearchableText: hasSearchable,
      wasPasswordProtected: wasEncrypted,
      classification: classification,
      fields: fields,
    );
  }

  // =========================================================================
  // IMAGE PROCESSING (ROTATION, CONTRAST, OCR)
  // =========================================================================
  Future<ExtractionPipelineResult> _processImage({
    required Uint8List bytes,
    required String fileName,
    required String language,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final tempImagePath = '${tempDir.path}/ocr_img_${_uuid.v4()}.jpg';
    final tempImageFile = File(tempImagePath);

    String ocrText = '';
    try {
      // Decode image to check EXIF rotation and optimize contrast for OCR
      final decoded = img.decodeImage(bytes);
      if (decoded != null) {
        // Fix orientation based on EXIF
        final oriented = img.bakeOrientation(decoded);
        // Save optimized copy strictly for OCR processing
        final processedJpg = img.encodeJpg(oriented, quality: 90);
        await tempImageFile.writeAsBytes(processedJpg, flush: true);
      } else {
        await tempImageFile.writeAsBytes(bytes, flush: true);
      }

      ocrText = await _ocrService.recognizeText(
        imagePath: tempImagePath,
        language: language,
      );
    } catch (e) {
      debugPrint('Image OCR processing error: $e');
    } finally {
      if (await tempImageFile.exists()) {
        await tempImageFile.delete();
      }
    }

    final classification = SmartDocumentClassifier.classify(
      ocrText,
      originalFileName: fileName,
    );
    final fields = DocumentFieldExtractor.extractFields(
      fullText: ocrText,
      documentType: classification.documentType,
      pageCount: 1,
    );

    return ExtractionPipelineResult(
      fullText: ocrText.trim(),
      pageCount: 1,
      pageTexts: {1: ocrText.trim()},
      extractionEngine: 'Tesseract OCR (Offline)',
      language: language,
      hasSearchableText: false,
      wasPasswordProtected: false,
      classification: classification,
      fields: fields,
    );
  }

  // =========================================================================
  // HUMAN-READABLE EXTRACTED TXT FILE GENERATOR
  // =========================================================================
  static String generateFormattedTextRecord({
    required String documentType,
    required String categoryName,
    required String sourceFileName,
    required String fullText,
    required List<RawExtractedField> fields,
    required String engine,
    required String language,
    int pageCount = 1,
    DateTime? extractionDate,
  }) {
    final buffer = StringBuffer();
    final dateStr = (extractionDate ?? DateTime.now()).toIso8601String();

    buffer.writeln('DOCUMENT: $documentType');
    buffer.writeln('DOCUMENT CATEGORY: $categoryName');
    buffer.writeln('EXTRACTION DATE: $dateStr');
    buffer.writeln('SOURCE FILE: $sourceFileName');
    buffer.writeln('TOTAL PAGES: $pageCount');
    buffer.writeln();

    if (fields.isNotEmpty) {
      buffer.writeln('STRUCTURED INFORMATION');
      for (final field in fields) {
        buffer.writeln(
          '${field.fieldName}: ${field.value} (Confidence: ${field.confidenceCategory})',
        );
      }
      buffer.writeln();
    }

    buffer.writeln('--------------------------------');
    buffer.writeln('FULL EXTRACTED TEXT');
    buffer.writeln('--------------------------------');
    buffer.writeln(
      fullText.isEmpty ? '[No text detected in document]' : fullText,
    );
    buffer.writeln();

    buffer.writeln('--------------------------------');
    buffer.writeln('EXTRACTION STATUS');
    buffer.writeln('--------------------------------');
    final unverifiedCount = fields
        .where((f) => f.confidenceCategory != 'High')
        .length;
    buffer.writeln('Fields requiring verification: $unverifiedCount');
    buffer.writeln('Extraction engine: $engine');
    buffer.writeln('Language: $language');

    return buffer.toString();
  }
}
