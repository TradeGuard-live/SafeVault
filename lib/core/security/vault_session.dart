import 'dart:async';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/widgets.dart';

import '../errors/exceptions.dart';
import '../storage/encrypted_file_storage.dart';
import 'clipboard_security_service.dart';

enum VaultLockReason { manual, inactivity, background, leaseExpired }

/// Coordinates vault session lifecycle, authentication state, master-key lifetime,
/// and bounded system activity leases (SAF picker, Camera, Sharesheet).
class VaultSession extends ChangeNotifier {
  SecretKey? _masterKey;
  DateTime? _lastActivityTime;
  DateTime? _backgroundedTime;
  Timer? _inactivityTimer;

  int _autoLockTimeoutSeconds = 0; // 0 = immediate upon backgrounding

  // System activity coordination (SAF file picker, camera, sharesheet)
  bool _isSystemActivityActive = false;
  String? _activeSystemActivityDescription;
  DateTime? _systemActivityStartTime;
  Timer? _systemActivityLeaseTimer;

  // Track active async operations (OCR extraction, file exports, batch encryption)
  int _activeOperationsCount = 0;
  int _operationCounter = 0;
  final Set<int> _activeOperationIds = {};

  /// Default lease period allowed when an explicit system activity is open (5 minutes)
  static const int systemActivityGraceTimeoutSeconds = 300;

  bool get isUnlocked => _masterKey != null;
  SecretKey? get masterKey => _masterKey;
  int get autoLockTimeoutSeconds => _autoLockTimeoutSeconds;
  DateTime? get lastActivityTime => _lastActivityTime;
  bool get isSystemActivityActive => _isSystemActivityActive;
  String? get activeSystemActivityDescription =>
      _activeSystemActivityDescription;
  bool get hasActiveOperations => _activeOperationsCount > 0;

  /// Returns the master key if unlocked, or throws [VaultLockedException] if locked.
  SecretKey getMasterKeyOrThrow() {
    if (!isUnlocked || _masterKey == null) {
      throw const VaultLockedException();
    }
    return _masterKey!;
  }

  void setAutoLockTimeout(int seconds) {
    _autoLockTimeoutSeconds = seconds;
    _resetInactivityTimer();
    notifyListeners();
  }

  /// Marks the start of an explicit system activity (e.g. Android SAF file picker,
  /// Camera, Sharesheet) with an independently enforced maximum lease timer.
  void beginSystemActivity(
    String description, {
    Duration timeout = const Duration(
      seconds: systemActivityGraceTimeoutSeconds,
    ),
  }) {
    if (!isUnlocked) return;
    _isSystemActivityActive = true;
    _activeSystemActivityDescription = description;
    _systemActivityStartTime = DateTime.now();

    // Enforce independent bounded lease timer so background/hung native intents cannot bypass auto-lock
    _systemActivityLeaseTimer?.cancel();
    _systemActivityLeaseTimer = Timer(timeout, () {
      endSystemActivity();
      lock(reason: VaultLockReason.leaseExpired);
    });
  }

  /// Marks the completion or cancellation of the active system activity and cancels the lease timer.
  void endSystemActivity() {
    _systemActivityLeaseTimer?.cancel();
    _systemActivityLeaseTimer = null;
    _isSystemActivityActive = false;
    _activeSystemActivityDescription = null;
    _systemActivityStartTime = null;
  }

  /// Registers an in-flight asynchronous operation (e.g. OCR scan or multi-file export).
  int beginActiveOperation() {
    final opId = ++_operationCounter;
    _activeOperationIds.add(opId);
    _activeOperationsCount = _activeOperationIds.length;
    return opId;
  }

  /// Unregisters a completed or cancelled operation.
  void endActiveOperation(int opId) {
    _activeOperationIds.remove(opId);
    _activeOperationsCount = _activeOperationIds.length;
  }

  /// Sets the unlocked session with the decrypted master key.
  Future<void> unlock(SecretKey key) async {
    _masterKey = key;
    _lastActivityTime = DateTime.now();
    _resetInactivityTimer();
    notifyListeners();
  }

  /// Locks the vault session and wipes sensitive key material from memory.
  void lock({VaultLockReason reason = VaultLockReason.manual}) {
    _inactivityTimer?.cancel();
    _inactivityTimer = null;

    _systemActivityLeaseTimer?.cancel();
    _systemActivityLeaseTimer = null;

    _isSystemActivityActive = false;
    _activeSystemActivityDescription = null;
    _systemActivityStartTime = null;
    _activeOperationIds.clear();
    _activeOperationsCount = 0;

    // Securely clear clipboard
    ClipboardSecurityService.instance.clearSensitiveClipboard();

    // Purge all ephemeral decrypted files, scanner cache, and staging files
    EncryptedFileStorage().wipeEphemeralFiles().ignore();

    // Release master key reference immediately
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
        // Lease timer is independently active in background.
        _backgroundedTime ??= DateTime.now();
      } else if (_autoLockTimeoutSeconds == 0) {
        lock(reason: VaultLockReason.background);
      } else {
        _backgroundedTime = DateTime.now();
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_isSystemActivityActive) {
        if (_backgroundedTime != null) {
          final elapsed = DateTime.now()
              .difference(_backgroundedTime!)
              .inSeconds;
          if (elapsed >= systemActivityGraceTimeoutSeconds) {
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
