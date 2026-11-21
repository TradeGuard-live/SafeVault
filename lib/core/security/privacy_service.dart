import 'package:flutter/services.dart';

class PrivacyService {
  static const MethodChannel _channel = MethodChannel(
    'com.vault.security/privacy',
  );

  /// Configures Android FLAG_SECURE to prevent screenshots and hide recent tasks preview.
  static Future<bool> setScreenshotProtection(bool enabled) async {
    try {
      final result = await _channel.invokeMethod<bool>('setSecureFlag', {
        'enabled': enabled,
      });
      return result ?? false;
    } catch (_) {
      // Gracefully no-op on non-Android platforms / tests
      return false;
    }
  }

  /// Checks if FLAG_SECURE is currently active.
  static Future<bool> isScreenshotProtectionEnabled() async {
    try {
      final result = await _channel.invokeMethod<bool>('isSecureFlagEnabled');
      return result ?? true;
    } catch (_) {
      return true;
    }
  }
}
