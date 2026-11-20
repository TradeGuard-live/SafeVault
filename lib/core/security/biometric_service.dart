import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import '../errors/exceptions.dart';

class BiometricService {
  final LocalAuthentication _localAuth;

  BiometricService({LocalAuthentication? localAuth})
      : _localAuth = localAuth ?? LocalAuthentication();

  /// Checks if hardware is available and supported.
  Future<bool> isBiometricsAvailable() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      return canCheck && isSupported;
    } on PlatformException {
      return false;
    }
  }

  /// Lists available biometric types (fingerprint, face, etc.).
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } on PlatformException {
      return [];
    }
  }

  /// Performs biometric authentication using Android BiometricPrompt.
  Future<bool> authenticate({String reason = 'Authenticate to unlock your Vault'}) async {
    try {
      final available = await isBiometricsAvailable();
      if (!available) {
        throw const BiometricException('Biometrics not available on this device.');
      }

      final biometrics = await getAvailableBiometrics();
      if (biometrics.isEmpty) {
        throw const BiometricException('No biometrics enrolled on this device. Please set up fingerprint or face unlock in Android Settings.');
      }

      final success = await _localAuth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );

      return success;
    } on PlatformException catch (e) {
      if (e.code == 'NotAvailable') {
        throw const BiometricException('Biometric authentication is not available on this device.');
      } else if (e.code == 'NotEnrolled') {
        throw const BiometricException('No biometrics enrolled. In mandatory 2FA mode, biometrics is required as Factor 1.');
      } else if (e.code == 'PasscodeNotSet') {
        throw const BiometricException('Device security is not set up.');
      } else if (e.code == 'LockedOut' || e.code == 'PermanentlyLockedOut') {
        throw const BiometricException('Biometric sensor is locked due to too many attempts. Please wait for sensor timeout.');
      }
      throw BiometricException(e.message ?? 'Biometric authentication failed.');
    }
  }

  /// Stop any active authentication prompt.
  Future<void> cancelAuthentication() async {
    try {
      await _localAuth.stopAuthentication();
    } catch (_) {}
  }
}
