import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../features/authentication/presentation/auth_providers.dart';
import '../../features/authentication/presentation/two_factor_verification_dialog.dart';
import 'vault_session.dart';

enum VaultActionType {
  revealBankDetails,
  copyBankDetails,
  revealPassword,
  copyPassword,
  editPassword,
  revealDocumentField,
  copyDocumentField,
  viewExtractedText,
  exportDocument,
  shareDocument,
  deleteDocument,
  custom,
}

enum SensitivityLevel {
  low,
  medium,
  high,
}

/// Represents a pending protected operation awaiting mandatory two-factor authentication.
class PendingVaultAction {
  final String id;
  final VaultActionType type;
  final String? targetId; // documentId, bankAccountId, passwordId
  final String? targetName;
  final String? returnRoute; // e.g. /bank-account/123
  final Map<String, dynamic> params;
  final DateTime createdAt;
  bool isExecuted;

  PendingVaultAction({
    String? id,
    required this.type,
    this.targetId,
    this.targetName,
    this.returnRoute,
    this.params = const {},
    DateTime? createdAt,
    this.isExecuted = false,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  bool get isExpired =>
      DateTime.now().difference(createdAt).inMinutes > 5;
}

final authenticationGateProvider = ChangeNotifierProvider<AuthenticationGate>((ref) {
  final session = ref.watch(vaultSessionProvider);
  return AuthenticationGate(session);
});

/// Central authentication gate for the entire application.
/// Ensures that protected operations (e.g. reveal account number, reveal password,
/// copy sensitive data, export document) require mandatory Two-Factor Authentication
/// (Biometric + 6-digit PIN) and return directly to the requesting screen and action,
/// never redirecting to the home screen.
class AuthenticationGate extends ChangeNotifier {
  final VaultSession _session;
  PendingVaultAction? _pendingAction;

  AuthenticationGate(this._session);

  PendingVaultAction? get pendingAction => _pendingAction;

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
    // 1. Record the pending action
    setPendingAction(action);

    // 2. Mark system activity to prevent lifecycle false auto-locks
    _session.beginSystemActivity('AUTHENTICATION_GATE_${action.type.name}');

    try {
      final dialogTitle = title ?? _defaultTitleFor(action.type);
      final dialogReason = reason ?? _defaultReasonFor(action.type, action.targetName);

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
      case VaultActionType.revealPassword:
        return 'Reveal Password';
      case VaultActionType.copyPassword:
        return 'Copy Password';
      case VaultActionType.editPassword:
        return 'Edit Password';
      case VaultActionType.revealDocumentField:
        return 'Reveal Document Information';
      case VaultActionType.copyDocumentField:
        return 'Copy Document Information';
      case VaultActionType.viewExtractedText:
        return 'View Extracted Text';
      case VaultActionType.exportDocument:
        return 'Export Document';
      case VaultActionType.shareDocument:
        return 'Authorize Share';
      case VaultActionType.deleteDocument:
        return 'Confirm Permanent Deletion';
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
      case VaultActionType.revealPassword:
        return 'Authenticate with biometrics and 6-digit PIN to reveal password$name.';
      case VaultActionType.copyPassword:
        return 'Authenticate with biometrics and 6-digit PIN to copy password$name.';
      case VaultActionType.editPassword:
        return 'Authenticate to edit password record$name.';
      case VaultActionType.revealDocumentField:
        return 'Authenticate to reveal confidential document numbers$name.';
      case VaultActionType.copyDocumentField:
        return 'Authenticate to copy confidential document information$name.';
      case VaultActionType.viewExtractedText:
        return 'Authenticate to view complete raw extracted document text$name.';
      case VaultActionType.exportDocument:
        return 'Authenticate to export decrypted document$name.';
      case VaultActionType.shareDocument:
        return 'Authenticate to share decrypted document$name.';
      case VaultActionType.deleteDocument:
        return 'Authenticate to permanently delete document$name.';
      case VaultActionType.custom:
        return 'Authenticate with biometrics and 6-digit PIN to proceed.';
    }
  }
}

