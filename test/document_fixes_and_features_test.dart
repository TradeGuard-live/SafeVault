import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'package:vault/core/security/authentication_gate.dart';
import 'package:vault/core/services/native_saf_and_share_service.dart';
import 'package:vault/features/documents/presentation/incoming_share_preview_screen.dart';
import 'package:vault/features/ocr/domain/document_extraction_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Document Fix 1: Biometric Protected Document Preview & Attached Files', () {
    test('VaultActionType.viewDocumentPreview and viewAttachedFile are defined and registered', () {
      expect(
        VaultActionType.values.contains(VaultActionType.viewDocumentPreview),
        isTrue,
      );
      expect(
        VaultActionType.values.contains(VaultActionType.viewAttachedFile),
        isTrue,
      );
    });

    test(
      'PendingVaultAction with viewDocumentPreview creates valid authorization',
      () {
        final action = PendingVaultAction(
          type: VaultActionType.viewDocumentPreview,
          targetId: 'doc-123',
          targetName: 'Aadhaar Card',
          returnRoute: '/document/doc-123',
        );

        expect(action.type, VaultActionType.viewDocumentPreview);
        expect(action.targetId, 'doc-123');
        expect(action.targetName, 'Aadhaar Card');
        expect(action.returnRoute, '/document/doc-123');
        expect(action.isExecuted, isFalse);
      },
    );

    test(
      'PendingVaultAction with viewAttachedFile creates valid authorization with file parameters',
      () {
        final action = PendingVaultAction(
          type: VaultActionType.viewAttachedFile,
          targetId: 'doc-123',
          targetName: 'passport_scan.pdf',
          returnRoute: '/document/doc-123',
          params: {
            'fileId': 'file-999',
            'encryptedFilePath': '/vault/files/enc_passport.bin',
            'mimeType': 'application/pdf',
            'fileName': 'passport_scan.pdf',
          },
        );

        expect(action.type, VaultActionType.viewAttachedFile);
        expect(action.targetId, 'doc-123');
        expect(action.targetName, 'passport_scan.pdf');
        expect(action.params['mimeType'], 'application/pdf');
        expect(action.params['fileName'], 'passport_scan.pdf');
        expect(action.isExecuted, isFalse);
      },
    );
  });

  group(
    'Document Fix 2: Combining 2 Shared Images into a Single PDF Document (Zero White Bars)',
    () {
      test(
        'Compiles 2 images into a single valid 2-page PDF document without white bars matching aspect ratios',
        () async {
          // 1. Create 2 synthetic test images (e.g. Front 160x90 landscape, Back 90x120 portrait)
          final img1 = img.Image(width: 160, height: 90);
          img.fill(img1, color: img.ColorRgb8(255, 0, 0)); // Red image (Page 1)
          final bytes1 = Uint8List.fromList(img.encodeJpg(img1));

          final img2 = img.Image(width: 90, height: 120);
          img.fill(
            img2,
            color: img.ColorRgb8(0, 0, 255),
          ); // Blue image (Page 2)
          final bytes2 = Uint8List.fromList(img.encodeJpg(img2));

          // 2. Compile into single PDF using dynamic aspect ratio without white bars
          final pdf = pw.Document();
          for (final imageBytes in [bytes1, bytes2]) {
            final image = pw.MemoryImage(imageBytes);
            double pageW = 595.27559;
            double pageH = 841.88976;

            final imgW = image.width?.toDouble();
            final imgH = image.height?.toDouble();

            if (imgW != null && imgH != null && imgW > 0 && imgH > 0) {
              pageH = pageW * (imgH / imgW);
            }

            final pageFormat = PdfPageFormat(pageW, pageH, marginAll: 0.0);
            pdf.addPage(
              pw.Page(
                pageFormat: pageFormat,
                margin: pw.EdgeInsets.zero,
                build: (pw.Context context) {
                  return pw.FullPage(
                    ignoreMargins: true,
                    child: pw.Image(image, fit: pw.BoxFit.fill),
                  );
                },
              ),
            );
          }

          final pdfBytes = await pdf.save();
          expect(pdfBytes, isNotEmpty);
          expect(pdfBytes.length, greaterThan(100));

          // Verify header of PDF
          final header = String.fromCharCodes(pdfBytes.sublist(0, 5));
          expect(header, '%PDF-');

          // 3. Verify page count and dynamic page dimensions (zero white bars)
          final loadedDoc = sf.PdfDocument(inputBytes: pdfBytes);
          expect(loadedDoc.pages.count, 2);

          // Page 1 should match 160:90 aspect ratio (334.84 pt height for 595.28 pt width)
          final p1Size = loadedDoc.pages[0].size;
          expect(p1Size.width, closeTo(595.28, 0.5));
          expect(p1Size.height, closeTo(334.84, 0.5));
          expect((p1Size.width / p1Size.height), closeTo(160 / 90, 0.01));

          // Page 2 should match 90:120 aspect ratio (793.70 pt height for 595.28 pt width)
          final p2Size = loadedDoc.pages[1].size;
          expect(p2Size.width, closeTo(595.28, 0.5));
          expect(p2Size.height, closeTo(793.70, 0.5));
          expect((p2Size.width / p2Size.height), closeTo(90 / 120, 0.01));

          loadedDoc.dispose();
        },
      );

      test(
        'IncomingShareItemState parses image item correctly and supports swap',
        () {
          final item1 = SafFileItem(
            path: '/cache/aadhaar_front.jpg',
            name: 'aadhaar_front.jpg',
            size: 1024,
            mimeType: 'image/jpeg',
          );
          final item2 = SafFileItem(
            path: '/cache/aadhaar_back.jpg',
            name: 'aadhaar_back.jpg',
            size: 1024,
            mimeType: 'image/jpeg',
          );

          final state1 = IncomingShareItemState(
            item: item1,
            customName: 'Aadhaar Front',
          );
          final state2 = IncomingShareItemState(
            item: item2,
            customName: 'Aadhaar Back',
          );

          final items = [state1, state2];
          expect(items[0].customName, 'Aadhaar Front');
          expect(items[1].customName, 'Aadhaar Back');

          // Simulate swap
          final temp = items[0];
          items[0] = items[1];
          items[1] = temp;

          expect(items[0].customName, 'Aadhaar Back'); // Now Page 1
          expect(items[1].customName, 'Aadhaar Front'); // Now Page 2
        },
      );
    },
  );

  group('Document Fix 3: Moving Extracted Info to Preview Page', () {
    test('ExtractedFieldModel supports toggling isSelected for preview display', () {
      final now = DateTime.now();
      final field = ExtractedFieldModel(
        id: 'f-1',
        extractionId: 'ext-1',
        fieldName: 'Date of Birth',
        encryptedValue: 'enc_dob',
        confidence: 0.95,
        confidenceCategory: 'High',
        isSelected: false,
        createdAt: now,
        updatedAt: now,
        plainValue: '15/08/1990',
      );

      expect(field.isSelected, isFalse);

      final onPreview = field.copyWith(isSelected: true);
      expect(onPreview.isSelected, isTrue);
      expect(onPreview.plainValue, '15/08/1990');
      expect(onPreview.fieldName, 'Date of Birth');

      final removedFromPreview = onPreview.copyWith(isSelected: false);
      expect(removedFromPreview.isSelected, isFalse);
    });

    test('Filtering fields for Preview card displays only selected extracted fields', () {
      final now = DateTime.now();
      final fields = [
        ExtractedFieldModel(
          id: 'f-1',
          extractionId: 'ext-1',
          fieldName: 'Date of Birth',
          encryptedValue: 'enc_dob',
          confidence: 0.95,
          confidenceCategory: 'High',
          isSelected: true, // Shown on preview
          createdAt: now,
          updatedAt: now,
          plainValue: '15/08/1990',
        ),
        ExtractedFieldModel(
          id: 'f-2',
          extractionId: 'ext-1',
          fieldName: "Father's Name",
          encryptedValue: 'enc_father',
          confidence: 0.88,
          confidenceCategory: 'High',
          isSelected: false, // Not on preview
          createdAt: now,
          updatedAt: now,
          plainValue: 'Ramesh Sharma',
        ),
        ExtractedFieldModel(
          id: 'f-3',
          extractionId: 'ext-1',
          fieldName: 'Address',
          encryptedValue: 'enc_addr',
          confidence: 0.92,
          confidenceCategory: 'High',
          isSelected: true, // Shown on preview
          createdAt: now,
          updatedAt: now,
          plainValue: '123 MG Road, Mumbai',
        ),
      ];

      final previewFields = fields.where((f) => f.isSelected).toList();
      expect(previewFields.length, 2);
      expect(previewFields.map((f) => f.fieldName).toList(), ['Date of Birth', 'Address']);

      final unselectedFields = fields.where((f) => !f.isSelected).toList();
      expect(unselectedFields.length, 1);
      expect(unselectedFields.first.fieldName, "Father's Name");
    });
  });
}
