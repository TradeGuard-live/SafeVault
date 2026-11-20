import 'package:flutter/foundation.dart';
import 'package:tesseract_ocr/ocr_engine_config.dart';
import 'package:tesseract_ocr/tesseract_ocr.dart';
import 'ocr_extractor.dart';

class OfflineOcrService {
  /// Extracts text from an image file using bundled Tesseract models offline.
  /// Supported languages: 'eng' (English), 'hin' (Hindi), 'guj' (Gujarati)
  Future<String> recognizeText({
    required String imagePath,
    String language = 'eng',
  }) async {
    try {
      final text = await TesseractOcr.extractText(
        imagePath,
        config: OCRConfig(
          language: language,
        ),
      );
      return text;
    } catch (e) {
      debugPrint('OCR extraction error: $e');
      return '';
    }
  }

  /// Processes raw extracted text into structured document metadata suggestions.
  OcrExtractionResult parseMetadata(String ocrText) {
    return OcrExtractor.extract(ocrText);
  }
}

