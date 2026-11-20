import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import '../constants/app_constants.dart';
import '../errors/exceptions.dart';

/// Production-grade AES-256-GCM encryption and decryption service.
/// Uses cryptographically secure random nonces, 128-bit authentication tags,
/// and optional Associated Authenticated Data (AAD) binding.
class EncryptionService {
  final AesGcm _aesGcm = AesGcm.with256bits();

  /// Encrypts raw bytes with AES-256-GCM and prepends the Vault header and nonce.
  /// Format: [MAGIC (5B)] [VERSION (1B)] [NONCE (12B)] [TAG (16B)] [CIPHERTEXT]
  Future<Uint8List> encryptBytes(
    Uint8List plainBytes,
    SecretKey key, {
    List<int> aad = const <int>[],
  }) async {
    try {
      final nonce = _aesGcm.newNonce();
      final secretBox = await _aesGcm.encrypt(
        plainBytes,
        secretKey: key,
        nonce: nonce,
        aad: aad,
      );

      final builder = BytesBuilder(copy: false);
      // 1. Magic bytes ('VAULT')
      builder.add(AppConstants.fileHeaderMagic);
      // 2. Encryption Version (0x01)
      builder.addByte(AppConstants.currentEncryptionVersion);
      // 3. Nonce (12 bytes)
      builder.add(secretBox.nonce);
      // 4. Tag (16 bytes)
      builder.add(secretBox.mac.bytes);
      // 5. Ciphertext
      builder.add(secretBox.cipherText);

      return builder.toBytes();
    } catch (e) {
      throw VaultSecurityException('Failed to encrypt data.', e);
    }
  }

  /// Decrypts raw bytes, authenticating the GCM tag, header, and optional AAD.
  Future<Uint8List> decryptBytes(
    Uint8List encryptedData,
    SecretKey key, {
    List<int> aad = const <int>[],
  }) async {
    const headerLen = 5; // 'VAULT'
    const versionLen = 1; // 0x01
    const nonceLen = AppConstants.gcmNonceLengthBytes; // 12
    const tagLen = AppConstants.gcmTagLengthBytes; // 16
    const minLen = headerLen + versionLen + nonceLen + tagLen;

    if (encryptedData.length < minLen) {
      throw const FileCorruptedException('File size is smaller than minimum encrypted payload.');
    }

    // Verify magic bytes
    for (int i = 0; i < headerLen; i++) {
      if (encryptedData[i] != AppConstants.fileHeaderMagic[i]) {
        throw const FileCorruptedException('Invalid file header or untrusted encrypted file.');
      }
    }

    // Verify version
    final version = encryptedData[headerLen];
    if (version != AppConstants.currentEncryptionVersion) {
      throw FileCorruptedException('Unsupported encryption version: $version');
    }

    final nonce = encryptedData.sublist(
      headerLen + versionLen,
      headerLen + versionLen + nonceLen,
    );
    final macBytes = encryptedData.sublist(
      headerLen + versionLen + nonceLen,
      headerLen + versionLen + nonceLen + tagLen,
    );
    final cipherText = encryptedData.sublist(minLen);

    try {
      final secretBox = SecretBox(
        cipherText,
        nonce: nonce,
        mac: Mac(macBytes),
      );

      final decryptedBytes = await _aesGcm.decrypt(
        secretBox,
        secretKey: key,
        aad: aad,
      );

      return Uint8List.fromList(decryptedBytes);
    } catch (e) {
      throw const DecryptionFailedException();
    }
  }

  /// Encrypts a string and returns a base64 encoded payload with optional AAD.
  Future<String> encryptString(
    String plainText,
    SecretKey key, {
    List<int> aad = const <int>[],
  }) async {
    final bytes = utf8.encode(plainText);
    final encrypted = await encryptBytes(Uint8List.fromList(bytes), key, aad: aad);
    return base64Encode(encrypted);
  }

  /// Decrypts a base64 encoded encrypted string with optional AAD.
  Future<String> decryptString(
    String cipherTextBase64,
    SecretKey key, {
    List<int> aad = const <int>[],
  }) async {
    final bytes = base64Decode(cipherTextBase64);
    final decrypted = await decryptBytes(bytes, key, aad: aad);
    return utf8.decode(decrypted);
  }

  /// Generates a cryptographically secure random 256-bit key.
  Future<SecretKey> generateRandomMasterKey() async {
    return await _aesGcm.newSecretKey();
  }
}
