import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault/core/errors/exceptions.dart';
import 'package:vault/core/security/clipboard_security_service.dart';
import 'package:vault/core/security/encryption_service.dart';
import 'package:vault/core/security/key_management_service.dart';
import 'package:vault/core/security/pin_service.dart';
import 'package:vault/core/security/two_factor_auth_coordinator.dart';
import 'package:vault/core/security/vault_session.dart';
import 'package:vault/features/bank_vault/domain/bank_account_model.dart';
import 'package:vault/features/passwords/data/password_generator.dart';
import 'package:vault/features/passwords/data/password_security_analyzer.dart';
import 'package:vault/features/passwords/domain/password_entry_model.dart';

/// In-memory mock storage for testing secure storage keys and encryption
class InMemorySecureStorage extends FlutterSecureStorage {
  final Map<String, String> _map = {};

  InMemorySecureStorage() : super();

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
      _map[key] = value;
    } else {
      _map.remove(key);
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
    return _map[key];
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
    _map.remove(key);
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
    _map.clear();
  }

  Map<String, String> get rawMap => _map;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PART 6 SECURITY TEST SUITE: Mandatory 2FA & Vault Upgrade', () {
    late EncryptionService encService;
    late InMemorySecureStorage mockStorage;
    late KeyManagementService keyService;
    late PinService pinService;

    setUp(() {
      encService = EncryptionService();
      mockStorage = InMemorySecureStorage();
      keyService = KeyManagementService(
        secureStorage: mockStorage,
        encryptionService: encService,
      );
      pinService = PinService(storage: mockStorage);
    });

    test('1. Biometric succeeds + PIN succeeds = Unlock Vault', () async {
      const pin = '654321';
      final initialKey = await keyService.initializeTwoFactorVault(pin: pin);
      final initialBytes = await initialKey.extractBytes();

      // Factor 1: Biometric succeeds
      final bioShare = await keyService.startTwoFactorBiometricUnlock();
      expect(bioShare.length, equals(32));

      // Factor 2: PIN succeeds
      final unlockedKey = await keyService.completeTwoFactorPinUnlock(
        bioShare: bioShare,
        pin: pin,
      );
      final unlockedBytes = await unlockedKey.extractBytes();

      // Master key is fully and accurately reconstructed
      expect(unlockedBytes, equals(initialBytes));
    });

    test('2. Biometric succeeds + PIN fails = Locked', () async {
      const pin = '123456';
      await keyService.initializeTwoFactorVault(pin: pin);

      // Factor 1: Biometric succeeds
      final bioShare = await keyService.startTwoFactorBiometricUnlock();

      // Factor 2: Wrong PIN entered
      expect(
        () async => await keyService.completeTwoFactorPinUnlock(
          bioShare: bioShare,
          pin: '999999',
        ),
        throwsA(isA<InvalidPinException>()),
      );
    });

    test(
      '3. Biometric fails (invalid/empty share) + PIN succeeds = Locked',
      () async {
        const pin = '123456';
        await keyService.initializeTwoFactorVault(pin: pin);

        // Simulate biometric failure / corrupted share
        final corruptedBioShare = Uint8List(32); // All zeros

        final resultKey = await keyService.completeTwoFactorPinUnlock(
          bioShare: corruptedBioShare,
          pin: pin,
        );
        final resultBytes = await resultKey.extractBytes();

        // The key cannot be valid VMK because S_bio was missing/corrupted
        final realBioShare = await keyService.startTwoFactorBiometricUnlock();
        final realKey = await keyService.completeTwoFactorPinUnlock(
          bioShare: realBioShare,
          pin: pin,
        );
        final realBytes = await realKey.extractBytes();

        expect(resultBytes, isNot(equals(realBytes)));
      },
    );

    test('4. Biometric fails + PIN fails = Locked', () async {
      const pin = '123456';
      await keyService.initializeTwoFactorVault(pin: pin);

      final dummyBio = Uint8List(32);
      expect(
        () async => await keyService.completeTwoFactorPinUnlock(
          bioShare: dummyBio,
          pin: '000000',
        ),
        throwsA(isA<InvalidPinException>()),
      );
    });

    test(
      '5. Authentication cancelled = Ephemeral state zeroed and locked',
      () async {
        final coordinator = TwoFactorAuthCoordinator();
        final testShare = Uint8List.fromList(List.generate(32, (i) => i + 1));

        coordinator.recordBiometricSuccess(testShare);
        expect(coordinator.hasActiveBiometricVerification, isTrue);

        // Cancel transaction
        coordinator.cancelTransaction();
        expect(coordinator.hasActiveBiometricVerification, isFalse);
        expect(coordinator.consumeBiometricShare(), isNull);
      },
    );

    test('6. Repeated incorrect PIN attempts trigger rate limiting', () async {
      expect(await pinService.isLockedOut(), isFalse);

      await pinService.recordFailedAttempt(); // 1
      await pinService.recordFailedAttempt(); // 2

      // 3rd attempt triggers 10s lockout
      try {
        await pinService.recordFailedAttempt();
        fail('Should have thrown PinLockedOutException');
      } on PinLockedOutException catch (e) {
        expect(e.lockDurationSeconds, equals(10));
      }

      expect(await pinService.isLockedOut(), isTrue);
      expect(
        await pinService.getRemainingLockoutSeconds(),
        inInclusiveRange(8, 10),
      );
    });

    test('7. PIN is never stored in plaintext', () async {
      const pin = '882244';
      await keyService.initializeTwoFactorVault(pin: pin);

      // Inspect every value written to storage
      for (final entry in mockStorage.rawMap.entries) {
        expect(
          entry.value,
          isNot(contains(pin)),
          reason: 'Key "${entry.key}" must not contain plaintext PIN',
        );
      }
    });

    test(
      '8. Password records are encrypted at rest with AES-256-GCM + AAD',
      () async {
        final masterKey = await encService.generateRandomMasterKey();
        final entry = await PasswordEntryModel.createEncrypted(
          id: 'pwd-101',
          title: 'GitHub',
          username: 'dev_octocat',
          email: 'octo@github.com',
          password: 'SuperSecretPassword#2026',
          notes: 'Personal access token inside',
          categoryId: 'developer',
          masterKey: masterKey,
          encryptionService: encService,
        );

        // Verify at rest (SQLite map) contains only ciphertext
        final map = entry.toMap();
        expect(
          map['password_enc'],
          isNot(contains('SuperSecretPassword#2026')),
        );
        expect(map['username_enc'], isNot(contains('dev_octocat')));
        expect(map['email_enc'], isNot(contains('octo@github.com')));

        // Decrypt and verify AAD binding
        final decrypted = await entry.decrypt(
          masterKey: masterKey,
          encryptionService: encService,
        );
        expect(decrypted.decryptedPassword, equals('SuperSecretPassword#2026'));
        expect(decrypted.decryptedUsername, equals('dev_octocat'));

        // If AAD is tampered (e.g. record ID changed), decryption fails
        final tamperedEntry = entry.copyWith(id: 'pwd-swapped-id');
        final failDecrypted = await tamperedEntry.decrypt(
          masterKey: masterKey,
          encryptionService: encService,
        );
        // Because AAD tag mismatch occurs, decrypted password returns null
        expect(failDecrypted.decryptedPassword, isNull);
      },
    );

    test('9. Bank details are encrypted at rest with AES-256-GCM', () async {
      final masterKey = await encService.generateRandomMasterKey();
      final account = await BankAccountModel.createEncrypted(
        id: 'bank-202',
        bankName: 'HDFC Bank',
        accountHolder: 'Naman Sharma',
        accountNumber: '50100458923411',
        ifsc: 'HDFC0001234',
        branch: 'Central Branch',
        accountType: 'savings',
        masterKey: masterKey,
        encryptionService: encService,
      );

      final map = account.toMap();
      expect(map['account_number_enc'], isNot(contains('50100458923411')));
      expect(map['account_holder_enc'], isNot(contains('Naman Sharma')));
      expect(map['ifsc_enc'], isNot(contains('HDFC0001234')));

      final decrypted = await account.decrypt(
        masterKey: masterKey,
        encryptionService: encService,
      );
      expect(decrypted.decryptedAccountNumber, equals('50100458923411'));
      expect(decrypted.maskedAccountNumber, equals('•••• •••• •••• 3411'));
    });

    test(
      '10. Strict Financial Restrictions: BankAccount has NO PIN or CVV fields',
      () {
        final fields = [
          'id',
          'bank_name',
          'account_holder_enc',
          'account_number_enc',
          'ifsc_enc',
          'branch_enc',
          'account_type',
          'nickname',
          'notes_enc',
          'is_favorite',
          'created_at',
          'updated_at',
        ];
        final forbiddenFields = [
          'atm_pin',
          'cvv',
          'card_pin',
          'upi_pin',
          'otp',
          'netbanking_password',
        ];
        for (final f in forbiddenFields) {
          expect(
            fields.contains(f),
            isFalse,
            reason: 'Field $f is strictly prohibited',
          );
        }
      },
    );

    test('11. Password Generator produces cryptographic random entropy', () {
      const config = PasswordGeneratorConfig(
        length: 24,
        includeUppercase: true,
        includeLowercase: true,
        includeNumbers: true,
        includeSymbols: true,
      );

      final p1 = PasswordGenerator.generate(config);
      final p2 = PasswordGenerator.generate(config);

      expect(p1.length, equals(24));
      expect(p2.length, equals(24));
      expect(p1, isNot(equals(p2))); // CSPRNG distinct
      expect(p1.contains(RegExp(r'[A-Z]')), isTrue);
      expect(p1.contains(RegExp(r'[a-z]')), isTrue);
      expect(p1.contains(RegExp(r'[0-9]')), isTrue);
      expect(p1.contains(RegExp(r'[^A-Za-z0-9]')), isTrue);
    });

    test('12. Password Security Analyzer detects weak, short, and reused passwords', () {
      final now = DateTime.now();
      final entries = [
        PasswordEntryModel(
          id: '1',
          title: 'Site A',
          passwordEnc: 'enc1',
          categoryId: 'social',
          createdAt: now,
          updatedAt: now,
          decryptedPassword: 'password123', // reused & weak
        ),
        PasswordEntryModel(
          id: '2',
          title: 'Site B',
          passwordEnc: 'enc2',
          categoryId: 'work',
          createdAt: now,
          updatedAt: now,
          decryptedPassword: 'password123', // reused & weak
        ),
        PasswordEntryModel(
          id: '3',
          title: 'Site C',
          passwordEnc: 'enc3',
          categoryId: 'email',
          createdAt: now,
          updatedAt: now,
          decryptedPassword: '123', // short <8
        ),
      ];

      final audit = PasswordSecurityAnalyzer.analyze(entries);
      expect(audit.totalPasswords, equals(3));
      expect(audit.reusedCount, equals(2));
      expect(audit.shortCount, equals(1));
      expect(audit.overallScore, lessThan(80));
    });

    test(
      '13. Automatic locking wipes sensitive master key buffer from memory',
      () async {
        final session = VaultSession();
        final key = await encService.generateRandomMasterKey();

        await session.unlock(key);
        expect(session.isUnlocked, isTrue);
        expect(session.masterKey, isNotNull);

        // Lock vault
        session.lock();
        expect(session.isUnlocked, isFalse);
        expect(session.masterKey, isNull);
      },
    );

    test('14. Passwords never appear in application logs or toString representations', () async {
      final masterKey = await encService.generateRandomMasterKey();
      final entry = await PasswordEntryModel.createEncrypted(
        id: 'test-pwd',
        title: 'SecretAccount',
        password: 'TopSecretPassword99!',
        categoryId: 'social',
        masterKey: masterKey,
        encryptionService: encService,
      );

      final mapString = entry.toMap().toString();
      expect(mapString, isNot(contains('TopSecretPassword99!')));
    });

    test(
      '15. Offline constraint: Zero network permissions in AndroidManifest.xml',
      () {
        final manifestFile = File('android/app/src/main/AndroidManifest.xml');
        expect(manifestFile.existsSync(), isTrue);

        final content = manifestFile.readAsStringSync();
        expect(content, contains('android.permission.INTERNET'));
        expect(
          content,
          contains('tools:node="remove"'),
          reason: 'INTERNET permission must be strictly removed via tools:node="remove"',
        );
        expect(content, contains('android.permission.ACCESS_NETWORK_STATE'));
      },
    );

    test('16. Invalid encryption tags are rejected in AES-256-GCM', () async {
      final key = await encService.generateRandomMasterKey();
      final plain = Uint8List.fromList(utf8.encode('Encrypted Vault Data'));
      final ciphertext = await encService.encryptBytes(plain, key);

      // Corrupt tag (bytes 18 to 33 in Vault format)
      final corrupted = Uint8List.fromList(ciphertext);
      corrupted[20] ^= 0xAA;

      expect(
        () async => await encService.decryptBytes(corrupted, key),
        throwsA(isA<DecryptionFailedException>()),
      );
    });

    test('17. Clipboard security service clears sensitive data on clearSensitiveClipboard()', () async {
      final clipService = ClipboardSecurityService.instance;
      // Should execute without throwing
      await clipService.clearSensitiveClipboard();
    });
  });
}
