import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/error_dialog.dart';
import '../../../core/widgets/pin_pad.dart';
import '../../authentication/presentation/auth_providers.dart';

enum SetupStep { createPin, confirmPin, biometricsNotice, finalizing }

class InitialSecuritySetupScreen extends ConsumerStatefulWidget {
  const InitialSecuritySetupScreen({super.key});

  @override
  ConsumerState<InitialSecuritySetupScreen> createState() =>
      _InitialSecuritySetupScreenState();
}

class _InitialSecuritySetupScreenState
    extends ConsumerState<InitialSecuritySetupScreen> {
  SetupStep _currentStep = SetupStep.createPin;
  String _firstEnteredPin = '';
  String _confirmedPin = '';
  bool _biometricsAvailableOnDevice = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
  }

  Future<void> _checkBiometrics() async {
    final bioService = ref.read(biometricServiceProvider);
    final available = await bioService.isBiometricsAvailable();
    if (mounted) {
      setState(() {
        _biometricsAvailableOnDevice = available;
      });
    }
  }

  void _handlePinCompleted(String pin) {
    setState(() => _errorMessage = null);

    if (_currentStep == SetupStep.createPin) {
      setState(() {
        _firstEnteredPin = pin;
        _currentStep = SetupStep.confirmPin;
      });
    } else if (_currentStep == SetupStep.confirmPin) {
      _confirmedPin = pin;
      if (_confirmedPin != _firstEnteredPin) {
        setState(() {
          _errorMessage =
              'PINs do not match. Please re-enter your 6-digit PIN.';
          _firstEnteredPin = '';
          _confirmedPin = '';
          _currentStep = SetupStep.createPin;
        });
      } else {
        setState(() {
          _currentStep = SetupStep.biometricsNotice;
        });
      }
    }
  }

  Future<void> _finalizeSetup() async {
    setState(() => _currentStep = SetupStep.finalizing);

    try {
      final keyService = ref.read(keyManagementServiceProvider);
      final session = ref.read(vaultSessionProvider);

      // Initialize Vault Master Key with Mandatory 2-of-2 Secret Sharing
      final masterKey = await keyService.initializeTwoFactorVault(
        pin: _confirmedPin,
      );

      // Save biometrics setting
      await ref.read(settingsProvider.notifier).setBiometricEnabled(true);

      // Unlock active session
      await session.unlock(masterKey);

      if (mounted) {
        context.go('/dashboard');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _currentStep = SetupStep.createPin);
        ErrorDialog.show(
          context,
          title: 'Setup Error',
          message: 'Failed to initialize encrypted vault: ${e.toString()}',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text(
          _currentStep == SetupStep.finalizing
              ? 'Finalizing Security'
              : 'Mandatory 2FA Setup',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
        backgroundColor: colors.background,
        elevation: 0,
        iconTheme: IconThemeData(color: colors.textPrimary),
        leading: _currentStep == SetupStep.confirmPin
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    _currentStep = SetupStep.createPin;
                    _errorMessage = null;
                  });
                },
              )
            : null,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: _currentStep == SetupStep.finalizing
              ? _buildFinalizingView(colors)
              : _currentStep == SetupStep.biometricsNotice
              ? _buildBiometricsNoticeView(colors)
              : _buildPinSetupView(colors),
        ),
      ),
    );
  }

  Widget _buildPinSetupView(dynamic colors) {
    final isCreating = _currentStep == SetupStep.createPin;

    return Column(
      children: [
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.primaryAccent.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isCreating
                ? Icons.pin_outlined
                : Icons.check_circle_outline_rounded,
            size: 36,
            color: colors.primaryAccent,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          isCreating ? 'Create Six-Digit PIN' : 'Confirm Six-Digit PIN',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          isCreating
              ? 'Enter a mandatory 6-digit application PIN. Factor 2 of your two-factor security.'
              : 'Re-enter your 6-digit PIN to confirm.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: colors.textSecondary),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: colors.errorContainer,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.error.withOpacity(0.3)),
            ),
            child: Text(
              _errorMessage!,
              style: TextStyle(
                color: colors.error,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        const Spacer(),
        PinPad(
          key: ValueKey(_currentStep),
          pinLength: AppConstants.pinLength, // 6 digits
          onPinComplete: _handlePinCompleted,
        ),
        const Spacer(),
      ],
    );
  }

  Widget _buildBiometricsNoticeView(dynamic colors) {
    return Column(
      children: [
        const Spacer(),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: colors.primaryAccent.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.fingerprint_rounded,
            size: 64,
            color: colors.primaryAccent,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Factor 1: Biometric Security',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0),
          child: Text(
            'Vault uses mandatory Two-Factor Authentication (Biometric + 6-digit PIN). Both factors are required for every unlock. Neither factor alone can decrypt your data.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              color: colors.textSecondary,
              height: 1.45,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: colors.surfaceSecondary,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.cardBorder),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: colors.primaryAccent,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Hardware Keystore Warning: If you alter enrolled biometrics in Android settings, Keystore invalidates the key. Keep your backup safe.',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textSecondary,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        ElevatedButton.icon(
          onPressed: _finalizeSetup,
          icon: const Icon(Icons.security_rounded, size: 20),
          label: const Text('Complete 2FA Setup'),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            backgroundColor: colors.primaryAccent,
            foregroundColor: colors.onPrimaryAccent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildFinalizingView(dynamic colors) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: colors.primaryAccent),
          const SizedBox(height: 24),
          Text(
            'Initializing 2FA Vault...',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Splitting Master Key into 2-of-2 secret shares (Biometric ⊕ PIN)',
            style: TextStyle(fontSize: 13, color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}
