import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vault/core/errors/exceptions.dart';
import 'package:vault/core/security/file_validator.dart';
import 'package:vault/features/ocr/data/ocr_extractor.dart';

void main() {
  group('File Validator Signature Tests', () {
    test('Validates authentic PDF signature', () {
      final pdfBytes = Uint8List.fromList([
        0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x35, // %PDF-1.5
        0x0A, 0x25, 0xE2, 0xE3, 0xCF, 0xD3,
      ]);

      final result = FileValidator.validateBytes(pdfBytes);
      expect(result.fileType, equals(ValidatedFileType.pdf));
      expect(result.mimeType, equals('application/pdf'));
      expect(result.extension, equals('pdf'));
    });

    test('Validates authentic JPEG signature', () {
      final jpegBytes = Uint8List.fromList([
        0xFF,
        0xD8,
        0xFF,
        0xE0,
        0x00,
        0x10,
        0x4A,
        0x46,
        0x49,
        0x46,
      ]);

      final result = FileValidator.validateBytes(jpegBytes);
      expect(result.fileType, equals(ValidatedFileType.jpeg));
      expect(result.mimeType, equals('image/jpeg'));
      expect(result.extension, equals('jpg'));
    });

    test('Validates authentic PNG signature', () {
      final pngBytes = Uint8List.fromList([
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
        0x00,
        0x00,
        0x00,
        0x0D,
      ]);

      final result = FileValidator.validateBytes(pngBytes);
      expect(result.fileType, equals(ValidatedFileType.png));
      expect(result.mimeType, equals('image/png'));
      expect(result.extension, equals('png'));
    });

    test('Rejects arbitrary untrusted file bytes', () {
      final untrustedBytes = Uint8List.fromList([
        0x4D, 0x5A, 0x90, 0x00, 0x03, 0x00, 0x00, 0x00, // Windows MZ header
      ]);

      expect(
        () => FileValidator.validateBytes(untrustedBytes),
        throwsA(isA<UnsupportedFormatException>()),
      );
    });
  });

  group('Offline OCR Extractor Intelligence Tests', () {
    test('Extracts PAN Card number, category and authority', () {
      const sampleOcr = '''
        INCOME TAX DEPARTMENT
        GOVT. OF INDIA
        Permanent Account Number Card
        ABCDE1234F
        Name: RAJESH SHARMA
        Father's Name: SURESH SHARMA
        Date of Birth: 15/08/1988
      ''';

      final result = OcrExtractor.extract(sampleOcr);
      expect(result.suggestedName, equals('PAN Card'));
      expect(result.suggestedCategoryId, equals('personal_identity'));
      expect(result.suggestedNumber, equals('ABCDE1234F'));
      expect(result.suggestedAuthority, equals('Income Tax Department'));
    });

    test('Extracts Aadhaar Card number and UIDAI authority', () {
      const sampleOcr = '''
        GOVERNMENT OF INDIA
        UNIQUE IDENTIFICATION AUTHORITY OF INDIA
        Aadhaar
        MERA AADHAAR, MERI PEHCHAAN
        3421 8976 5412
        VID: 9182 3746 1928 3746
      ''';

      final result = OcrExtractor.extract(sampleOcr);
      expect(result.suggestedName, equals('Aadhaar Card'));
      expect(result.suggestedCategoryId, equals('personal_identity'));
      expect(result.suggestedNumber, equals('3421 8976 5412'));
      expect(result.suggestedAuthority, equals('UIDAI'));
    });

    test('Extracts Driving Licence number and expiry date', () {
      const sampleOcr = '''
        UNION OF INDIA DRIVING LICENCE
        TRANSPORT DEPARTMENT
        DL NO: MH02 20180012345
        Name: AMIT PATEL
        ISSUE DATE: 10/01/2018
        VALID UPTO: 09/01/2038
      ''';

      final result = OcrExtractor.extract(sampleOcr);
      expect(result.suggestedName, equals('Driving Licence'));
      expect(result.suggestedCategoryId, equals('vehicle_documents'));
      expect(result.suggestedNumber, contains('MH02'));
      expect(result.suggestedExpiryDate, isNotNull);
      expect(result.suggestedExpiryDate!.year, equals(2038));
    });
  });
}
