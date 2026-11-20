import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/errors/exceptions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/pin_pad.dart';
import 'auth_providers.dart';

/// Modal dialog requiring mandatory Two-Factor Authentication (Biometric + 6-digit PIN)
/// before revealing sensitive secrets (passwords, full bank account numbers).
class TwoFactorVerificationDialog extends ConsumerStatefulWidget {
  final String title;
  final String reason;

  const TwoFactorVerificationDialog({
    super.key,
    required this.title,
    required this.reason,
  });

  /// Displays the dialog and returns true only if BOTH biometric and PIN succeed.
  static Future<bool> verify(
    BuildContext context, {
    required String title,
    required String reason,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => TwoFactorVerificationDialog(
        title: title,
        reason: reason,
      ),
    );
    return result ?? false;
  }

  @override
  ConsumerState<TwoFactorVerificationDialog> createState() =>
      _TwoFactorVerificationDialogState();
}

class _TwoFactorVerificationDialogState
    extends ConsumerState<TwoFactorVerificationDialog> {
  bool _biometricPassed = false;
  bool _isAuthenticatingBio = false;
  Uint8List? _ephemeralBioShare;
  String? _errorMessage;
  int _lockoutSeconds = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startBiometric();
    });
  }

  @override
  void dispose() {
    _cleanupBioShare();
    super.dispose();
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
      if (!success) {
        if (mounted) {
          setState(() {
            _isAuthenticatingBio = false;
            _errorMessage = 'Biometric verification cancelled.';
          });
        }
        return;
      }

      final share = await keyService.startTwoFactorBiometricUnlock();

      if (mounted) {
        setState(() {
          _ephemeralBioShare = share;
          _biometricPassed = true;
          _isAuthenticatingBio = false;
        });
      }
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
    if (_ephemeralBioShare == null) {
      Navigator.of(context).pop(false);
      return;
    }

    final pinService = ref.read(pinServiceProvider);
    final keyService = ref.read(keyManagementServiceProvider);

    final isLocked = await pinService.isLockedOut();
    if (isLocked) {
      final rem = await pinService.getRemainingLockoutSeconds();
      setState(() => _lockoutSeconds = rem);
      return;
    }

    try {
      // Complete two-factor unlock
      await keyService.completeTwoFactorPinUnlock(
        bioShare: Uint8List.fromList(_ephemeralBioShare!),
        pin: pin,
      );

      // Both passed!
      await pinService.resetFailedAttempts();
      _cleanupBioShare();

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on InvalidPinException {
      HapticFeedback.heavyImpact();
      _cleanupBioShare();
      try {
        final count = await pinService.recordFailedAttempt();
        if (mounted) {
          setState(() {
            _biometricPassed = false; // Reset to factor 1
            _errorMessage = 'Incorrect PIN ($count failed attempts). Please retry from Factor 1.';
          });
        }
      } on PinLockedOutException catch (e) {
        if (mounted) {
          setState(() {
            _biometricPassed = false;
            _lockoutSeconds = e.lockDurationSeconds;
            _errorMessage = 'Too many failed attempts. Locked for ${e.lockDurationSeconds}s.';
          });
        }
      }
    } catch (e) {
      _cleanupBioShare();
      if (mounted) {
        setState(() {
          _biometricPassed = false;
          _errorMessage = 'Authentication error. Please retry.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor: isDark ? AppColors.darkCard : AppColors.lightCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
                      color: AppColors.primaryTeal.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.security_rounded,
                        color: AppColors.primaryTeal, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Mandatory Two-Factor Verification',
                          style: TextStyle(
                              fontSize: 11,
                              color: AppColors.primaryTeal,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () {
                      _cleanupBioShare();
                      Navigator.of(context).pop(false);
                    },
                  ),
                ],
              ),
              const Divider(height: 24),

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
                      color: AppColors.primaryTeal.withOpacity(0.12),
                      border: Border.all(
                        color: AppColors.primaryTeal.withOpacity(0.3),
                        width: 2,
                      ),
                    ),
                    child: const Icon(Icons.fingerprint_rounded,
                        size: 48, color: AppColors.primaryTeal),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Factor 1: Biometric Verification',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.reason,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                  ),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: AppColors.errorRed),
                  ),
                ],
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _isAuthenticatingBio ? null : _startBiometric,
                  icon: const Icon(Icons.fingerprint_rounded, size: 18),
                  label: const Text('Verify Biometrics'),
                ),
              ] else ...[
                // Factor 2 View
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle_rounded,
                        color: AppColors.successGreen, size: 16),
                    SizedBox(width: 6),
                    Text(
                      'Biometrics Verified • Enter 6-Digit PIN',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.successGreen),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                PinPad(
                  pinLength: 6,
                  onPinComplete: _handlePinSubmitted,
                  errorMessage: _errorMessage,
                  lockoutRemainingSeconds: _lockoutSeconds,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

