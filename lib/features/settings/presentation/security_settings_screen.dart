import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/security/privacy_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/error_dialog.dart';
import '../../authentication/presentation/auth_providers.dart';
import '../../authentication/presentation/two_factor_verification_dialog.dart';

class SecuritySettingsScreen extends ConsumerStatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  ConsumerState<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends ConsumerState<SecuritySettingsScreen> {
  Future<void> _showChangePinDialog() async {
    // 1. Mandatory 2FA Verification before sensitive PIN change
    final verified = await TwoFactorVerificationDialog.verify(
      context,
      title: 'Authorize PIN Change',
      reason: 'Factor 1: Verify your identity with biometrics before changing PIN',
    );

    if (!verified || !mounted) return;

    final currentPinController = TextEditingController();
    final newPinController = TextEditingController();
    final confirmPinController = TextEditingController();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    final changed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: isDark ? AppColors.darkCardElevated : AppColors.lightCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Change 6-Digit App PIN', style: TextStyle(fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: currentPinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(labelText: 'Current 6-digit PIN'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: newPinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(labelText: 'New 6-digit PIN'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: confirmPinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(labelText: 'Confirm New 6-digit PIN'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (newPinController.text.length != 6) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('PIN must be exactly 6 numeric digits.')),
                  );
                  return;
                }
                if (newPinController.text != confirmPinController.text) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('New PINs do not match.')),
                  );
                  return;
                }
                Navigator.of(ctx).pop(true);
              },
              child: const Text('Change PIN'),
            ),
          ],
        );
      },
    );

    if (changed == true && mounted) {
      try {
        final keyService = ref.read(keyManagementServiceProvider);
        final bioShare = await keyService.startTwoFactorBiometricUnlock();

        await keyService.changeSixDigitPin2FA(
          bioShare: bioShare,
          currentPin: currentPinController.text.trim(),
          newPin: newPinController.text.trim(),
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('6-digit PIN changed successfully.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ErrorDialog.show(context, title: 'PIN Change Failed', message: e.toString());
        }
      }
    }
  }

  Future<void> _updateAutoLock(int seconds) async {
    await ref.read(settingsProvider.notifier).setAutoLockDuration(seconds);
    ref.read(vaultSessionProvider).setAutoLockTimeout(seconds);
  }

  Future<void> _toggleScreenshotProtection(bool enable) async {
    await ref.read(settingsProvider.notifier).setScreenshotProtection(enable);
    await PrivacyService.setScreenshotProtection(enable);
  }

  Future<void> _resetVault() async {
    final confirmed = await ErrorDialog.confirm(
      context,
      title: 'DANGER: Destroy & Reset Vault?',
      message: 'This will permanently destroy ALL encrypted keys, documents, passwords, bank records, and settings. Recovery is mathematically impossible.',
      confirmLabel: 'Destroy Everything',
      isDestructive: true,
    );

    if (confirmed && mounted) {
      final keyService = ref.read(keyManagementServiceProvider);
      final session = ref.read(vaultSessionProvider);
      session.lock();
      await keyService.wipeAllKeys();

      if (mounted) {
        context.go('/welcome');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.lightBackground,
      appBar: AppBar(
        title: const Text('Security & Privacy', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        children: [
          // Mandatory 2FA Architecture Notice Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkCard : AppColors.lightCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.primaryTeal.withOpacity(0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.verified_user_rounded, color: AppColors.primaryTeal, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Mandatory Two-Factor Architecture',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Vault enforces 2-of-2 secret sharing (VMK = S_bio ⊕ S_pin). Factor 1 (Biometric) and Factor 2 (6-digit PIN) are both mandatory for every unlock. Neither factor independently grants access to any decrypted document, password, or bank record.',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Security note on 6-digit PINs: A 6-digit PIN has 1,000,000 combinations (~19.93 bits of entropy). On its own, it does not provide high entropy. By binding the PIN with the hardware-backed Android Keystore biometric share, offline brute-force attacks on the PIN are neutralized.',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontStyle: FontStyle.italic,
                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Authentication Section
          _buildSectionHeader('Authentication Controls'),
          _buildCard([
            ListTile(
              leading: const Icon(Icons.password_rounded, color: AppColors.primaryTeal),
              title: const Text('Change 6-Digit App PIN', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Requires 2FA verification before updating', style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _showChangePinDialog,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.fingerprint_rounded, color: AppColors.primaryTeal),
              title: const Text('Factor 1: Biometric Authentication', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Enforced for all unlocks • Protected by Android Keystore', style: TextStyle(fontSize: 12)),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primaryTeal.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text('MANDATORY', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.primaryTeal)),
              ),
            ),
          ]),
          const SizedBox(height: 20),

          // Auto-Lock Section
          _buildSectionHeader('Auto-Lock Timeout'),
          _buildCard([
            _buildTimeoutOption('Immediately when backgrounded (Recommended)', 0, settings.autoLockDuration),
            const Divider(height: 1),
            _buildTimeoutOption('30 seconds of inactivity', 30, settings.autoLockDuration),
            const Divider(height: 1),
            _buildTimeoutOption('1 minute of inactivity', 60, settings.autoLockDuration),
            const Divider(height: 1),
            _buildTimeoutOption('5 minutes of inactivity', 300, settings.autoLockDuration),
          ]),
          const SizedBox(height: 20),

          // Screen Privacy Section
          _buildSectionHeader('Screen Privacy'),
          _buildCard([
            SwitchListTile(
              secondary: const Icon(Icons.visibility_off_outlined, color: AppColors.primaryTeal),
              title: const Text('Block Screenshots & Recordings', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Hides preview in recent-apps list (FLAG_SECURE)', style: TextStyle(fontSize: 12)),
              value: settings.screenshotProtection,
              activeColor: AppColors.primaryTeal,
              onChanged: _toggleScreenshotProtection,
            ),
          ]),
          const SizedBox(height: 24),

          // Danger Zone
          _buildSectionHeader('Danger Zone'),
          _buildCard([
            ListTile(
              leading: const Icon(Icons.dangerous_outlined, color: AppColors.statusDanger),
              title: const Text('Destroy & Reset Vault', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.statusDanger)),
              subtitle: const Text('Permanently wipes all encryption keys, documents, passwords, and bank accounts', style: TextStyle(fontSize: 12)),
              onTap: _resetVault,
            ),
          ]),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppColors.primaryTeal,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildTimeoutOption(String label, int seconds, int currentVal) {
    return RadioListTile<int>(
      title: Text(label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500)),
      value: seconds,
      groupValue: currentVal,
      activeColor: AppColors.primaryTeal,
      onChanged: (val) {
        if (val != null) _updateAutoLock(val);
      },
    );
  }
}
