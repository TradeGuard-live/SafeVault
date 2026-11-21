import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../features/authentication/presentation/auth_providers.dart';
import '../../features/authentication/presentation/two_factor_verification_dialog.dart';
import 'vault_session.dart';

enum VaultActionType {
  revealBankDetails,
  copyBankDetails,
  deleteBankAccount,
  revealPassword,
  copyPassword,
  editPassword,
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

/// Represents a pending protected operation awaiting mandatory two-factor authentication.
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
  final session = ref.watch(vaultSessionProvider);
  return AuthenticationGate(session);
});

/// Central authentication gate for the entire application.
/// Ensures that protected operations (e.g. reveal account number, reveal password,
/// copy sensitive data, export document, delete document) require mandatory Two-Factor Authentication
/// (Biometric + 6-digit PIN) and return directly to the requesting screen and action,
/// never redirecting to the home screen.
class AuthenticationGate extends ChangeNotifier {
  final VaultSession _session;
  PendingVaultAction? _pendingAction;
  bool _isAuthenticating = false;

  AuthenticationGate(this._session);

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

  /// Authenticates the user for a specific protected operation using mandatory 2FA.
  /// Returns `true` only if BOTH Biometric and 6-digit PIN verifications succeed.
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
    if (_isAuthenticating) return false;
    _isAuthenticating = true;

    // 1. Record the pending action
    setPendingAction(action);

    // 2. Mark system activity to prevent lifecycle false auto-locks
    _session.beginSystemActivity('AUTHENTICATION_GATE_${action.type.name}');

    try {
      final dialogTitle = title ?? _defaultTitleFor(action.type);
      final dialogReason =
          reason ?? _defaultReasonFor(action.type, action.targetName);

      // 3. Display in-place Two-Factor Verification Dialog (Biometric + 6-digit PIN)
      final verified = await TwoFactorVerificationDialog.verify(
        context,
        title: dialogTitle,
        reason: dialogReason,
        session: _session,
      );

      if (verified) {
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
      return false;
    } finally {
      _isAuthenticating = false;
      Future.microtask(() {
        _session.endSystemActivity();
      });
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
        return 'Two-Factor Authentication';
    }
  }

  String _defaultReasonFor(VaultActionType type, String? targetName) {
    final name = targetName != null ? ' for "$targetName"' : '';
    switch (type) {
      case VaultActionType.revealBankDetails:
        return 'Authenticate with biometrics and 6-digit PIN to reveal full bank account details$name.';
      case VaultActionType.copyBankDetails:
        return 'Authenticate with biometrics and 6-digit PIN to copy bank details$name to clipboard.';
      case VaultActionType.deleteBankAccount:
        return 'Authenticate with biometrics and 6-digit PIN to delete bank account$name.';
      case VaultActionType.revealPassword:
        return 'Authenticate with biometrics and 6-digit PIN to reveal password$name.';
      case VaultActionType.copyPassword:
        return 'Authenticate with biometrics and 6-digit PIN to copy password$name.';
      case VaultActionType.editPassword:
        return 'Authenticate to edit password record$name.';
      case VaultActionType.deletePassword:
        return 'Authenticate to delete password record$name.';
      case VaultActionType.revealDocumentField:
        return 'Authenticate to reveal confidential document numbers$name.';
      case VaultActionType.copyDocumentField:
        return 'Authenticate to copy confidential document information$name.';
      case VaultActionType.copyAllFields:
        return 'Authenticate to copy all structured fields$name to clipboard.';
      case VaultActionType.viewExtractedText:
        return 'Authenticate to view complete raw extracted document text$name.';
      case VaultActionType.exportDocument:
        return 'Authenticate to export decrypted document$name.';
      case VaultActionType.shareDocument:
        return 'Authenticate to share decrypted document$name.';
      case VaultActionType.deleteDocument:
        return 'Authenticate to delete document$name.';
      case VaultActionType.restoreDocument:
        return 'Authenticate to restore document$name from trash.';
      case VaultActionType.permanentlyDeleteDocument:
        return 'Authenticate to permanently delete and overwrite document$name.';
      case VaultActionType.custom:
        return 'Authenticate with biometrics and 6-digit PIN to proceed.';
    }
  }
}
