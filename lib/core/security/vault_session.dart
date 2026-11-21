import 'dart:async';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/widgets.dart';
import '../storage/encrypted_file_storage.dart';
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

  // System activity coordination (SAF file picker, camera, sharesheet)
  bool _isSystemActivityActive = false;
  String? _activeSystemActivityDescription;
  DateTime? _systemActivityStartTime;

  /// Grace period allowed when an explicit system activity is open (5 minutes)
  static const int systemActivityGraceTimeoutSeconds = 300;

  bool get isUnlocked => _masterKey != null;
  SecretKey? get masterKey => _masterKey;
  int get autoLockTimeoutSeconds => _autoLockTimeoutSeconds;
  DateTime? get lastActivityTime => _lastActivityTime;
  bool get isSystemActivityActive => _isSystemActivityActive;
  String? get activeSystemActivityDescription => _activeSystemActivityDescription;

  void setAutoLockTimeout(int seconds) {
    _autoLockTimeoutSeconds = seconds;
    _resetInactivityTimer();
    notifyListeners();
  }

  /// Marks the start of an explicit system activity (e.g. Android SAF file picker,
  /// Camera, Sharesheet) so that transient paused/inactive lifecycle states
  /// do not prematurely lock the vault session.
  void beginSystemActivity(String description) {
    if (!isUnlocked) return;
    _isSystemActivityActive = true;
    _activeSystemActivityDescription = description;
    _systemActivityStartTime = DateTime.now();
  }

  /// Marks the completion or cancellation of the active system activity.
  void endSystemActivity() {
    _isSystemActivityActive = false;
    _activeSystemActivityDescription = null;
    _systemActivityStartTime = null;
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
    _isSystemActivityActive = false;
    _activeSystemActivityDescription = null;
    _systemActivityStartTime = null;

    // Securely clear clipboard
    ClipboardSecurityService.instance.clearSensitiveClipboard();

    // Securely purge all ephemeral decrypted files and scanner cache
    EncryptedFileStorage().wipeEphemeralFiles().ignore();

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
      if (_isSystemActivityActive) {
        // App was paused/inactive because an explicit system activity was launched
        // (e.g. Android Storage Access Framework file picker, Camera, Sharesheet).
        // Do NOT lock immediately; record timestamp for grace timeout evaluation.
        _backgroundedTime ??= DateTime.now();
      } else if (_autoLockTimeoutSeconds == 0) {
        lock(reason: VaultLockReason.background);
      } else {
        _backgroundedTime = DateTime.now();
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_isSystemActivityActive) {
        if (_backgroundedTime != null) {
          final elapsed = DateTime.now().difference(_backgroundedTime!).inSeconds;
          if (elapsed >= systemActivityGraceTimeoutSeconds) {
            // Exceeded system activity grace timeout (e.g. user walked away for > 5 min)
            endSystemActivity();
            lock(reason: VaultLockReason.background);
            return;
          }
        }
        _backgroundedTime = null;
        recordUserActivity();
        return;
      }

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
