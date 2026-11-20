import 'dart:async';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/widgets.dart';
import 'clipboard_security_service.dart';

enum VaultLockReason {
  manual,
  inactivity,
  background,
}

class VaultSession extends ChangeNotifier {
  SecretKey? _masterKey;
  Uint8List? _ephemeralKeyBuffer;
  DateTime? _lastActivityTime;
  DateTime? _backgroundedTime;
  Timer? _inactivityTimer;

  int _autoLockTimeoutSeconds = 0; // 0 = immediate upon backgrounding

  bool get isUnlocked => _masterKey != null;
  SecretKey? get masterKey => _masterKey;
  int get autoLockTimeoutSeconds => _autoLockTimeoutSeconds;
  DateTime? get lastActivityTime => _lastActivityTime;

  void setAutoLockTimeout(int seconds) {
    _autoLockTimeoutSeconds = seconds;
    _resetInactivityTimer();
    notifyListeners();
  }

  /// Sets the unlocked session with the decrypted master key.
  Future<void> unlock(SecretKey key) async {
    _masterKey = key;
    final bytes = await key.extractBytes();
    _ephemeralKeyBuffer = Uint8List.fromList(bytes);
    _lastActivityTime = DateTime.now();
    _resetInactivityTimer();
    notifyListeners();
  }

  /// Locks the vault session and wipes sensitive key buffers from memory.
  void lock({VaultLockReason reason = VaultLockReason.manual}) {
    _inactivityTimer?.cancel();
    _inactivityTimer = null;

    // Securely clear clipboard
    ClipboardSecurityService.instance.clearSensitiveClipboard();

    // Securely wipe ephemeral key buffer from memory
    if (_ephemeralKeyBuffer != null) {
      _ephemeralKeyBuffer!.fillRange(0, _ephemeralKeyBuffer!.length, 0);
      _ephemeralKeyBuffer = null;
    }

    _masterKey = null;
    _lastActivityTime = null;
    _backgroundedTime = null;

    notifyListeners();
  }

  /// Called on user touch/navigation to keep the session alive.
  void recordUserActivity() {
    if (!isUnlocked) return;
    _lastActivityTime = DateTime.now();
    _resetInactivityTimer();
  }

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    if (_autoLockTimeoutSeconds > 0 && isUnlocked) {
      _inactivityTimer = Timer(
        Duration(seconds: _autoLockTimeoutSeconds),
        () => lock(reason: VaultLockReason.inactivity),
      );
    }
  }

  /// Handles Flutter lifecycle state transitions.
  void handleLifecycleChange(AppLifecycleState state) {
    if (!isUnlocked) return;

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      if (_autoLockTimeoutSeconds == 0) {
        lock(reason: VaultLockReason.background);
      } else {
        _backgroundedTime = DateTime.now();
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_backgroundedTime != null) {
        final elapsed = DateTime.now().difference(_backgroundedTime!).inSeconds;
        _backgroundedTime = null;
        if (elapsed >= _autoLockTimeoutSeconds && _autoLockTimeoutSeconds > 0) {
          lock(reason: VaultLockReason.background);
          return;
        }
      }
      recordUserActivity();
    }
  }

  @override
  void dispose() {
    lock();
    super.dispose();
  }
}
