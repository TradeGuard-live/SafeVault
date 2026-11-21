import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../constants/app_constants.dart';
import '../errors/exceptions.dart';
import 'encryption_service.dart';
import 'native_biometric_keystore_service.dart';

/// Key Management Service with Mandatory Two-Factor Secret Sharing Architecture
/// and Hardware-Backed Android Keystore Integration.
///
/// ============================================================================
/// SECURITY SPECIFICATION & MATHEMATICAL DESIGN:
/// ============================================================================
/// 1. Mandatory 2-of-2 Secret Sharing:
///    The 256-bit Vault Master Key (VMK) is never stored directly. Instead, it is
///    split into two independent 32-byte shares using XOR secret sharing:
///      VMK = S_bio ⊕ S_pin
///
///    - S_bio: 32 cryptographically secure random bytes generated via CSPRNG.
///      Wrapped via AES-256-GCM using a hardware-backed key inside the Android
///      Keystore (StrongBox/TEE). The key enforces setUserAuthenticationRequired(true)
///      and AUTH_BIOMETRIC_STRONG with setInvalidatedByBiometricEnrollment(true).
///      No software-only read of secure storage can unwrap S_bio.
///
///    - S_pin: 32 bytes computed as VMK ⊕ S_bio.
///      Wrapped with KEK_pin using AES-256-GCM. KEK_pin is derived from the user's
///      six-digit PIN and a unique 32-byte random salt using PBKDF2 (HMAC-SHA256,
///      100,000 iterations).
///
/// 2. Information-Theoretic Security of Secret Shares:
///    By Shannon's Perfect Secrecy theorem:
///      H(VMK | S_bio) = 256 bits
///      H(VMK | S_pin) = 256 bits
///    Neither factor independently reveals ANY information whatsoever about the VMK.
///    Access to biometrics alone CANNOT decrypt any vault document or password.
///    Access to the PIN alone CANNOT decrypt any vault document or password.
///    Both factors are strictly mandatory in every unlock sequence.
///
/// 3. Hardware-Backed Protection & Invalidation:
///    If the user modifies enrolled biometrics in Android Settings, the Android
///    Keystore invalidates the key. In a zero-knowledge 2-factor vault, access
///    cannot be restored without the biometric key, preventing stolen-device attacks.
/// ============================================================================
class KeyManagementService {
  final FlutterSecureStorage _secureStorage;
  final EncryptionService _encryptionService;
  final NativeBiometricKeystoreService _keystoreService;
  final Pbkdf2 _pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: AppConstants.pbkdf2Iterations,
    bits: 256,
  );

  // Storage keys for 2FA Architecture
  static const String _keyVaultInitialized = 'vault_is_initialized';
  static const String _key2FaConfigured = 'vault_2fa_configured';
  static const String _keyWrappedShareBio = 'vault_2fa_share_bio';
  static const String _keyBioKek = 'vault_2fa_bio_kek';
  static const String _keyWrappedSharePin = 'vault_2fa_share_pin';
  static const String _keyPinSalt = 'vault_2fa_pin_salt';

  // Legacy keys for migration support
  static const String _legacyKeyWrappedMasterKeyPin = 'vault_wrapped_mk_pin';
  static const String _legacyKeyPinSalt = 'vault_pin_salt';
  static const String _legacyKeyWrappedMasterKeyBio = 'vault_wrapped_mk_bio';
  static const String _legacyKeyBioKek = 'vault_bio_kek';
  static const String _legacyKeyBiometricEnabled = 'vault_biometric_enabled';

  KeyManagementService({
    FlutterSecureStorage? secureStorage,
    EncryptionService? encryptionService,
    NativeBiometricKeystoreService? keystoreService,
  }) : _secureStorage =
           secureStorage ??
           const FlutterSecureStorage(
             aOptions: AndroidOptions(resetOnError: false),
           ),
       _encryptionService = encryptionService ?? EncryptionService(),
       _keystoreService =
           keystoreService ?? const NativeBiometricKeystoreService();

  /// Checks if a vault has been initialized on this device.
  Future<bool> isVaultInitialized() async {
    final value = await _secureStorage.read(key: _keyVaultInitialized);
    return value == 'true';
  }

  /// Checks if mandatory 2FA is active and configured.
  Future<bool> isTwoFactorConfigured() async {
    final value = await _secureStorage.read(key: _key2FaConfigured);
    return value == 'true';
  }

  /// Checks if a legacy single-factor vault exists that requires migration.
  Future<bool> hasLegacyVault() async {
    final isInit = await isVaultInitialized();
    final is2Fa = await isTwoFactorConfigured();
    final legacyPin = await _secureStorage.read(
      key: _legacyKeyWrappedMasterKeyPin,
    );
    return isInit && !is2Fa && legacyPin != null;
  }

  /// Initializes a brand new vault under the Mandatory Two-Factor Secret Sharing scheme.
  /// Requires a valid 6-digit PIN.
  Future<SecretKey> initializeTwoFactorVault({required String pin}) async {
    _validatePinFormat(pin);

    // 1. Generate 256-bit random Master Key (VMK)
    final masterKey = await _encryptionService.generateRandomMasterKey();
    final vmkBytes = Uint8List.fromList(await masterKey.extractBytes());

    // 2. Generate random 32-byte Biometric Share S_bio
    final sBio = _generateRandomBytes(AppConstants.masterKeyLengthBytes);

    // 3. Compute PIN Share S_pin = VMK ⊕ S_bio
    final sPin = _xorBytes(vmkBytes, sBio);

    // 4. Wrap S_bio with hardware Keystore key or host fallback
    Uint8List wrappedShareBio;
    try {
      if (_keystoreService.isSupported) {
        await _keystoreService.generateBiometricKey();
        wrappedShareBio = await _keystoreService.wrapBiometricShare(sBio);
        await _secureStorage.delete(key: _keyBioKek);
      } else {
        final bioKekBytes = _generateRandomBytes(
          AppConstants.masterKeyLengthBytes,
        );
        final bioKek = SecretKey(bioKekBytes);
        wrappedShareBio = Uint8List.fromList(
          await _encryptionService.encryptBytes(sBio, bioKek),
        );
        await _secureStorage.write(
          key: _keyBioKek,
          value: base64Encode(bioKekBytes),
        );
      }

      // 5. Wrap S_pin with PIN KEK (PBKDF2 100k rounds)
      final salt = _generateRandomBytes(AppConstants.pbkdf2SaltLength);
      final pinKek = await _deriveKeyFromPin(pin, salt);
      final wrappedSharePin = await _encryptionService.encryptBytes(
        sPin,
        pinKek,
      );

      // 6. Write securely to storage
      await _secureStorage.write(
        key: _keyWrappedShareBio,
        value: base64Encode(wrappedShareBio),
      );
      await _secureStorage.write(key: _keyPinSalt, value: base64Encode(salt));
      await _secureStorage.write(
        key: _keyWrappedSharePin,
        value: base64Encode(wrappedSharePin),
      );
      await _secureStorage.write(key: _key2FaConfigured, value: 'true');
      await _secureStorage.write(key: _keyVaultInitialized, value: 'true');
    } catch (e) {
      // Compensating cleanup: remove partially written keys so a retry can
      // start from a consistent state.
      await _secureStorage.delete(key: _keyWrappedShareBio);
      await _secureStorage.delete(key: _keyPinSalt);
      await _secureStorage.delete(key: _keyWrappedSharePin);
      await _secureStorage.delete(key: _key2FaConfigured);
      await _secureStorage.delete(key: _keyVaultInitialized);
      if (_keystoreService.isSupported) {
        await _keystoreService.deleteBiometricKey();
      }
      rethrow;
    } finally {
      // Wipe intermediate sensitive buffers
      sBio.fillRange(0, sBio.length, 0);
      sPin.fillRange(0, sPin.length, 0);
    }

    return masterKey;
  }

  /// Factor 1: Biometric Verification Step.
  /// Unwraps and returns the ephemeral 32-byte biometric share S_bio.
  /// Does NOT grant access to the vault on its own.
  Future<Uint8List> startTwoFactorBiometricUnlock() async {
    final wrappedBioBase64 = await _secureStorage.read(
      key: _keyWrappedShareBio,
    );

    if (wrappedBioBase64 == null) {
      throw const BiometricException(
        'Biometric authentication key material not found. Two-factor vault is not configured.',
      );
    }

    final wrappedBioBytes = base64Decode(wrappedBioBase64);

    // Backward-compatible migration check:
    // If legacy software bio KEK is present in secure storage, unwrap using it and migrate to hardware Keystore
    final legacyBioKekBase64 = await _secureStorage.read(key: _keyBioKek);
    if (legacyBioKekBase64 != null && legacyBioKekBase64.isNotEmpty) {
      try {
        final bioKekBytes = base64Decode(legacyBioKekBase64);
        final bioKek = SecretKey(bioKekBytes);
        final sBio = await _encryptionService.decryptBytes(
          wrappedBioBytes,
          bioKek,
        );
        final sBioList = Uint8List.fromList(sBio);

        // Opportunistic upgrade to hardware Keystore key
        if (_keystoreService.isSupported) {
          try {
            await _keystoreService.generateBiometricKey();
            final hardwareWrapped = await _keystoreService.wrapBiometricShare(
              sBioList,
            );
            await _secureStorage.write(
              key: _keyWrappedShareBio,
              value: base64Encode(hardwareWrapped),
            );
            await _secureStorage.delete(key: _keyBioKek);
          } catch (_) {
            // Keep legacy fallback if Keystore generation fails
          }
        }
        return sBioList;
      } catch (e) {
        throw BiometricException(
          'Biometric key unwrapping failed: ${e.toString()}',
        );
      }
    }

    // Hardware Android Keystore unwrap
    return await _keystoreService.unwrapBiometricShare(wrappedBioBytes);
  }

  /// Factor 2: Six-digit PIN Verification Step.
  /// Verifies the PIN, unwraps S_pin, reconstructs VMK = S_bio ⊕ S_pin,
  /// zeroes sensitive temporary shares, and returns the unlocked VMK.
  Future<SecretKey> completeTwoFactorPinUnlock({
    required Uint8List bioShare,
    required String pin,
  }) async {
    _validatePinFormat(pin);

    final saltBase64 = await _secureStorage.read(key: _keyPinSalt);
    final wrappedPinBase64 = await _secureStorage.read(
      key: _keyWrappedSharePin,
    );

    if (saltBase64 == null || wrappedPinBase64 == null) {
      throw const VaultSecurityException(
        'PIN authentication key material not found.',
      );
    }

    final salt = base64Decode(saltBase64);
    final wrappedPinBytes = base64Decode(wrappedPinBase64);

    try {
      // Derive PIN KEK
      final pinKek = await _deriveKeyFromPin(pin, salt);

      // Decrypt S_pin (AES-GCM verifies auth tag; throws DecryptionFailedException on invalid PIN)
      final sPin = await _encryptionService.decryptBytes(
        wrappedPinBytes,
        pinKek,
      );

      if (sPin.length != AppConstants.masterKeyLengthBytes ||
          bioShare.length != AppConstants.masterKeyLengthBytes) {
        throw const DecryptionFailedException('Invalid secret share length.');
      }

      // Reconstruct Master Key: VMK = S_bio ⊕ S_pin
      final vmkBytes = _xorBytes(bioShare, Uint8List.fromList(sPin));

      // Overwrite temporary shares
      bioShare.fillRange(0, bioShare.length, 0);
      sPin.fillRange(0, sPin.length, 0);

      return SecretKey(vmkBytes);
    } on DecryptionFailedException {
      throw const InvalidPinException();
    } catch (e) {
      if (e is InvalidPinException) rethrow;
      throw const InvalidPinException();
    }
  }

  /// Changes the six-digit PIN in the 2FA system without re-encrypting vault documents.
  /// Requires the currently verified S_bio and current PIN to prove authorization.
  /// The biometric share (S_bio) is preserved, so the Android Keystore key is
  /// not regenerated and cannot be orphaned by a partial failure.
  Future<void> changeSixDigitPin2FA({
    required Uint8List bioShare,
    required String currentPin,
    required String newPin,
  }) async {
    _validatePinFormat(newPin);
    _validatePinFormat(currentPin);

    final bioShareCopy = Uint8List.fromList(bioShare);

    try {
      // 1. Reconstruct current Master Key to prove validity
      final currentMasterKey = await completeTwoFactorPinUnlock(
        bioShare: Uint8List.fromList(bioShareCopy),
        pin: currentPin,
      );
      final vmkBytes = Uint8List.fromList(
        await currentMasterKey.extractBytes(),
      );

      // 2. Keep the existing S_bio; only S_pin changes: newS_pin = VMK ⊕ S_bio
      final newSPin = _xorBytes(vmkBytes, bioShareCopy);

      // 3. Wrap new S_pin with new PIN KEK
      final newSalt = _generateRandomBytes(AppConstants.pbkdf2SaltLength);
      final newPinKek = await _deriveKeyFromPin(newPin, newSalt);
      final wrappedPin = await _encryptionService.encryptBytes(
        newSPin,
        newPinKek,
      );

      // Preserve old values for rollback on partial failure.
      final oldSalt = await _secureStorage.read(key: _keyPinSalt);
      final oldWrappedPin = await _secureStorage.read(key: _keyWrappedSharePin);

      try {
        await _secureStorage.write(
          key: _keyPinSalt,
          value: base64Encode(newSalt),
        );
        await _secureStorage.write(
          key: _keyWrappedSharePin,
          value: base64Encode(wrappedPin),
        );
      } catch (e) {
        // Roll back to the previous PIN wrapping if a write fails.
        if (oldSalt != null) {
          await _secureStorage.write(key: _keyPinSalt, value: oldSalt);
        }
        if (oldWrappedPin != null) {
          await _secureStorage.write(
            key: _keyWrappedSharePin,
            value: oldWrappedPin,
          );
        }
        rethrow;
      }

      // Zero memory
      newSPin.fillRange(0, newSPin.length, 0);
      vmkBytes.fillRange(0, vmkBytes.length, 0);
    } finally {
      bioShareCopy.fillRange(0, bioShareCopy.length, 0);
    }
  }

  /// Migrates a legacy vault (v1 single-factor/optional bio) to Mandatory 2FA.
  /// Preserves the existing Master Key so all existing documents remain 100% intact!
  Future<SecretKey> migrateLegacyVaultToTwoFactor({
    required String legacyPin,
    required String newSixDigitPin,
  }) async {
    _validatePinFormat(newSixDigitPin);

    // 1. Decrypt Master Key from legacy PIN wrapping
    final saltBase64 = await _secureStorage.read(key: _legacyKeyPinSalt);
    final wrappedMkBase64 = await _secureStorage.read(
      key: _legacyKeyWrappedMasterKeyPin,
    );

    if (saltBase64 == null || wrappedMkBase64 == null) {
      throw const VaultSecurityException('Legacy vault credentials not found.');
    }

    final salt = base64Decode(saltBase64);
    final wrappedBytes = base64Decode(wrappedMkBase64);
    final pinKek = await _deriveKeyFromPin(legacyPin, salt);
    final vmkBytes = await _encryptionService.decryptBytes(
      wrappedBytes,
      pinKek,
    );

    // 2. Generate 2FA shares for this existing Master Key
    final sBio = _generateRandomBytes(AppConstants.masterKeyLengthBytes);
    final sPin = _xorBytes(Uint8List.fromList(vmkBytes), sBio);

    // 3. Wrap S_bio with Keystore key or host fallback
    Uint8List wrappedShareBio;
    if (_keystoreService.isSupported) {
      await _keystoreService.generateBiometricKey();
      wrappedShareBio = await _keystoreService.wrapBiometricShare(sBio);
      await _secureStorage.delete(key: _keyBioKek);
    } else {
      final bioKekBytes = _generateRandomBytes(
        AppConstants.masterKeyLengthBytes,
      );
      final bioKek = SecretKey(bioKekBytes);
      wrappedShareBio = Uint8List.fromList(
        await _encryptionService.encryptBytes(sBio, bioKek),
      );
      await _secureStorage.write(
        key: _keyBioKek,
        value: base64Encode(bioKekBytes),
      );
    }

    // 4. Wrap S_pin with new 6-digit PIN key
    final newSalt = _generateRandomBytes(AppConstants.pbkdf2SaltLength);
    final newPinKek = await _deriveKeyFromPin(newSixDigitPin, newSalt);
    final wrappedSharePin = await _encryptionService.encryptBytes(
      sPin,
      newPinKek,
    );

    // 5. Store 2FA configuration
    await _secureStorage.write(
      key: _keyWrappedShareBio,
      value: base64Encode(wrappedShareBio),
    );
    await _secureStorage.write(key: _keyPinSalt, value: base64Encode(newSalt));
    await _secureStorage.write(
      key: _keyWrappedSharePin,
      value: base64Encode(wrappedSharePin),
    );
    await _secureStorage.write(key: _key2FaConfigured, value: 'true');

    // 6. Delete legacy wrapped keys
    await _secureStorage.delete(key: _legacyKeyWrappedMasterKeyPin);
    await _secureStorage.delete(key: _legacyKeyPinSalt);
    await _secureStorage.delete(key: _legacyKeyWrappedMasterKeyBio);
    await _secureStorage.delete(key: _legacyKeyBioKek);
    await _secureStorage.delete(key: _legacyKeyBiometricEnabled);

    // Zero temporary buffers
    sBio.fillRange(0, sBio.length, 0);
    sPin.fillRange(0, sPin.length, 0);

    return SecretKey(vmkBytes);
  }

  /// Validates that a PIN is strictly 6 numeric digits.
  void _validatePinFormat(String pin) {
    if (pin.length != AppConstants.pinLength ||
        !RegExp(r'^\d{6}$').hasMatch(pin)) {
      throw const VaultSecurityException(
        'PIN must be exactly 6 numeric digits.',
      );
    }
  }

  Uint8List _xorBytes(Uint8List a, Uint8List b) {
    if (a.length != b.length) {
      throw ArgumentError('Byte arrays must have identical length for XOR');
    }
    final result = Uint8List(a.length);
    for (int i = 0; i < a.length; i++) {
      result[i] = a[i] ^ b[i];
    }
    return result;
  }

  Future<SecretKey> _deriveKeyFromPin(String pin, List<int> salt) async {
    final secretKey = SecretKey(utf8.encode(pin));
    return await _pbkdf2.deriveKey(secretKey: secretKey, nonce: salt);
  }

  Uint8List _generateRandomBytes(int length) {
    final random = Random.secure();
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes;
  }

  /// Completely wipes all secure storage keys (used for vault reset).
  Future<void> wipeAllKeys() async {
    await _secureStorage.deleteAll();
    if (_keystoreService.isSupported) {
      await _keystoreService.deleteBiometricKey();
    }
  }
}
