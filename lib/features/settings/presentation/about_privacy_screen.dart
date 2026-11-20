import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';

class AboutPrivacyScreen extends StatelessWidget {
  const AboutPrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('About & Privacy Architecture', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        children: [
          // App Header
          Center(
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: colors.heroGradient,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: colors.primaryAccent.withOpacity(0.25),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.shield_outlined, color: Colors.white, size: 36),
                ),
                const SizedBox(height: 12),
                Text(
                  AppConstants.appName,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${AppConstants.appTagline} • v${AppConstants.appVersion}',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Security & Privacy Pillar Cards
          _buildInfoCard(
            context,
            icon: Icons.wifi_off_rounded,
            title: '100% Offline by Design',
            content: 'The application contains zero network permissions, zero cloud synchronization, zero remote analytics, and zero advertising SDKs. Document files, passwords, bank records, and database tables never leave your physical device.',
          ),
          const SizedBox(height: 14),

          _buildInfoCard(
            context,
            icon: Icons.verified_user_rounded,
            title: 'Mandatory Two-Factor Architecture',
            content: 'Vault strictly requires BOTH Factor 1 (Android BiometricPrompt) and Factor 2 (6-digit PIN) for every unlock. The Vault Master Key (VMK) is divided into two 256-bit shares using XOR secret sharing (VMK = S_bio ⊕ S_pin). By information theory, neither factor alone can decrypt any document, password, or bank account.',
          ),
          const SizedBox(height: 14),

          _buildInfoCard(
            context,
            icon: Icons.info_outline_rounded,
            title: 'Entropy & Limitations of 6-Digit PINs',
            content: 'A six-digit numeric PIN offers exactly 1,000,000 combinations (~19.93 bits of entropy). On its own, a 6-digit PIN does NOT have high entropy. However, in Vault\'s 2FA architecture, the PIN is combined with a hardware-backed biometric share from the Android Keystore, neutralizing offline brute-force attacks. Local guessing is restricted via 100,000 PBKDF2 iterations and exponential rate-limiting lockouts.',
          ),
          const SizedBox(height: 14),

          _buildInfoCard(
            context,
            icon: Icons.key_rounded,
            title: 'Password Manager & AAD Binding',
            content: 'Passwords, usernames, emails, and notes are encrypted at rest with AES-256-GCM. Each field is bound to its record identity and field name using Associated Authenticated Data (AAD) to prevent ciphertext swapping. Revealing any stored password requires fresh two-factor authentication.',
          ),
          const SizedBox(height: 14),

          _buildInfoCard(
            context,
            icon: Icons.account_balance_rounded,
            title: 'Bank Vault Restrictions & Strict Privacy',
            content: 'Bank Vault stores encrypted reference data ONLY. It does NOT connect to banks or process transactions. Vault STRICTLY PROHIBITS and has NO fields for ATM PINs, CVVs, UPI PINs, OTPs, or Netbanking passwords. Full account numbers are masked by default and require fresh 2FA verification to reveal.',
          ),
          const SizedBox(height: 14),

          _buildInfoCard(
            context,
            icon: Icons.content_copy_rounded,
            title: 'Clipboard Protection & Limitations',
            content: 'Copied passwords, usernames, and account numbers are automatically overwritten with empty strings after 30 seconds and upon application lock. Note: Android\'s clipboard is a shared system resource; if another background app reads the clipboard before the 30-second wipe, Vault cannot erase third-party copies. Users should paste credentials immediately.',
          ),
          const SizedBox(height: 14),

          _buildInfoCard(
            context,
            icon: Icons.visibility_off_rounded,
            title: 'Screen Privacy (FLAG_SECURE)',
            content: 'Android window FLAG_SECURE is applied by default to prevent screen recordings, screenshots, and hide previews in the Android Recent Tasks switcher.',
          ),
          const SizedBox(height: 14),

          _buildInfoCard(
            context,
            icon: Icons.text_snippet_outlined,
            title: 'Bundled Offline OCR Models & Licenses',
            content: 'Offline text recognition is powered by Tesseract OCR with bundled language models:\n• eng.traineddata (English)\n• hin.traineddata (Hindi)\n• guj.traineddata (Gujarati)\nAll bundled models are distributed under the Apache License 2.0 (Copyright Google LLC & Tesseract OCR contributors). No online models are ever requested or downloaded at runtime.',
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildInfoCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String content,
  }) {
    final colors = context.themeColors;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colors.cardBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: colors.primaryAccent, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            content,
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
