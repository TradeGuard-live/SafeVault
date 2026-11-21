import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../constants/app_constants.dart';
import '../errors/exceptions.dart';

class PinService {
  final FlutterSecureStorage _storage;

  static const String _keyFailedAttempts = 'vault_failed_pin_attempts';
  static const String _keyLockoutExpiry = 'vault_pin_lockout_expiry';

  PinService({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(resetOnError: false),
          );

  /// Validates format of a user entered PIN (Mandatory 6 numeric digits).
  bool isValidPinFormat(String pin) {
    if (pin.length != AppConstants.pinLength) {
      return false;
    }
    return RegExp(r'^\d{6}$').hasMatch(pin);
  }

  /// Checks if PIN entry is currently locked out due to repeated failures.
  Future<bool> isLockedOut() async {
    final expiryStr = await _storage.read(key: _keyLockoutExpiry);
    if (expiryStr == null) return false;

    final expiryTime = int.tryParse(expiryStr) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    if (now < expiryTime) {
      return true;
    }
    // Expired lockout
    await _storage.delete(key: _keyLockoutExpiry);
    return false;
  }

  /// Returns remaining seconds until lockout expires.
  Future<int> getRemainingLockoutSeconds() async {
    final expiryStr = await _storage.read(key: _keyLockoutExpiry);
    if (expiryStr == null) return 0;

    final expiryTime = int.tryParse(expiryStr) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final remainingMs = expiryTime - now;

    if (remainingMs <= 0) {
      await _storage.delete(key: _keyLockoutExpiry);
      return 0;
    }

    return (remainingMs / 1000).ceil();
  }

  /// Increments failed attempts and applies backoff delay if threshold exceeded.
  Future<int> recordFailedAttempt() async {
    final countStr = await _storage.read(key: _keyFailedAttempts);
    final count = (int.tryParse(countStr ?? '0') ?? 0) + 1;
    await _storage.write(key: _keyFailedAttempts, value: count.toString());

    int lockoutSeconds = 0;
    if (count == 3) {
      lockoutSeconds = 10;
    } else if (count == 4) {
      lockoutSeconds = 30;
    } else if (count == 5) {
      lockoutSeconds = 60;
    } else if (count >= 6) {
      lockoutSeconds = 300; // 5 minutes
    }

    if (lockoutSeconds > 0) {
      final expiry =
          DateTime.now().millisecondsSinceEpoch + (lockoutSeconds * 1000);
      await _storage.write(key: _keyLockoutExpiry, value: expiry.toString());
      throw PinLockedOutException(lockDurationSeconds: lockoutSeconds);
    }

    return count;
  }

  /// Clears failed attempt counters upon successful authentication.
  Future<void> resetFailedAttempts() async {
    await _storage.delete(key: _keyFailedAttempts);
    await _storage.delete(key: _keyLockoutExpiry);
  }

  /// Current failed attempt count.
  Future<int> getFailedAttemptsCount() async {
    final countStr = await _storage.read(key: _keyFailedAttempts);
    return int.tryParse(countStr ?? '0') ?? 0;
  }
}
