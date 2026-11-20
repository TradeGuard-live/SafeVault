import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/errors/exceptions.dart';
import '../../../core/theme/app_colors.dart';
import 'auth_providers.dart';

/// Screen 1 of Mandatory 2FA: Factor 1 - Biometric Verification.
/// The user must successfully scan their fingerprint or face before the
/// six-digit PIN screen is displayed.
class BiometricAuthScreen extends ConsumerStatefulWidget {
  const BiometricAuthScreen({super.key});

  @override
  ConsumerState<BiometricAuthScreen> createState() => _BiometricAuthScreenState();
}

class _BiometricAuthScreenState extends ConsumerState<BiometricAuthScreen> {
  bool _isAuthenticating = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startBiometric();
    });
  }

  Future<void> _startBiometric() async {
    if (_isAuthenticating) return;
    setState(() {
      _isAuthenticating = true;
      _errorMessage = null;
    });

    try {
      final bioService = ref.read(biometricServiceProvider);
      final keyService = ref.read(keyManagementServiceProvider);
      final coordinator = ref.read(twoFactorCoordinatorProvider);

      // Verify biometric hardware presence
      final hasHardware = await bioService.isBiometricsAvailable();
      if (!hasHardware) {
        throw const BiometricException(
          'Biometric hardware is not available on this device. Mandatory two-factor authentication cannot proceed.',
        );
      }

      // Prompt Android BiometricPrompt
      final success = await bioService.authenticate(
        reason: 'Factor 1 of 2: Authenticate with biometrics to begin unlocking Vault',
      );

      if (!success) {
        if (mounted) {
          setState(() {
            _isAuthenticating = false;
            _errorMessage = 'Biometric verification cancelled. Please tap to try again.';
          });
        }
        return;
      }

      // Decrypt ephemeral biometric key share S_bio
      final bioShare = await keyService.startTwoFactorBiometricUnlock();

      // Store in coordinator
      coordinator.recordBiometricSuccess(bioShare);

      if (mounted) {
        // Transition to Factor 2 (Six-digit PIN)
        context.go('/pin-unlock');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isAuthenticating = false;
          _errorMessage = e is BiometricException
              ? e.message
              : 'Biometric verification failed. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.lightBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),

              // Vault Security Icon
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.primaryTeal.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.shield_rounded,
                  size: 38,
                  color: AppColors.primaryTeal,
                ),
              ),
              const SizedBox(height: 20),

              const Text(
                'Vault',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primaryTeal.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Factor 1 of 2 • Biometric Authentication',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryTeal,
                  ),
                ),
              ),

              const SizedBox(height: 48),

              // Interactive Fingerprint Button
              InkWell(
                onTap: _isAuthenticating ? null : _startBiometric,
                borderRadius: BorderRadius.circular(60),
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: AppColors.primaryTeal.withOpacity(0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.primaryTeal.withOpacity(0.35),
                      width: 2.5,
                    ),
                  ),
                  child: Center(
                    child: _isAuthenticating
                        ? const CircularProgressIndicator(
                            color: AppColors.primaryTeal,
                            strokeWidth: 3,
                          )
                        : const Icon(
                            Icons.fingerprint_rounded,
                            size: 68,
                            color: AppColors.primaryTeal,
                          ),
                  ),
                ),
              ),

              const SizedBox(height: 32),

              Text(
                'Verify Fingerprint or Face',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Touch the fingerprint sensor or look at your camera to complete Factor 1.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                ),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.errorRed.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.errorRed.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          size: 16, color: AppColors.errorRed),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.errorRed,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const Spacer(),

              // Manual retry button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isAuthenticating ? null : _startBiometric,
                  icon: const Icon(Icons.fingerprint_rounded, size: 20),
                  label: const Text('Scan Biometrics'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
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
