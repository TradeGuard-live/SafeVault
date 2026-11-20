import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/rupee_bunny_mascot.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              const Center(
                child: RupeeBunnyMascot(
                  pose: MascotPose.friendly,
                  size: 88,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Welcome to Vault',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your offline, hardware-encrypted personal document safe.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: colors.textSecondary,
                  height: 1.4,
                ),
              ),
              const Spacer(),
              _buildFeatureItem(
                context,
                icon: Icons.wifi_off_rounded,
                title: 'Completely Offline & Private',
                subtitle: 'Zero cloud dependencies, zero external tracking. Your documents never leave this device.',
              ),
              const SizedBox(height: 16),
              _buildFeatureItem(
                context,
                icon: Icons.shield_rounded,
                title: 'AES-256-GCM Cryptography',
                subtitle: 'Documents and metadata are securely encrypted at rest using an ephemeral master key.',
              ),
              const SizedBox(height: 16),
              _buildFeatureItem(
                context,
                icon: Icons.fingerprint_rounded,
                title: 'Mandatory Two-Factor Security',
                subtitle: 'Protected by both biometric authentication and a dedicated 6-digit vault passcode.',
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.primaryAccent.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.primaryAccent.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 20, color: colors.primaryAccent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Offline Security Guarantee: If you forget your PIN and biometrics are unavailable, your encrypted vault cannot be recovered.',
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.textSecondary,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => context.go('/setup'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.primaryAccent,
                  foregroundColor: colors.onPrimaryAccent,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Initialize Secure Vault',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_forward_rounded, size: 18),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final colors = context.themeColors;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: colors.surfaceSecondary,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colors.cardBorder,
            ),
          ),
          child: Icon(icon, color: colors.primaryAccent, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12.5,
                  color: colors.textSecondary,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
