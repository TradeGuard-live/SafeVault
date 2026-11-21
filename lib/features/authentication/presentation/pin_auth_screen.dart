import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/exceptions.dart';
import '../../../core/routes/app_router.dart';
import '../../../core/security/authentication_gate.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/pin_pad.dart';
import 'auth_providers.dart';

/// Screen 2 of Mandatory 2FA: Factor 2 - Six-digit Vault PIN.
/// Only accessible after Factor 1 (Biometric) verification has succeeded.
class PinAuthScreen extends ConsumerStatefulWidget {
  const PinAuthScreen({super.key});

  @override
  ConsumerState<PinAuthScreen> createState() => _PinAuthScreenState();
}

class _PinAuthScreenState extends ConsumerState<PinAuthScreen> {
  final GlobalKey<State<PinPad>> _pinPadKey = GlobalKey();
  String? _errorMessage;
  int _lockoutSeconds = 0;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _verifyFactorOnePrecondition();
    _checkLockout();
  }

  void _verifyFactorOnePrecondition() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final coordinator = ref.read(twoFactorCoordinatorProvider);
      // Strictly enforce that Factor 1 must have completed!
      if (!coordinator.hasActiveBiometricVerification) {
        context.go('/biometric-unlock');
      }
    });
  }

  Future<void> _checkLockout() async {
    final pinService = ref.read(pinServiceProvider);
    final isLocked = await pinService.isLockedOut();
    if (isLocked) {
      final rem = await pinService.getRemainingLockoutSeconds();
      if (mounted) setState(() => _lockoutSeconds = rem);
    }
  }

  Future<void> _handlePinEntered(String pin) async {
    setState(() {
      _errorMessage = null;
      _isLoading = true;
    });

    final coordinator = ref.read(twoFactorCoordinatorProvider);
    final pinService = ref.read(pinServiceProvider);
    final keyService = ref.read(keyManagementServiceProvider);
    final session = ref.read(vaultSessionProvider);

    // Consume ephemeral biometric share
    final bioShare = coordinator.consumeBiometricShare();
    if (bioShare == null) {
      // Biometric session timed out or missing
      if (mounted) {
        setState(() => _isLoading = false);
        context.go('/biometric-unlock');
      }
      return;
    }

    try {
      // Verify Factor 2 and reconstruct Master Key: VMK = S_bio ⊕ S_pin
      final masterKey = await keyService.completeTwoFactorPinUnlock(
        bioShare: bioShare,
        pin: pin,
      );

      // Both factors verified successfully!
      await pinService.resetFailedAttempts();

      // Unlock ephemeral session
      await session.unlock(masterKey);

      if (mounted) {
        final gate = ref.read(authenticationGateProvider);
        if (gate.pendingAction != null &&
            gate.pendingAction!.returnRoute != null &&
            !gate.pendingAction!.isExpired) {
          final target = gate.pendingAction!.returnRoute!;
          context.go(target);
        } else {
          final pendingShares = ref.read(pendingIncomingShareProvider);
          if (pendingShares.isNotEmpty) {
            context.go('/incoming-share-preview');
          } else {
            context.go('/dashboard');
          }
        }
      }
    } on InvalidPinException {
      HapticFeedback.heavyImpact();
      coordinator.cancelTransaction(); // Invalidate 2FA session on failure
      try {
        final count = await pinService.recordFailedAttempt();
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage =
                'Incorrect PIN ($count attempts). Biometric factor reset.';
          });
          // Redirect back to biometric screen after brief delay to re-authenticate Factor 1
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (mounted && !session.isUnlocked) {
              context.go('/biometric-unlock');
            }
          });
        }
      } on PinLockedOutException catch (e) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _lockoutSeconds = e.lockDurationSeconds;
            _errorMessage =
                'Account locked for ${e.lockDurationSeconds}s due to repeated failures.';
          });
        }
      }
    } catch (e) {
      coordinator.cancelTransaction();
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Authentication failed. Please re-authenticate.';
        });
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted && !session.isUnlocked) {
            context.go('/biometric-unlock');
          }
        });
      }
    }
  }

  void _cancelAuthentication() {
    // User cancelled: wipe ephemeral state and return to Factor 1
    ref.read(twoFactorCoordinatorProvider).cancelTransaction();
    context.go('/biometric-unlock');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        elevation: 0,
        iconTheme: IconThemeData(color: colors.textPrimary),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Back to Biometrics',
          onPressed: _cancelAuthentication,
        ),
        title: Text(
          'Factor 2: Vault PIN',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
          child: Column(
            children: [
              // 2FA Progress Indicator
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colors.successContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          size: 14,
                          color: colors.success,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Factor 1: Biometrics Verified',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: colors.success,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              Text(
                'Enter Six-Digit PIN',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Enter your 6-digit application password to decrypt the vault.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: colors.textSecondary),
              ),

              const Spacer(),

              // Custom 6-digit PinPad
              PinPad(
                key: _pinPadKey,
                pinLength: 6,
                onPinComplete: _handlePinEntered,
                errorMessage: _errorMessage,
                lockoutRemainingSeconds: _lockoutSeconds,
              ),

              const Spacer(),

              // Cancel button
              TextButton.icon(
                onPressed: _isLoading ? null : _cancelAuthentication,
                icon: const Icon(Icons.cancel_outlined, size: 16),
                label: const Text('Cancel Authentication'),
                style: TextButton.styleFrom(
                  foregroundColor: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
