import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/security/authentication_gate.dart';
import '../../../core/security/privacy_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/error_dialog.dart';
import '../../authentication/presentation/auth_providers.dart';

class SecuritySettingsScreen extends ConsumerStatefulWidget {
  const SecuritySettingsScreen({super.key});

  @override
  ConsumerState<SecuritySettingsScreen> createState() =>
      _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState
    extends ConsumerState<SecuritySettingsScreen> {
  Future<void> _showChangePinDialog() async {
    final currentPinController = TextEditingController();
    final newPinController = TextEditingController();
    final confirmPinController = TextEditingController();

    final colors = context.themeColors;

    final changed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: colors.cardBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: colors.cardBorder),
          ),
          title: Text(
            'Change 6-Digit App PIN',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: currentPinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(
                  labelText: 'Current 6-digit PIN',
                  labelStyle: TextStyle(color: colors.textSecondary),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: newPinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(
                  labelText: 'New 6-digit PIN',
                  labelStyle: TextStyle(color: colors.textSecondary),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: confirmPinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: InputDecoration(
                  labelText: 'Confirm New 6-digit PIN',
                  labelStyle: TextStyle(color: colors.textSecondary),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                'Cancel',
                style: TextStyle(color: colors.textSecondary),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primaryAccent,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final currentPin = currentPinController.text.trim();
                final newPin = newPinController.text.trim();
                final confirmPin = confirmPinController.text.trim();
                final pinRegex = RegExp(r'^\d{6}$');
                if (!pinRegex.hasMatch(currentPin)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Current PIN must be exactly 6 numeric digits.'),
                    ),
                  );
                  return;
                }
                if (!pinRegex.hasMatch(newPin)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('New PIN must be exactly 6 numeric digits.'),
                    ),
                  );
                  return;
                }
                if (newPin != confirmPin) {
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
        final bioService = ref.read(biometricServiceProvider);
        final verified = await bioService.authenticate(
          reason: 'Authenticate to change your vault PIN',
        );
        if (!verified) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Biometric authentication cancelled. PIN not changed.'),
              ),
            );
          }
          currentPinController.dispose();
          newPinController.dispose();
          confirmPinController.dispose();
          return;
        }

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
          ErrorDialog.show(
            context,
            title: 'PIN Change Failed',
            message: e.toString(),
          );
        }
      } finally {
        currentPinController.dispose();
        newPinController.dispose();
        confirmPinController.dispose();
      }
    } else {
      currentPinController.dispose();
      newPinController.dispose();
      confirmPinController.dispose();
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
    final colors = context.themeColors;
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text(
          'Security & Privacy',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        children: [
          // Mandatory 2FA Architecture Notice Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.cardBackground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.primaryAccent.withOpacity(0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.verified_user_rounded,
                      color: colors.primaryAccent,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Mandatory Two-Factor Architecture',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: colors.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Vault enforces 2-of-2 secret sharing (VMK = S_bio ⊕ S_pin). Factor 1 (Biometric) and Factor 2 (6-digit PIN) are both mandatory for every unlock. Neither factor independently grants access to any decrypted document, password, or bank record.',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Security note on 6-digit PINs: A 6-digit PIN has 1,000,000 combinations (~19.93 bits of entropy). On its own, it does not provide high entropy. By binding the PIN with the hardware-backed Android Keystore biometric share, offline brute-force attacks on the PIN are neutralized.',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontStyle: FontStyle.italic,
                    color: colors.textSecondary,
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
              leading: Icon(
                Icons.password_rounded,
                color: colors.primaryAccent,
              ),
              title: Text(
                'Change 6-Digit App PIN',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              subtitle: Text(
                'Requires 2FA verification before updating',
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
              ),
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: colors.textSecondary,
              ),
              onTap: _showChangePinDialog,
            ),
            Divider(height: 1, color: colors.cardBorder),
            ListTile(
              leading: Icon(
                Icons.fingerprint_rounded,
                color: colors.primaryAccent,
              ),
              title: Text(
                'Factor 1: Biometric Authentication',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              subtitle: Text(
                'Enforced for all unlocks • Protected by Android Keystore',
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
              ),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: colors.primaryAccent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'MANDATORY',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: colors.primaryAccent,
                  ),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 20),

          // Auto-Lock Section
          _buildSectionHeader('Auto-Lock Timeout'),
          _buildCard([
            _buildTimeoutOption(
              'Immediately when backgrounded (Recommended)',
              0,
              settings.autoLockDuration,
            ),
            Divider(height: 1, color: colors.cardBorder),
            _buildTimeoutOption(
              '30 seconds of inactivity',
              30,
              settings.autoLockDuration,
            ),
            Divider(height: 1, color: colors.cardBorder),
            _buildTimeoutOption(
              '1 minute of inactivity',
              60,
              settings.autoLockDuration,
            ),
            Divider(height: 1, color: colors.cardBorder),
            _buildTimeoutOption(
              '5 minutes of inactivity',
              300,
              settings.autoLockDuration,
            ),
          ]),
          const SizedBox(height: 20),

          // Screen Privacy Section
          _buildSectionHeader('Screen Privacy'),
          _buildCard([
            SwitchListTile(
              secondary: Icon(
                Icons.visibility_off_outlined,
                color: colors.primaryAccent,
              ),
              title: Text(
                'Block Screenshots & Recordings',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              subtitle: Text(
                'Hides preview in recent-apps list (FLAG_SECURE)',
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
              ),
              value: settings.screenshotProtection,
              activeColor: colors.primaryAccent,
              onChanged: _toggleScreenshotProtection,
            ),
          ]),
          const SizedBox(height: 24),

          // Danger Zone
          _buildSectionHeader('Danger Zone', color: colors.error),
          _buildCard([
            ListTile(
              leading: Icon(Icons.dangerous_outlined, color: colors.error),
              title: Text(
                'Destroy & Reset Vault',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: colors.error,
                ),
              ),
              subtitle: Text(
                'Permanently wipes all encryption keys, documents, passwords, and bank accounts',
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
              ),
              onTap: _resetVault,
            ),
          ]),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, {Color? color}) {
    final colors = context.themeColors;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: color ?? colors.primaryAccent,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    final colors = context.themeColors;

    return Container(
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.cardBorder),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildTimeoutOption(String label, int seconds, int currentVal) {
    final colors = context.themeColors;
    return RadioListTile<int>(
      title: Text(
        label,
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
          color: colors.textPrimary,
        ),
      ),
      value: seconds,
      groupValue: currentVal,
      activeColor: colors.primaryAccent,
      onChanged: (val) {
        if (val != null) _updateAutoLock(val);
      },
    );
  }
}
