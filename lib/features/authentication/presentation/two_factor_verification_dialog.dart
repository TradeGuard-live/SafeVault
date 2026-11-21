import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/exceptions.dart';
import '../../../core/security/vault_session.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/pin_pad.dart';
import 'auth_providers.dart';

/// Modal dialog requiring mandatory Two-Factor Authentication
/// (Biometric + 6-digit PIN) before revealing or acting on sensitive secrets
/// (passwords, full bank account numbers, protected document fields).
///
/// The dialog is intentionally non-dismissible by tapping outside. It can only
/// be closed with the explicit close button or after both factors succeed.
class TwoFactorVerificationDialog extends ConsumerStatefulWidget {
  final String title;
  final String reason;

  const TwoFactorVerificationDialog({
    super.key,
    required this.title,
    required this.reason,
  });

  /// Displays the dialog and returns true only if BOTH biometric and PIN
  /// succeed while the vault session remains unlocked.
  static Future<bool> verify(
    BuildContext context, {
    required String title,
    required String reason,
    VaultSession? session,
  }) async {
    if (session != null && !session.isUnlocked) return false;

    session?.beginSystemActivity('TWO_FACTOR_VERIFICATION');
    try {
      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) =>
            TwoFactorVerificationDialog(title: title, reason: reason),
      );
      return result ?? false;
    } finally {
      session?.endSystemActivity();
    }
  }

  @override
  ConsumerState<TwoFactorVerificationDialog> createState() =>
      _TwoFactorVerificationDialogState();
}

class _TwoFactorVerificationDialogState
    extends ConsumerState<TwoFactorVerificationDialog> {
  late final VaultSession _session;
  bool _biometricPassed = false;
  bool _isAuthenticatingBio = false;
  bool _isVerifyingPin = false;
  Uint8List? _ephemeralBioShare;
  String? _errorMessage;
  int _lockoutSeconds = 0;

  @override
  void initState() {
    super.initState();
    _session = ref.read(vaultSessionProvider);
    _session.addListener(_handleSessionChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startBiometric();
    });
  }

  @override
  void dispose() {
    _session.removeListener(_handleSessionChange);
    _cleanupBioShare();
    // Ensure a biometric prompt cannot outlive the dialog.
    unawaited(ref.read(biometricServiceProvider).cancelAuthentication());
    super.dispose();
  }

  void _handleSessionChange() {
    // A lock during the prompt must invalidate the whole verification. Never
    // leave a dialog open that could later return true for a locked vault.
    if (!_session.isUnlocked && mounted) {
      _cleanupBioShare();
      Navigator.of(context).pop(false);
    }
  }

  void _cleanupBioShare() {
    if (_ephemeralBioShare != null) {
      _ephemeralBioShare!.fillRange(0, _ephemeralBioShare!.length, 0);
      _ephemeralBioShare = null;
    }
  }

  Future<void> _startBiometric() async {
    if (_isAuthenticatingBio) return;

    setState(() {
      _isAuthenticatingBio = true;
      _errorMessage = null;
    });

    try {
      final bioService = ref.read(biometricServiceProvider);
      final keyService = ref.read(keyManagementServiceProvider);

      final success = await bioService.authenticate(reason: widget.reason);
      if (!mounted) return;

      if (!success) {
        setState(() {
          _isAuthenticatingBio = false;
          _errorMessage = 'Biometric verification cancelled.';
        });
        return;
      }

      // The hardware Keystore key is valid for a short window after the
      // biometric prompt. Unwrap the biometric share immediately.
      final share = await keyService.startTwoFactorBiometricUnlock();
      if (!mounted) {
        share.fillRange(0, share.length, 0);
        return;
      }

      // Keep the session protected while the user enters Factor 2. The static
      // verify() wrapper ends this lease when the dialog closes.
      _session.beginSystemActivity('TWO_FACTOR_PIN_ENTRY');

      setState(() {
        _ephemeralBioShare = share;
        _biometricPassed = true;
        _isAuthenticatingBio = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isAuthenticatingBio = false;
          _errorMessage = e is BiometricException
              ? e.message
              : 'Biometric verification failed.';
        });
      }
    }
  }

  Future<void> _handlePinSubmitted(String pin) async {
    if (_isVerifyingPin) return;

    final share = _ephemeralBioShare;
    if (share == null) {
      Navigator.of(context).pop(false);
      return;
    }

    setState(() {
      _isVerifyingPin = true;
      _errorMessage = null;
    });

    final pinService = ref.read(pinServiceProvider);
    final keyService = ref.read(keyManagementServiceProvider);

    try {
      if (await pinService.isLockedOut()) {
        final remaining = await pinService.getRemainingLockoutSeconds();
        if (!mounted) return;
        setState(() {
          _isVerifyingPin = false;
          _lockoutSeconds = remaining;
        });
        return;
      }

      // Factor 2: verify the PIN and reconstruct the master key. The
      // reconstructed key is deliberately not persisted here; the active
      // session already holds the unlocked key.
      await keyService.completeTwoFactorPinUnlock(
        bioShare: Uint8List.fromList(share),
        pin: pin,
      );

      await pinService.resetFailedAttempts();
      _cleanupBioShare();
      _session.recordUserActivity();

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on InvalidPinException {
      HapticFeedback.heavyImpact();
      _cleanupBioShare();
      try {
        final count = await pinService.recordFailedAttempt();
        if (!mounted) return;
        setState(() {
          _biometricPassed = false; // Reset to Factor 1
          _isVerifyingPin = false;
          _errorMessage =
              'Incorrect PIN ($count failed attempts). Verify biometrics again.';
        });
      } on PinLockedOutException catch (e) {
        if (!mounted) return;
        setState(() {
          _biometricPassed = false;
          _isVerifyingPin = false;
          _lockoutSeconds = e.lockDurationSeconds;
          _errorMessage =
              'Too many failed attempts. Locked for ${e.lockDurationSeconds}s.';
        });
      }
    } catch (e) {
      _cleanupBioShare();
      if (!mounted) return;
      setState(() {
        _biometricPassed = false;
        _isVerifyingPin = false;
        _errorMessage = 'Authentication error. Please retry.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;

    return Dialog(
      backgroundColor: colors.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.cardBorder),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colors.primaryAccent.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.security_rounded,
                      color: colors.primaryAccent,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Mandatory Two-Factor Verification',
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.primaryAccent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: colors.textSecondary,
                    ),
                    onPressed: () {
                      _cleanupBioShare();
                      Navigator.of(context).pop(false);
                    },
                  ),
                ],
              ),
              Divider(height: 24, color: colors.divider),

              if (!_biometricPassed) ...[
                // Factor 1 View
                const SizedBox(height: 12),
                InkWell(
                  onTap: _isAuthenticatingBio ? null : _startBiometric,
                  borderRadius: BorderRadius.circular(40),
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colors.primaryAccent.withOpacity(0.12),
                      border: Border.all(
                        color: colors.primaryAccent.withOpacity(0.3),
                        width: 2,
                      ),
                    ),
                    child: _isAuthenticatingBio
                        ? Padding(
                            padding: const EdgeInsets.all(24),
                            child: CircularProgressIndicator(
                              color: colors.primaryAccent,
                              strokeWidth: 2.5,
                            ),
                          )
                        : Icon(
                            Icons.fingerprint_rounded,
                            size: 48,
                            color: colors.primaryAccent,
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Factor 1: Biometric Verification',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.reason,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: colors.textSecondary),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: colors.error),
                  ),
                ],
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _isAuthenticatingBio ? null : _startBiometric,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.primaryAccent,
                    foregroundColor: colors.onPrimaryAccent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.fingerprint_rounded, size: 18),
                  label: const Text('Verify Biometrics'),
                ),
              ] else ...[
                // Factor 2 View
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      color: colors.success,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Biometrics Verified • Enter 6-Digit PIN',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.success,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                AbsorbPointer(
                  absorbing: _isVerifyingPin,
                  child: Opacity(
                    opacity: _isVerifyingPin ? 0.55 : 1,
                    child: PinPad(
                      pinLength: 6,
                      onPinComplete: _handlePinSubmitted,
                      errorMessage: _errorMessage,
                      lockoutRemainingSeconds: _lockoutSeconds,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
