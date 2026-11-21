import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault/core/security/clipboard_security_service.dart';
import 'package:vault/core/security/encryption_service.dart';
import 'package:vault/core/services/native_saf_and_share_service.dart';
import 'package:vault/features/ocr/data/document_field_extractor.dart';
import 'package:vault/features/ocr/data/document_text_extractor.dart';
import 'package:vault/features/ocr/data/offline_ocr_service.dart';
import 'package:vault/features/ocr/data/smart_document_classifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Part 1 & 2: Native Android SAF & Share Item Models', () {
    test('SafFileItem parses from map and identifies PDF and Image MIME types', () {
      final pdfItem = SafFileItem.fromMap({
        'path': '/data/user/0/com.vault.vault/cache/staging/saf_import_1.pdf',
        'name': 'passport_copy.pdf',
        'size': 1048576,
        'mimeType': 'application/pdf',
      });

      expect(pdfItem.name, 'passport_copy.pdf');
      expect(pdfItem.size, 1048576);
      expect(pdfItem.isPdf, isTrue);
      expect(pdfItem.isImage, isFalse);

      final imgItem = SafFileItem.fromMap({
        'path': '/data/user/0/com.vault.vault/cache/staging/saf_import_2.jpg',
        'name': 'aadhaar_front.jpg',
        'size': 524288,
        'mimeType': 'image/jpeg',
      });

      expect(imgItem.isPdf, isFalse);
      expect(imgItem.isImage, isTrue);
    });

    test('SafFileItem handles missing or null fields gracefully', () {
      final item = SafFileItem.fromMap({});
      expect(item.path, '');
      expect(item.name, 'document');
      expect(item.size, 0);
      expect(item.mimeType, 'application/octet-stream');
    });
  });

  group('Part 3 & 4: Offline OCR & Smart Document Classification Engine', () {
    test('OfflineOcrService verifies supported offline scripts (eng, hin, guj)', () {
      expect(OfflineOcrService.isLanguageSupported('eng'), isTrue);
      expect(OfflineOcrService.isLanguageSupported('hin'), isTrue);
      expect(OfflineOcrService.isLanguageSupported('guj'), isTrue);
      expect(OfflineOcrService.isLanguageSupported('fra'), isFalse);
      expect(OfflineOcrService.supportedLanguages.contains('guj'), isTrue);
    });

    test('SmartDocumentClassifier classifies PAN Card correctly', () {
      const panSample = '''
      INCOME TAX DEPARTMENT
      GOVT. OF INDIA
      PERMANENT ACCOUNT NUMBER CARD
      ABCDE1234F
      NAME: RAHUL KUMAR SHARMA
      FATHER: RAJESH SHARMA
      DATE OF BIRTH: 15/08/1990
      ''';

      final classification = SmartDocumentClassifier.classify(panSample);
      expect(classification.documentType, 'PAN Card');
      expect(classification.categoryId, 'personal_identity');
      expect(classification.confidence, greaterThanOrEqualTo(0.90));
    });

    test('SmartDocumentClassifier classifies Aadhaar Card correctly', () {
      const aadhaarSample = '''
      UNIQUE IDENTIFICATION AUTHORITY OF INDIA
      GOVERNMENT OF INDIA
      Mera Aadhaar, Meri Pehchan
      To: Priya Patel
      Address: Flat 402, Lotus Residency, Ahmedabad, Gujarat 380015
      DOB: 22/11/1995
      Gender: FEMALE
      1234 5678 9012
      ''';

      final classification = SmartDocumentClassifier.classify(aadhaarSample);
      expect(classification.documentType, 'Aadhaar Card');
      expect(classification.categoryId, 'personal_identity');
      expect(classification.confidence, greaterThanOrEqualTo(0.90));
    });

    test('SmartDocumentClassifier classifies Driving Licence correctly', () {
      const dlSample = '''
      UNION OF INDIA DRIVING LICENCE
      TRANSPORT DEPARTMENT DELHI
      DL NO: DL0420110012345
      NAME: VIKRAM SINGH
      DOB: 10/05/1988
      ISSUE DATE: 12/03/2011
      VALID TILL: 09/05/2028
      AUTHORISED TO DRIVE: LMV, MCWG
      ''';

      final classification = SmartDocumentClassifier.classify(dlSample);
      expect(classification.documentType, 'Driving Licence');
      expect(classification.categoryId, 'vehicle_documents');
      expect(classification.confidence, greaterThanOrEqualTo(0.90));
    });

    test('SmartDocumentClassifier classifies Vehicle RC Book correctly', () {
      const rcSample = '''
      FORM 23
      CERTIFICATE OF REGISTRATION
      REGISTRATION NUMBER: MH12AB1234
      REGISTERED OWNER: AMIT VERMA
      CHASSIS NO: MA3EKA12S00123456
      ENGINE NO: K12MN1234567
      FUEL: PETROL
      REG. DATE: 05/01/2020
      ''';

      final classification = SmartDocumentClassifier.classify(rcSample);
      expect(classification.documentType, 'Vehicle RC Book');
      expect(classification.categoryId, 'vehicle_documents');
      expect(classification.confidence, greaterThanOrEqualTo(0.90));
    });

    test('SmartDocumentClassifier classifies Passport correctly', () {
      const passportSample = '''
      PASSPORT
      REPUBLIC OF INDIA
      TYPE: P  COUNTRY CODE: IND  PASSPORT NO: Z1234567
      SURNAME: GUPTA
      GIVEN NAMES: ANANYA
      NATIONALITY: INDIAN
      SEX: F
      DATE OF BIRTH: 04/09/1992
      DATE OF ISSUE: 15/06/2018
      DATE OF EXPIRY: 14/06/2028
      ''';

      final classification = SmartDocumentClassifier.classify(passportSample);
      expect(classification.documentType, 'Passport');
      expect(classification.categoryId, 'personal_identity');
      expect(classification.confidence, greaterThanOrEqualTo(0.90));
    });
  });

  group('Part 4: Structured Field Extractor & Confidence Scoring', () {
    test('Extracts PAN Card structured fields with confidence scores', () {
      const panText = '''
      INCOME TAX DEPARTMENT
      ABCDE1234F
      RAHUL KUMAR SHARMA
      FATHER: RAJESH SHARMA
      DOB: 15/08/1990
      ''';

      final fields = DocumentFieldExtractor.extractFields(
        fullText: panText,
        documentType: 'PAN Card',
      );

      final panNumField = fields.firstWhere((f) => f.fieldName == 'PAN Number');
      expect(panNumField.value, 'ABCDE1234F');
      expect(panNumField.confidenceCategory, 'High');

      final dobField = fields.firstWhere((f) => f.fieldName == 'Date of Birth');
      expect(dobField.value, '15/08/1990');
      expect(dobField.confidenceCategory, 'High');
    });

    test('Extracts Aadhaar fields with masked preference (XXXX XXXX 1234)', () {
      const aadhaarText = '''
      UNIQUE IDENTIFICATION AUTHORITY OF INDIA
      DOB: 22/11/1995
      MALE
      Address: 123 Main Street, Pune
      1234 5678 9012
      ''';

      final fields = DocumentFieldExtractor.extractFields(
        fullText: aadhaarText,
        documentType: 'Aadhaar Card',
      );

      final aadhaarField = fields.firstWhere((f) => f.fieldName == 'Aadhaar Number');
      expect(aadhaarField.value, 'XXXX XXXX 9012');
      expect(aadhaarField.confidenceCategory, 'High');

      final genderField = fields.firstWhere((f) => f.fieldName == 'Gender');
      expect(genderField.value, 'MALE');
    });

    test('Extracts Driving Licence number and vehicle classes', () {
      const dlText = '''
      DRIVING LICENCE
      DL NO: DL0420110012345
      DOB: 10/05/1988
      ISSUE DATE: 12/03/2011
      EXPIRY DATE: 09/05/2028
      VEHICLE CLASS: LMV, MCWG
      ''';

      final fields = DocumentFieldExtractor.extractFields(
        fullText: dlText,
        documentType: 'Driving Licence',
      );

      final dlNum = fields.firstWhere((f) => f.fieldName == 'Licence Number');
      expect(dlNum.value.replaceAll(' ', ''), 'DL0420110012345');
      expect(dlNum.confidenceCategory, 'High');

      final classes = fields.firstWhere((f) => f.fieldName == 'Authorised Vehicle Class');
      expect(classes.value.contains('LMV'), isTrue);
      expect(classes.value.contains('MCWG'), isTrue);
    });

    test('Never invents missing fields', () {
      const partialText = 'DRIVING LICENCE WITHOUT NUMBERS OR DATES';
      final fields = DocumentFieldExtractor.extractFields(
        fullText: partialText,
        documentType: 'Driving Licence',
      );

      expect(fields.any((f) => f.fieldName == 'Licence Number'), isFalse);
      expect(fields.any((f) => f.fieldName == 'Date of Birth'), isFalse);
    });
  });

  group('Part 5: Formatted Text Record Generation & Encrypted Storage', () {
    test('generateFormattedTextRecord formats human-readable TXT companion file', () {
      final rawFields = [
        const RawExtractedField(
          fieldName: 'PAN Number',
          value: 'ABCDE1234F',
          confidence: 0.98,
          confidenceCategory: 'High',
        ),
        const RawExtractedField(
          fieldName: 'Date of Birth',
          value: '15/08/1990',
          confidence: 0.95,
          confidenceCategory: 'High',
        ),
      ];

      final txt = DocumentTextExtractor.generateFormattedTextRecord(
        documentType: 'PAN Card',
        categoryName: 'Personal Identity',
        sourceFileName: 'pan_scan.jpg',
        fullText: 'INCOME TAX DEPARTMENT ABCDE1234F 15/08/1990',
        fields: rawFields,
        engine: 'Tesseract OCR (Offline)',
        language: 'eng',
        pageCount: 1,
      );

      expect(txt.contains('DOCUMENT: PAN Card'), isTrue);
      expect(txt.contains('DOCUMENT CATEGORY: Personal Identity'), isTrue);
      expect(txt.contains('SOURCE FILE: pan_scan.jpg'), isTrue);
      expect(txt.contains('PAN Number: ABCDE1234F (Confidence: High)'), isTrue);
      expect(txt.contains('FULL EXTRACTED TEXT'), isTrue);
      expect(txt.contains('EXTRACTION STATUS'), isTrue);
      expect(txt.contains('Language: eng'), isTrue);
    });

    test('Encrypted TXT file roundtrip matches original plaintext and protects against tampering', () async {
      final encryptionService = EncryptionService();
      final masterKey = await encryptionService.generateRandomMasterKey();

      const originalText = '''
      DOCUMENT: Driving Licence
      Licence Number: DL0420110012345
      FULL EXTRACTED TEXT
      Sample extracted OCR content for testing.
      ''';

      final encryptedPayload = await encryptionService.encryptBytes(
        Uint8List.fromList(utf8.encode(originalText)),
        masterKey,
      );

      // Decrypt with correct key
      final decryptedBytes = await encryptionService.decryptBytes(encryptedPayload, masterKey);
      final decryptedString = utf8.decode(decryptedBytes);
      expect(decryptedString, originalText);

      // Tampering tag or ciphertext fails decryption
      final tampered = Uint8List.fromList(encryptedPayload);
      tampered[tampered.length - 1] ^= 0xFF; // Flip bit in GCM auth tag
      expect(
        () async => await encryptionService.decryptBytes(tampered, masterKey),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('Part 8 & Native Manifest: FileProvider & Offline Security', () {
    test('AndroidManifest.xml declares FileProvider for secure outgoing shares', () {
      final manifest = File('android/app/src/main/AndroidManifest.xml');
      expect(manifest.existsSync(), isTrue);
      final content = manifest.readAsStringSync();

      expect(content.contains('androidx.core.content.FileProvider'), isTrue);
      expect(content.contains('com.vault.vault.fileprovider'), isTrue);
      expect(content.contains('android:grantUriPermissions="true"'), isTrue);
      expect(content.contains('@xml/provider_paths'), isTrue);
    });

    test('AndroidManifest.xml declares incoming SEND and SEND_MULTIPLE intent filters', () {
      final manifest = File('android/app/src/main/AndroidManifest.xml');
      final content = manifest.readAsStringSync();

      expect(content.contains('android.intent.action.SEND'), isTrue);
      expect(content.contains('android.intent.action.SEND_MULTIPLE'), isTrue);
      expect(content.contains('android:mimeType="application/pdf"'), isTrue);
      expect(content.contains('android:mimeType="image/jpeg"'), isTrue);
      expect(content.contains('android:mimeType="image/png"'), isTrue);
    });

    test('provider_paths.xml exposes only ephemeral shared_exports directory', () {
      final pathsFile = File('android/app/src/main/res/xml/provider_paths.xml');
      expect(pathsFile.existsSync(), isTrue);
      final content = pathsFile.readAsStringSync();

      expect(content.contains('<cache-path name="shared_exports" path="shared_exports/" />'), isTrue);
      // Does not expose root database or full app data
      expect(content.contains('<root-path'), isFalse);
    });

    test('100% Offline Integrity: Zero network permissions in AndroidManifest.xml', () {
      final manifest = File('android/app/src/main/AndroidManifest.xml');
      final content = manifest.readAsStringSync();

      expect(content.contains('android.permission.INTERNET" tools:node="remove"'), isTrue);
      expect(content.contains('android.permission.ACCESS_NETWORK_STATE" tools:node="remove"'), isTrue);
      expect(content.contains('android.permission.RECORD_AUDIO" tools:node="remove"'), isTrue);
    });
  });
}
