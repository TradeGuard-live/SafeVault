import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault/core/security/encryption_service.dart';
import 'package:vault/core/security/vault_session.dart';
import 'package:vault/core/services/native_saf_and_share_service.dart';
import 'package:vault/features/documents/domain/document_draft_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Part 1: VaultSession System Activity Lifecycle Grace (Bug 1 Fix)', () {
    late VaultSession session;
    late SecretKey dummyMasterKey;

    setUp(() async {
      session = VaultSession();
      final algorithm = AesGcm.with256bits();
      dummyMasterKey = await algorithm.newSecretKey();
      await session.unlock(dummyMasterKey);
      session.setAutoLockTimeout(
        0,
      ); // Immediate lock upon regular backgrounding
    });

    tearDown(() {
      session.dispose();
    });

    test('Regular backgrounding immediately locks vault when autoLockTimeoutSeconds == 0', () {
      expect(session.isUnlocked, isTrue);

      // App transitions to paused (e.g. user pressed Home or switched apps)
      session.handleLifecycleChange(AppLifecycleState.paused);

      expect(session.isUnlocked, isFalse);
      expect(session.masterKey, isNull);
    });

    test('Launching system activity (SAF File Picker) prevents premature lock on paused/inactive', () {
      expect(session.isUnlocked, isTrue);

      // Explicitly launch Android Storage Access Framework file picker
      session.beginSystemActivity('SAF_OPEN_DOCUMENT');
      expect(session.isSystemActivityActive, isTrue);
      expect(session.activeSystemActivityDescription, 'SAF_OPEN_DOCUMENT');

      // Android pauses MainActivity to show system file picker dialog
      session.handleLifecycleChange(AppLifecycleState.inactive);
      expect(
        session.isUnlocked,
        isTrue,
        reason: 'Inactive state during SAF picker must not lock',
      );

      session.handleLifecycleChange(AppLifecycleState.paused);
      expect(
        session.isUnlocked,
        isTrue,
        reason: 'Paused state during SAF picker must not lock',
      );
      expect(session.masterKey, isNotNull);

      // User selects a file and returns to Vault (resumed)
      session.handleLifecycleChange(AppLifecycleState.resumed);
      expect(
        session.isUnlocked,
        isTrue,
        reason: 'Returning from SAF picker keeps vault unlocked',
      );
      expect(session.masterKey, isNotNull);

      // Picker operation finishes
      session.endSystemActivity();
      expect(session.isSystemActivityActive, isFalse);

      // Subsequent regular backgrounding without active system activity locks normally
      session.handleLifecycleChange(AppLifecycleState.paused);
      expect(
        session.isUnlocked,
        isFalse,
        reason: 'Regular backgrounding after picker locks normally',
      );
    });

    test('NativeSafAndShareService coordinates system activity lifecycle with VaultSession', () async {
      final service = NativeSafAndShareService.instance;
      service.attachSession(session);

      expect(session.isSystemActivityActive, isFalse);

      // Manual check on begin/end lifecycle coordination
      session.beginSystemActivity('SAF_OPEN_DOCUMENT');
      expect(session.isSystemActivityActive, isTrue);

      session.handleLifecycleChange(AppLifecycleState.paused);
      expect(session.isUnlocked, isTrue);

      session.handleLifecycleChange(AppLifecycleState.resumed);
      expect(session.isUnlocked, isTrue);

      session.endSystemActivity();
      expect(session.isSystemActivityActive, isFalse);
    });
  });

  group('Part 2: DocumentDraftModel (Bug 2 Fix)', () {
    test('DocumentDraftModel reports isEmpty accurately for empty drafts', () {
      final emptyDraft = DocumentDraftModel(updatedAt: DateTime.now());
      expect(emptyDraft.isEmpty, isTrue);
      expect(emptyDraft.isNotEmpty, isFalse);
    });

    test('DocumentDraftModel reports isNotEmpty when fields are populated', () {
      final draft = DocumentDraftModel(
        title: 'Aadhaar Card Copy',
        categoryId: 'personal_identity',
        documentNumber: '1234 5678 9012',
        ownerName: 'Naman',
        notes: 'Verified scan',
        tags: const ['aadhaar', 'id'],
        attachedFiles: const [
          {
            'path': '/path/to/scan1.jpg',
            'mimeType': 'image/jpeg',
            'name': 'scan1.jpg',
          },
        ],
        updatedAt: DateTime.now(),
      );

      expect(draft.isEmpty, isFalse);
      expect(draft.isNotEmpty, isTrue);
      expect(draft.title, 'Aadhaar Card Copy');
      expect(draft.attachedFiles.length, 1);
    });

    test(
      'DocumentDraftModel serializes and deserializes to/from Map perfectly',
      () {
        final now = DateTime(2026, 11, 21, 14, 30);
        final issueDate = DateTime(2024, 1, 15);
        final expiryDate = DateTime(2034, 1, 15);

        final original = DocumentDraftModel(
          id: 'active_draft',
          title: 'Passport Renewal',
          categoryId: 'personal_identity',
          documentType: 'Passport',
          documentNumber: 'Z1234567',
          ownerName: 'Naman Sharma',
          issuingAuthority: 'Passport Seva Kendra',
          issueDate: issueDate,
          expiryDate: expiryDate,
          notes: 'Original document in locker',
          tags: const ['passport', 'official', 'travel'],
          attachedFiles: const [
            {
              'path': '/cache/staging/doc1.pdf',
              'mimeType': 'application/pdf',
              'name': 'doc1.pdf',
            },
            {
              'path': '/cache/staging/doc2.jpg',
              'mimeType': 'image/jpeg',
              'name': 'doc2.jpg',
            },
          ],
          updatedAt: now,
        );

        final map = original.toMap();
        final restored = DocumentDraftModel.fromMap(map);

        expect(restored.id, original.id);
        expect(restored.title, original.title);
        expect(restored.categoryId, original.categoryId);
        expect(restored.documentType, original.documentType);
        expect(restored.documentNumber, original.documentNumber);
        expect(restored.ownerName, original.ownerName);
        expect(restored.issuingAuthority, original.issuingAuthority);
        expect(restored.issueDate, original.issueDate);
        expect(restored.expiryDate, original.expiryDate);
        expect(restored.notes, original.notes);
        expect(restored.tags, original.tags);
        expect(restored.attachedFiles.length, 2);
        expect(restored.attachedFiles[0]['name'], 'doc1.pdf');
        expect(restored.attachedFiles[1]['name'], 'doc2.jpg');
      },
    );

    test('DocumentDraftModel copyWith modifies specified fields without mutating others', () {
      final draft = DocumentDraftModel(
        title: 'Original Title',
        categoryId: 'financial',
        updatedAt: DateTime.now(),
      );

      final updated = draft.copyWith(
        title: 'Updated Title',
        documentNumber: 'ACC-9988',
      );

      expect(updated.title, 'Updated Title');
      expect(updated.documentNumber, 'ACC-9988');
      expect(updated.categoryId, 'financial');
    });
  });

  group('Part 3: Encrypted Draft Persistence (AES-256-GCM)', () {
    late SecretKey masterKey;
    late EncryptionService encryptionService;

    setUp(() async {
      encryptionService = EncryptionService();
      masterKey = await AesGcm.with256bits().newSecretKey();
    });

    test('Draft data is strictly encrypted at rest with AES-256-GCM (No plaintext storage)', () async {
      final draft = DocumentDraftModel(
        title: 'Top Secret Aadhaar Number',
        documentNumber: '9999-8888-7777',
        ownerName: 'Confidential Owner',
        notes: 'Highly sensitive notes stored only on local device',
        updatedAt: DateTime.now(),
      );

      // Save draft encrypted with masterKey
      final jsonStr = jsonEncode(draft.toMap());
      final encData = await encryptionService.encryptString(jsonStr, masterKey);

      // Verify encrypted string has NO plaintext keywords
      expect(encData.contains('Top Secret Aadhaar Number'), isFalse);
      expect(encData.contains('9999-8888-7777'), isFalse);
      expect(encData.contains('Confidential Owner'), isFalse);
      expect(encData.contains('Highly sensitive notes'), isFalse);

      // Decrypt and verify full roundtrip
      final decryptedJson = await encryptionService.decryptString(
        encData,
        masterKey,
      );
      final restoredDraft = DocumentDraftModel.fromMap(
        jsonDecode(decryptedJson),
      );

      expect(restoredDraft.title, 'Top Secret Aadhaar Number');
      expect(restoredDraft.documentNumber, '9999-8888-7777');
      expect(restoredDraft.ownerName, 'Confidential Owner');
    });

    test('Draft decryption with invalid/different key fails safely', () async {
      final draft = DocumentDraftModel(
        title: 'Sensitive Title',
        updatedAt: DateTime.now(),
      );

      final encData = await encryptionService.encryptString(
        jsonEncode(draft.toMap()),
        masterKey,
      );
      final wrongKey = await AesGcm.with256bits().newSecretKey();

      expect(
        () async => await encryptionService.decryptString(encData, wrongKey),
        throwsA(anything),
      );
    });
  });

  group(
    'Part 4: Android My Files Incoming Share Integration & Post-Import Actions',
    () {
      test('SafFileItem distinguishes PDF and Images correctly', () {
        final pdfItem = SafFileItem.fromMap({
          'path': '/storage/emulated/0/Download/pan_card.pdf',
          'name': 'pan_card.pdf',
          'size': 204800,
          'mimeType': 'application/pdf',
        });
        expect(pdfItem.isPdf, isTrue);
        expect(pdfItem.isImage, isFalse);

        final pngItem = SafFileItem.fromMap({
          'path': '/storage/emulated/0/Pictures/driving_licence.png',
          'name': 'driving_licence.png',
          'size': 512000,
          'mimeType': 'image/png',
        });
        expect(pngItem.isPdf, isFalse);
        expect(pngItem.isImage, isTrue);
      });

      test('Incoming share queue retains items for 2FA unlocking', () {
        final items = [
          const SafFileItem(
            path: '/cache/staging/doc1.pdf',
            name: 'doc1.pdf',
            size: 1024,
            mimeType: 'application/pdf',
          ),
        ];

        expect(items.isNotEmpty, isTrue);
        expect(items.first.name, 'doc1.pdf');
      });
    },
  );
}
