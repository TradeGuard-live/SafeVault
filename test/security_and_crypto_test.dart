import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault/core/errors/exceptions.dart';
import 'package:vault/core/security/encryption_service.dart';
import 'package:vault/core/security/pin_service.dart';
import 'package:vault/core/utils/date_formatter.dart';
import 'package:vault/core/utils/masked_text_formatter.dart';

void main() {
  group('Security & AES-256-GCM Encryption Tests', () {
    late EncryptionService encryptionService;

    setUp(() {
      encryptionService = EncryptionService();
    });

    test('Encrypt and decrypt roundtrip matches original plaintext', () async {
      final key = await encryptionService.generateRandomMasterKey();
      final originalData = utf8.encode('Top Secret Vault Document Contents 2026');
      final plainBytes = Uint8List.fromList(originalData);

      final encrypted = await encryptionService.encryptBytes(plainBytes, key);
      expect(encrypted, isNot(equals(plainBytes)));
      expect(encrypted.length, greaterThan(plainBytes.length));

      final decrypted = await encryptionService.decryptBytes(encrypted, key);
      expect(decrypted, equals(plainBytes));
      expect(utf8.decode(decrypted), equals('Top Secret Vault Document Contents 2026'));
    });

    test('Decryption fails when wrong key is provided', () async {
      final keyA = await encryptionService.generateRandomMasterKey();
      final keyB = await encryptionService.generateRandomMasterKey();

      final plainBytes = Uint8List.fromList(utf8.encode('Sensitive Data'));
      final encrypted = await encryptionService.encryptBytes(plainBytes, keyA);

      expect(
        () async => await encryptionService.decryptBytes(encrypted, keyB),
        throwsA(isA<DecryptionFailedException>()),
      );
    });

    test('Decryption fails with FileCorruptedException or DecryptionFailedException when payload is tampered', () async {
      final key = await encryptionService.generateRandomMasterKey();
      final plainBytes = Uint8List.fromList(utf8.encode('Protected Information'));

      final encrypted = await encryptionService.encryptBytes(plainBytes, key);
      final tampered = Uint8List.fromList(encrypted);
      // Tamper ciphertext byte near the end
      tampered[tampered.length - 2] ^= 0xFF;

      expect(
        () async => await encryptionService.decryptBytes(tampered, key),
        throwsA(isA<DecryptionFailedException>()),
      );
    });

    test('Decryption detects invalid header magic bytes', () async {
      final key = await encryptionService.generateRandomMasterKey();
      final plainBytes = Uint8List.fromList(utf8.encode('Header verification'));

      final encrypted = await encryptionService.encryptBytes(plainBytes, key);
      final corruptedHeader = Uint8List.fromList(encrypted);
      corruptedHeader[0] = 0x00; // corrupt first magic byte

      expect(
        () async => await encryptionService.decryptBytes(corruptedHeader, key),
        throwsA(isA<FileCorruptedException>()),
      );
    });

    test('String encryption and decryption roundtrip', () async {
      final key = await encryptionService.generateRandomMasterKey();
      const rawString = 'PAN: ABCDE1234F, Aadhaar: 1234 5678 9012';

      final encryptedBase64 = await encryptionService.encryptString(rawString, key);
      final decrypted = await encryptionService.decryptString(encryptedBase64, key);

      expect(decrypted, equals(rawString));
    });
  });

  group('PIN Validation and Security Tests', () {
    late PinService pinService;

    setUp(() {
      pinService = PinService();
    });

    test('Validates mandatory 6-digit numeric PINs', () {
      expect(pinService.isValidPinFormat('123456'), isTrue);
      expect(pinService.isValidPinFormat('000000'), isTrue);
      expect(pinService.isValidPinFormat('987654'), isTrue);

      expect(pinService.isValidPinFormat('1234'), isFalse); // 4 digits no longer allowed
      expect(pinService.isValidPinFormat('12345'), isFalse); // 5 digits
      expect(pinService.isValidPinFormat('1234567'), isFalse); // 7 digits
      expect(pinService.isValidPinFormat('12a456'), isFalse); // alphanumeric
      expect(pinService.isValidPinFormat(''), isFalse); // empty
    });
  });

  group('Data Masking & Privacy Tests', () {
    test('MaskedTextFormatter masks sensitive document numbers', () {
      expect(
        MaskedTextFormatter.maskDocumentNumber('123456789012'),
        equals('•••• •••• 9012'),
      );
      expect(
        MaskedTextFormatter.maskDocumentNumber('ABCDE1234F'),
        contains('34F'),
      );
      expect(
        MaskedTextFormatter.maskDocumentNumber(null),
        equals('Not Provided'),
      );
    });
  });

  group('Expiry Calculation Tests', () {
    test('Calculates days remaining correctly', () {
      final now = DateTime.now();
      final futureDate = now.add(const Duration(days: 15));
      final pastDate = now.subtract(const Duration(days: 5));

      final daysLeft = DateFormatter.daysRemaining(futureDate);
      expect(daysLeft, inInclusiveRange(14, 16));

      final daysPast = DateFormatter.daysRemaining(pastDate);
      expect(daysPast, lessThan(0));
    });
  });
}

