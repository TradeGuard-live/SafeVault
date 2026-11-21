import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:vault/core/constants/app_constants.dart';
import 'package:vault/core/errors/exceptions.dart';
import 'package:vault/core/security/authentication_gate.dart';
import 'package:vault/core/security/encryption_service.dart';
import 'package:vault/core/security/key_management_service.dart';
import 'package:vault/core/security/native_biometric_keystore_service.dart';
import 'package:vault/core/security/vault_session.dart';
import 'package:vault/core/storage/encrypted_file_storage.dart';
import 'package:vault/features/ocr/data/document_field_extractor.dart';

class MockSecureStorage extends FlutterSecureStorage {
  final Map<String, String> _storage = {};

  MockSecureStorage() : super();

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value != null) {
      _storage[key] = value;
    } else {
      _storage.remove(key);
    }
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return _storage[key];
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _storage.remove(key);
  }

  @override
  Future<void> deleteAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _storage.clear();
  }
}

class MockKeystoreService extends NativeBiometricKeystoreService {
  bool keyExists = false;
  Uint8List? lastWrapped;

  MockKeystoreService() : super();

  @override
  bool get isSupported => true;

  @override
  Future<bool> generateBiometricKey() async {
    keyExists = true;
    return true;
  }

  @override
  Future<Uint8List> wrapBiometricShare(Uint8List shareBytes) async {
    if (!keyExists) throw const BiometricException('Keystore key not found');
    // Prepend 12 bytes dummy IV + 16 bytes tag simulation
    final iv = Uint8List(12)..fillRange(0, 12, 0x42);
    final wrapped = Uint8List(12 + shareBytes.length);
    wrapped.setRange(0, 12, iv);
    wrapped.setRange(12, 12 + shareBytes.length, shareBytes);
    lastWrapped = wrapped;
    return wrapped;
  }

  @override
  Future<Uint8List> unwrapBiometricShare(Uint8List wrappedBytes) async {
    if (!keyExists) throw const BiometricException('Keystore key not found');
    if (wrappedBytes.length <= 12) {
      throw const BiometricException('Payload too short');
    }
    // Extract share after 12-byte IV
    return Uint8List.fromList(wrappedBytes.sublist(12));
  }

  @override
  Future<bool> isKeystoreKeyAvailable() async => keyExists;

  @override
  Future<bool> deleteBiometricKey() async {
    keyExists = false;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P0: Action Restoration & Pending Coordinator Tests', () {
    test('PendingVaultAction preserves original route, query params and safe state', () {
      final action = PendingVaultAction(
        type: VaultActionType.revealPassword,
        targetId: 'pwd_99',
        targetName: 'Work Email',
        originalRoute: '/password/pwd_99',
        queryParams: {'section': 'credentials', 'tab': 'edit'},
        safeState: {'fieldIndex': 2},
      );

      expect(action.id, isNotEmpty);
      expect(action.type, VaultActionType.revealPassword);
      expect(action.targetId, 'pwd_99');
      expect(action.originalRoute, '/password/pwd_99');
      expect(action.returnRoute, '/password/pwd_99');
      expect(action.queryParams['section'], 'credentials');
      expect(action.queryParams['tab'], 'edit');
      expect(action.safeState['fieldIndex'], 2);
      expect(action.isExecuted, isFalse);
      expect(action.isExpired, isFalse);
    });

    test(
      'Pending action cannot be consumed twice (single execution guarantee)',
      () {
        final session = VaultSession();
        final gate = AuthenticationGate(session);

        final action = PendingVaultAction(
          type: VaultActionType.revealBankDetails,
          targetId: 'bank_77',
        );
        gate.setPendingAction(action);

        final firstConsume = gate.consumePendingAction('bank_77');
        expect(firstConsume, isNotNull);
        expect(firstConsume!.isExecuted, isTrue);

        // Second attempt to consume must return null
        final secondConsume = gate.consumePendingAction('bank_77');
        expect(secondConsume, isNull);
      },
    );
  });

  group('P0: Android Keystore Biometric Key & Migration Tests', () {
    late MockSecureStorage mockStorage;
    late MockKeystoreService mockKeystore;
    late EncryptionService encryptionService;
    late KeyManagementService kms;

    setUp(() {
      mockStorage = MockSecureStorage();
      mockKeystore = MockKeystoreService();
      encryptionService = EncryptionService();
      kms = KeyManagementService(
        secureStorage: mockStorage,
        encryptionService: encryptionService,
        keystoreService: mockKeystore,
      );
    });

    test('initializeTwoFactorVault uses hardware Keystore and never stores software bio KEK', () async {
      final masterKey = await kms.initializeTwoFactorVault(pin: '654321');
      expect(masterKey, isNotNull);

      // Hardware Keystore key must have been generated
      expect(mockKeystore.keyExists, isTrue);

      // Software bio KEK must NOT be stored in secure storage
      final softwareKek = await mockStorage.read(key: 'vault_2fa_bio_kek');
      expect(softwareKek, isNull);

      // Wrapped bio share must exist
      final wrappedBio = await mockStorage.read(key: 'vault_2fa_share_bio');
      expect(wrappedBio, isNotNull);

      // 2FA must be marked configured
      final is2Fa = await kms.isTwoFactorConfigured();
      expect(is2Fa, isTrue);

      // Unlock roundtrip
      final bioShare = await kms.startTwoFactorBiometricUnlock();
      expect(bioShare.length, equals(AppConstants.masterKeyLengthBytes));

      final unlockedKey = await kms.completeTwoFactorPinUnlock(
        bioShare: bioShare,
        pin: '654321',
      );

      final origBytes = await masterKey.extractBytes();
      final unlockedBytes = await unlockedKey.extractBytes();
      expect(unlockedBytes, equals(origBytes));
    });

    test('Safe migration from legacy software bio KEK to hardware Keystore preserves VMK', () async {
      // 1. Manually setup a legacy 2FA vault with software KEK in secure storage
      final vmk = await encryptionService.generateRandomMasterKey();
      final vmkBytes = Uint8List.fromList(await vmk.extractBytes());
      final sBio = Uint8List(32)..fillRange(0, 32, 0x11);
      final sPin = Uint8List(32);
      for (int i = 0; i < 32; i++) {
        sPin[i] = vmkBytes[i] ^ sBio[i];
      }

      // Software bio KEK
      final legacyBioKek = await encryptionService.generateRandomMasterKey();
      final legacyBioKekBytes = await legacyBioKek.extractBytes();
      final wrappedBio = await encryptionService.encryptBytes(
        sBio,
        legacyBioKek,
      );

      // PIN KEK
      final salt = Uint8List(32)..fillRange(0, 32, 0x99);
      final pinKek = await kms.deriveKeyFromPinForTest('112233', salt);
      final wrappedPin = await encryptionService.encryptBytes(sPin, pinKek);

      // Write legacy configuration
      await mockStorage.write(
        key: 'vault_2fa_bio_kek',
        value: base64Encode(legacyBioKekBytes),
      );
      await mockStorage.write(
        key: 'vault_2fa_share_bio',
        value: base64Encode(wrappedBio),
      );
      await mockStorage.write(
        key: 'vault_2fa_pin_salt',
        value: base64Encode(salt),
      );
      await mockStorage.write(
        key: 'vault_2fa_share_pin',
        value: base64Encode(wrappedPin),
      );
      await mockStorage.write(key: 'vault_2fa_configured', value: 'true');
      await mockStorage.write(key: 'vault_is_initialized', value: 'true');

      // 2. Perform unlock which must trigger automatic migration to Keystore
      final restoredBioShare = await kms.startTwoFactorBiometricUnlock();
      expect(restoredBioShare, equals(sBio));

      // After migration:
      // Hardware key must exist
      expect(mockKeystore.keyExists, isTrue);
      // Software bio KEK must have been deleted!
      final deletedKek = await mockStorage.read(key: 'vault_2fa_bio_kek');
      expect(deletedKek, isNull);

      // 3. Complete PIN unlock and verify exact master key matches original VMK
      final migratedMasterKey = await kms.completeTwoFactorPinUnlock(
        bioShare: restoredBioShare,
        pin: '112233',
      );
      final migratedBytes = await migratedMasterKey.extractBytes();
      expect(migratedBytes, equals(vmkBytes));
    });
  });

  group('P0: VaultSession Bounded Lease & Memory Lifecycle Tests', () {
    test('beginSystemActivity starts lease timer and locks vault upon lease expiry', () async {
      final session = VaultSession();
      final encService = EncryptionService();
      final key = await encService.generateRandomMasterKey();
      await session.unlock(key);
      expect(session.isUnlocked, isTrue);

      // Begin system activity with short lease duration (50ms)
      session.beginSystemActivity(
        'SAF_FILE_PICKER',
        timeout: const Duration(milliseconds: 50),
      );
      expect(session.isSystemActivityActive, isTrue);

      // Wait for lease timer to expire
      await Future.delayed(const Duration(milliseconds: 80));

      // Session must be locked automatically because lease expired
      expect(session.isSystemActivityActive, isFalse);
      expect(session.isUnlocked, isFalse);
      expect(session.masterKey, isNull);
    });

    test('endSystemActivity cancels lease timer safely', () async {
      final session = VaultSession();
      final encService = EncryptionService();
      final key = await encService.generateRandomMasterKey();
      await session.unlock(key);

      session.beginSystemActivity(
        'CAMERA_SCANNER',
        timeout: const Duration(milliseconds: 100),
      );
      expect(session.isSystemActivityActive, isTrue);

      // Cancel/end activity before lease timer fires
      session.endSystemActivity();
      expect(session.isSystemActivityActive, isFalse);

      await Future.delayed(const Duration(milliseconds: 120));

      // Vault must remain unlocked because activity ended normally
      expect(session.isUnlocked, isTrue);
      expect(session.masterKey, isNotNull);
    });

    test('getMasterKeyOrThrow throws VaultLockedException when locked', () {
      final session = VaultSession();
      expect(
        () => session.getMasterKeyOrThrow(),
        throwsA(isA<VaultLockedException>()),
      );
    });
  });

  group('P1: Encrypted Storage Hardening & Integrity Tests', () {
    test('saveEncryptedFile rejects files exceeding 50 MB', () async {
      final storage = EncryptedFileStorage();
      final encService = EncryptionService();
      final key = await encService.generateRandomMasterKey();

      // Create dummy bytes of 51 MB (simulated without allocating 51MB by passing oversized list)
      final oversizedBytes = Uint8List(51 * 1024 * 1024);

      expect(
        () => storage.saveEncryptedFile(
          plainBytes: oversizedBytes,
          masterKey: key,
        ),
        throwsA(isA<StorageException>()),
      );
    });
  });

  group('P1: Complete RC Book 14 Specific Fields Extraction', () {
    test('RC Book extracts all 14 mandatory fields explicitly', () {
      const rcText = '''
        TRANSPORT DEPARTMENT - FORM 23
        CERTIFICATE OF REGISTRATION
        REGISTRATION NUMBER: MH12AB1234
        OWNER NAME: RAHUL RAMESH SHARMA
        REGISTRATION DATE: 12/04/2021
        ENGINE NUMBER: K12MN1234567
        CHASSIS NUMBER: MA3ERB12S00123456
        MAKER: MARUTI SUZUKI INDIA LTD
        MODEL: SWIFT VXI
        FUEL TYPE: PETROL
        CLASS OF VEHICLE: MOTOR CAR (LMV)
        CUBIC CAPACITY: 1197 CC
        SEATING CAPACITY: 5
        COLOUR: PEARL ARCTIC WHITE
        INSURANCE: ICICI LOMBARD MOTOR POLICY 2024
        PUC UPTO: 15/04/2025
      ''';

      final fields = DocumentFieldExtractor.extractFields(
        fullText: rcText,
        documentType: 'Vehicle RC Book',
      );

      final map = {for (var f in fields) f.fieldName: f.value};

      // Verify all 14 required fields
      expect(map['Registration Number'], 'MH12AB1234');
      expect(map['Owner Name'], 'RAHUL RAMESH SHARMA');
      expect(map['Registration Date'], '12/04/2021');
      expect(map['Engine Number'], 'K12MN1234567');
      expect(map['Chassis Number'], 'MA3ERB12S00123456');
      expect(map['Maker / Manufacturer'], 'MARUTI SUZUKI INDIA LTD');
      expect(map['Model Name'], 'SWIFT VXI');
      expect(map['Fuel Type'], 'PETROL');
      expect(map['Vehicle Class'], contains('MOTOR CAR'));
      expect(map['Cubic Capacity (CC)'], contains('1197'));
      expect(map['Seating Capacity'], '5');
      expect(map['Color'], 'PEARL ARCTIC WHITE');
      expect(map['Insurance Details'], contains('ICICI LOMBARD'));
      expect(map['PUC Validity'], '15/04/2025');
    });
  });
}

extension on KeyManagementService {
  Future<SecretKey> deriveKeyFromPinForTest(String pin, List<int> salt) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: AppConstants.pbkdf2Iterations,
      bits: 256,
    );
    return await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(pin)),
      nonce: salt,
    );
  }
}
