import 'package:flutter/foundation.dart';
import 'package:tesseract_ocr/ocr_engine_config.dart';
import 'package:tesseract_ocr/tesseract_ocr.dart';
import 'ocr_extractor.dart';

class OfflineOcrService {
  /// Bundled, 100% offline languages supported in Vault:
  /// - 'eng': English Latin script
  /// - 'hin': Hindi Devanagari script
  /// - 'guj': Gujarati script
  static const List<String> supportedLanguages = ['eng', 'hin', 'guj'];

  static bool isLanguageSupported(String lang) => supportedLanguages.contains(lang.toLowerCase());

  /// Extracts text from an image file using bundled Tesseract models offline.
  /// Supported languages: 'eng' (English), 'hin' (Hindi), 'guj' (Gujarati)
  Future<String> recognizeText({
    required String imagePath,
    String language = 'eng',
  }) async {
    final effectiveLang = isLanguageSupported(language) ? language.toLowerCase() : 'eng';

    try {
      final text = await TesseractOcr.extractText(
        imagePath,
        config: OCRConfig(
          language: effectiveLang,
        ),
      );
      return text;
    } catch (e) {
      debugPrint('OCR extraction error ($effectiveLang): $e');
      return '';
    }
  }

  /// Processes raw extracted text into structured document metadata suggestions.
  OcrExtractionResult parseMetadata(String ocrText) {
    return OcrExtractor.extract(ocrText);
  }
}
