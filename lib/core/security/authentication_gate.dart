import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../features/authentication/presentation/auth_providers.dart';
import 'biometric_service.dart';
import 'vault_session.dart';

enum VaultActionType {
  revealBankDetails,
  copyBankDetails,
  deleteBankAccount,
  revealPassword,
  copyPassword,
  editPassword,
  editBankAccount,
  deletePassword,
  revealDocumentField,
  copyDocumentField,
  copyAllFields,
  viewExtractedText,
  exportDocument,
  shareDocument,
  deleteDocument,
  restoreDocument,
  permanentlyDeleteDocument,
  custom,
}

enum SensitivityLevel { low, medium, high }

/// Represents a protected operation awaiting confirmation or the initial vault
/// unlock flow.
class PendingVaultAction {
  final String id;
  final VaultActionType type;
  final String? targetId; // documentId, bankAccountId, passwordId
  final String? targetName;
  final String? originalRoute; // e.g. /bank-account/123
  final String? returnRoute; // backward-compatibility alias
  final Map<String, String> queryParams;
  final SensitivityLevel requiredAuthLevel;
  final Map<String, dynamic> safeState;
  final Map<String, dynamic> params; // backward-compatibility alias
  final DateTime createdAt;
  bool isExecuted;

  PendingVaultAction({
    String? id,
    required this.type,
    this.targetId,
    this.targetName,
    String? originalRoute,
    String? returnRoute,
    Map<String, String>? queryParams,
    this.requiredAuthLevel = SensitivityLevel.high,
    Map<String, dynamic>? safeState,
    Map<String, dynamic>? params,
    DateTime? createdAt,
    this.isExecuted = false,
  }) : id = id ?? const Uuid().v4(),
       originalRoute = originalRoute ?? returnRoute,
       returnRoute = returnRoute ?? originalRoute,
       queryParams = queryParams ?? const {},
       safeState = safeState ?? params ?? const {},
       params = params ?? safeState ?? const {},
       createdAt = createdAt ?? DateTime.now();

  bool get isExpired => DateTime.now().difference(createdAt).inMinutes > 5;
}

final authenticationGateProvider = ChangeNotifierProvider<AuthenticationGate>((
  ref,
) {
  // AuthenticationGate owns the action that must be resumed after unlock.
  // Reading (rather than watching) the session keeps that action intact when
  // VaultSession notifies listeners during the unlock transition.
  final session = ref.read(vaultSessionProvider);
  final biometricService = ref.read(biometricServiceProvider);
  return AuthenticationGate(session, biometricService: biometricService);
});

/// Central authentication gate for the entire application.
/// The initial vault unlock requires both biometric verification and the
/// six-digit PIN. Once unlocked, protected operations require a fresh
/// biometric confirmation only; the PIN is not requested again during the
/// same vault session.
class AuthenticationGate extends ChangeNotifier {
  final VaultSession _session;
  final BiometricService _biometricService;
  PendingVaultAction? _pendingAction;
  bool _isAuthenticating = false;

  AuthenticationGate(this._session, {BiometricService? biometricService})
    : _biometricService =
          biometricService ?? BiometricService(vaultSession: _session);

  PendingVaultAction? get pendingAction => _pendingAction;
  bool get isAuthenticating => _isAuthenticating;

  void setPendingAction(PendingVaultAction action) {
    _pendingAction = action;
    notifyListeners();
  }

  void clearPendingAction() {
    _pendingAction = null;
    notifyListeners();
  }

  /// Consumes and executes a pending action if matching the target ID.
  PendingVaultAction? consumePendingAction(String? targetId) {
    if (_pendingAction == null) return null;
    if (_pendingAction!.isExpired || _pendingAction!.isExecuted) {
      _pendingAction = null;
      return null;
    }
    if (targetId != null && _pendingAction!.targetId != targetId) {
      return null;
    }
    final action = _pendingAction;
    _pendingAction = null;
    action!.isExecuted = true;
    notifyListeners();
    return action;
  }

  /// Authenticates a sensitive action with biometrics while the vault is
  /// already unlocked. The initial unlock remains biometric + PIN.
  /// Guarantees that the navigation stack is preserved and the user is NEVER
  /// redirected to the home screen.
  Future<bool> authenticateForAction(
    BuildContext context, {
    required PendingVaultAction action,
    String? title,
    String? reason,
    SensitivityLevel sensitivityLevel = SensitivityLevel.high,
  }) async {
    // Prevent duplicate concurrent prompt execution from multiple taps
    if (_isAuthenticating || !_session.isUnlocked) return false;
    _isAuthenticating = true;

    // 1. Record the pending action
    setPendingAction(action);

    _session.beginSystemActivity('AUTHENTICATION_GATE_${action.type.name}');

    try {
      final actionTitle = title ?? _defaultTitleFor(action.type);
      final dialogReason =
          reason ?? _defaultReasonFor(action.type, action.targetName);

      final verified = await _biometricService.authenticate(
        reason: '$actionTitle. $dialogReason',
      );

      if (verified && _session.isUnlocked) {
        action.isExecuted = true;
        _session.recordUserActivity();
        clearPendingAction();
        return true;
      } else {
        clearPendingAction();
        return false;
      }
    } catch (e) {
      clearPendingAction();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Biometric verification failed.')),
        );
      }
      return false;
    } finally {
      _isAuthenticating = false;
      Future.microtask(_session.endSystemActivity);
    }
  }

  String _defaultTitleFor(VaultActionType type) {
    switch (type) {
      case VaultActionType.revealBankDetails:
        return 'Reveal Bank Account';
      case VaultActionType.copyBankDetails:
        return 'Authorize Account Copy';
      case VaultActionType.deleteBankAccount:
        return 'Authorize Bank Deletion';
      case VaultActionType.revealPassword:
        return 'Reveal Password';
      case VaultActionType.copyPassword:
        return 'Copy Password';
      case VaultActionType.editPassword:
        return 'Edit Password';
      case VaultActionType.editBankAccount:
        return 'Edit Bank Account';
      case VaultActionType.deletePassword:
        return 'Authorize Password Deletion';
      case VaultActionType.revealDocumentField:
        return 'Reveal Document Information';
      case VaultActionType.copyDocumentField:
        return 'Copy Document Information';
      case VaultActionType.copyAllFields:
        return 'Copy All Structured Fields';
      case VaultActionType.viewExtractedText:
        return 'View Extracted Text';
      case VaultActionType.exportDocument:
        return 'Export Document';
      case VaultActionType.shareDocument:
        return 'Authorize Share';
      case VaultActionType.deleteDocument:
        return 'Confirm Deletion';
      case VaultActionType.restoreDocument:
        return 'Authorize Restoration';
      case VaultActionType.permanentlyDeleteDocument:
        return 'Confirm Permanent Destruction';
      case VaultActionType.custom:
        return 'Biometric Authentication';
    }
  }

  String _defaultReasonFor(VaultActionType type, String? targetName) {
    final name = targetName != null ? ' for "$targetName"' : '';
    switch (type) {
      case VaultActionType.revealBankDetails:
        return 'Confirm with biometrics to reveal full bank account details$name.';
      case VaultActionType.copyBankDetails:
        return 'Confirm with biometrics to copy bank details$name to clipboard.';
      case VaultActionType.deleteBankAccount:
        return 'Confirm with biometrics to delete bank account$name.';
      case VaultActionType.revealPassword:
        return 'Confirm with biometrics to reveal password$name.';
      case VaultActionType.copyPassword:
        return 'Confirm with biometrics to copy password$name.';
      case VaultActionType.editPassword:
        return 'Confirm with biometrics to edit password record$name.';
      case VaultActionType.editBankAccount:
        return 'Confirm with biometrics to edit bank account$name.';
      case VaultActionType.deletePassword:
        return 'Confirm with biometrics to delete password record$name.';
      case VaultActionType.revealDocumentField:
        return 'Confirm with biometrics to reveal confidential document numbers$name.';
      case VaultActionType.copyDocumentField:
        return 'Confirm with biometrics to copy confidential document information$name.';
      case VaultActionType.copyAllFields:
        return 'Confirm with biometrics to copy all structured fields$name to clipboard.';
      case VaultActionType.viewExtractedText:
        return 'Confirm with biometrics to view complete raw extracted document text$name.';
      case VaultActionType.exportDocument:
        return 'Confirm with biometrics to export decrypted document$name.';
      case VaultActionType.shareDocument:
        return 'Confirm with biometrics to share decrypted document$name.';
      case VaultActionType.deleteDocument:
        return 'Confirm with biometrics to delete document$name.';
      case VaultActionType.restoreDocument:
        return 'Confirm with biometrics to restore document$name from trash.';
      case VaultActionType.permanentlyDeleteDocument:
        return 'Confirm with biometrics to permanently delete and overwrite document$name.';
      case VaultActionType.custom:
        return 'Confirm with biometrics to proceed.';
    }
  }
}
