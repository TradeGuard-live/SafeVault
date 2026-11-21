import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../errors/exceptions.dart';

/// Service interfacing directly with the hardware-backed Android Keystore
/// via native method channel `com.vault.security/keystore_biometric`.
///
/// Features:
/// - AES-256-GCM hardware key generation with `setUserAuthenticationRequired(true)`.
/// - Strong biometric authentication requirement (`AUTH_BIOMETRIC_STRONG`).
/// - Key invalidation on biometric enrollment changes (`setInvalidatedByBiometricEnrollment(true)`).
/// - Wrapped secret share handling with zero software-only KEK persistence.
class NativeBiometricKeystoreService {
  static const MethodChannel _defaultChannel = MethodChannel(
    'com.vault.security/keystore_biometric',
  );

  final MethodChannel _channel;

  const NativeBiometricKeystoreService({MethodChannel? channel})
    : _channel = channel ?? _defaultChannel;

  /// Returns whether the current runtime environment is Android and supports Keystore
  bool get isSupported => Platform.isAndroid;

  /// Generates or re-generates the hardware-backed biometric key in Android Keystore
  Future<bool> generateBiometricKey() async {
    if (!isSupported) return true;
    try {
      final success = await _channel.invokeMethod<bool>('generateBiometricKey');
      return success ?? false;
    } on PlatformException catch (e) {
      throw BiometricException(
        'Failed to generate Keystore biometric key: ${e.message}',
      );
    } catch (_) {
      return false;
    }
  }

  /// Wraps (encrypts) the 32-byte S_bio share using the Android Keystore hardware key
  Future<Uint8List> wrapBiometricShare(Uint8List shareBytes) async {
    if (!isSupported) return shareBytes;
    try {
      final result = await _channel.invokeMethod<Uint8List>(
        'wrapBiometricShare',
        {'shareBytes': shareBytes},
      );
      if (result == null || result.isEmpty) {
        throw const BiometricException(
          'Hardware Keystore failed to wrap biometric share.',
        );
      }
      return result;
    } on PlatformException catch (e) {
      throw BiometricException(
        'Hardware Keystore wrap error: ${e.message ?? e.code}',
      );
    }
  }

  /// Unwraps (decrypts) the S_bio share.
  /// Hardware Keystore enforces that the user must have authenticated biometrically
  /// within the validity window.
  Future<Uint8List> unwrapBiometricShare(Uint8List wrappedBytes) async {
    if (!isSupported) return wrappedBytes;
    try {
      final result = await _channel.invokeMethod<Uint8List>(
        'unwrapBiometricShare',
        {'wrappedBytes': wrappedBytes},
      );
      if (result == null || result.isEmpty) {
        throw const BiometricException(
          'Hardware Keystore failed to unwrap biometric share.',
        );
      }
      return result;
    } on PlatformException catch (e) {
      if (e.code == 'KEY_PERMANENTLY_INVALIDATED') {
        throw const BiometricEnrollmentChangedException();
      } else if (e.code == 'USER_NOT_AUTHENTICATED') {
        throw const BiometricException(
          'Biometric authentication required before accessing key material.',
        );
      }
      throw BiometricException(
        'Hardware Keystore unwrap failed: ${e.message ?? e.code}',
      );
    }
  }

  /// Checks if the hardware Keystore key exists in AndroidKeyStore
  Future<bool> isKeystoreKeyAvailable() async {
    if (!isSupported) return true;
    try {
      final available = await _channel.invokeMethod<bool>(
        'isKeystoreKeyAvailable',
      );
      return available ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Deletes the hardware Keystore key
  Future<bool> deleteBiometricKey() async {
    if (!isSupported) return true;
    try {
      final deleted = await _channel.invokeMethod<bool>('deleteBiometricKey');
      return deleted ?? false;
    } catch (_) {
      return false;
    }
  }
}
