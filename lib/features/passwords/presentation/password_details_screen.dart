import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/security/authentication_gate.dart';
import '../../../core/security/clipboard_security_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/error_dialog.dart';
import '../../authentication/presentation/auth_providers.dart';
import '../domain/password_entry_model.dart';

class PasswordDetailsScreen extends ConsumerStatefulWidget {
  final String passwordId;

  const PasswordDetailsScreen({super.key, required this.passwordId});

  @override
  ConsumerState<PasswordDetailsScreen> createState() =>
      _PasswordDetailsScreenState();
}

class _PasswordDetailsScreenState extends ConsumerState<PasswordDetailsScreen> {
  bool _isPasswordRevealed = false;
  PasswordEntryModel? _entry;
  bool _isLoading = true;
  Timer? _visibilityTimer;

  @override
  void initState() {
    super.initState();
    _loadEntry();
  }

  @override
  void deactivate() {
    // Re-hide password when navigating away
    _visibilityTimer?.cancel();
    _isPasswordRevealed = false;
    super.deactivate();
  }

  @override
  void dispose() {
    _visibilityTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadEntry() async {
    final session = ref.read(vaultSessionProvider);
    if (!session.isUnlocked || session.masterKey == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final repo = ref.read(passwordRepositoryProvider);
    final entry = await repo.getEntryById(
      widget.passwordId,
      session.masterKey!,
    );
    if (mounted) {
      setState(() {
        _entry = entry;
        _isLoading = false;
      });
      if (entry != null) {
        repo.updateLastAccessed(entry.id);
      }

      // Resume any pending action targeting this password entry
      final gate = ref.read(authenticationGateProvider);
      final pending = gate.consumePendingAction(widget.passwordId);
      if (pending != null && mounted) {
        if (pending.type == VaultActionType.revealPassword) {
          setState(() => _isPasswordRevealed = true);
        } else if (pending.type == VaultActionType.copyPassword &&
            entry?.decryptedPassword != null) {
          _copyPassword();
        }
      }
    }
  }

  Future<void> _revealPassword() async {
    if (_isPasswordRevealed) {
      setState(() => _isPasswordRevealed = false);
      return;
    }

    // The vault was unlocked with 2FA; a fresh biometric confirms this action.
    final gate = ref.read(authenticationGateProvider);
    final verified = await gate.authenticateForAction(
      context,
      action: PendingVaultAction(
        type: VaultActionType.revealPassword,
        targetId: widget.passwordId,
        targetName: _entry?.title ?? 'Password',
        returnRoute: '/password/${widget.passwordId}',
      ),
    );

    if (verified && mounted) {
      setState(() => _isPasswordRevealed = true);
      _visibilityTimer?.cancel();
      _visibilityTimer = Timer(const Duration(seconds: 60), () {
        if (mounted) {
          setState(() => _isPasswordRevealed = false);
        }
      });
    }
  }

  Future<void> _copyPassword() async {
    if (_entry?.decryptedPassword == null) return;
    if (!_isPasswordRevealed) {
      final gate = ref.read(authenticationGateProvider);
      final verified = await gate.authenticateForAction(
        context,
        action: PendingVaultAction(
          type: VaultActionType.copyPassword,
          targetId: widget.passwordId,
          targetName: _entry?.title ?? 'Password',
          returnRoute: '/password/${widget.passwordId}',
        ),
      );
      if (!mounted || !verified) return;
    }
    await ClipboardSecurityService.instance.copySensitive(
      context,
      text: _entry!.decryptedPassword!,
      label: 'Password',
    );
  }

  Future<void> _copyUsername() async {
    final text = _entry?.decryptedUsername ?? _entry?.decryptedEmail;
    if (text == null || text.isEmpty) return;
    await ClipboardSecurityService.instance.copySensitive(
      context,
      text: text,
      label: 'Username',
    );
  }

  Future<void> _toggleFavorite() async {
    if (_entry == null) return;
    final repo = ref.read(passwordRepositoryProvider);
    final newFav = !_entry!.isFavorite;
    await repo.toggleFavorite(_entry!.id, newFav);
    setState(() {
      _entry = _entry!.copyWith(isFavorite: newFav);
    });
    ref.invalidate(allPasswordsProvider);
    ref.invalidate(favoritePasswordsProvider);
  }

  Future<void> _deleteEntry() async {
    final colors = context.themeColors;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Password?'),
        content: Text(
          'Are you sure you want to permanently delete "${_entry?.title}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: colors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final gate = ref.read(authenticationGateProvider);
      final verified = await gate.authenticateForAction(
        context,
        action: PendingVaultAction(
          type: VaultActionType.deletePassword,
          targetId: widget.passwordId,
          targetName: _entry?.title ?? 'Password',
          returnRoute: '/passwords',
        ),
        title: 'Authorize Password Deletion',
        reason:
            'Confirm with biometrics to delete password "${_entry?.title}".',
      );
      if (!verified || !mounted) return;

      final repo = ref.read(passwordRepositoryProvider);
      await repo.deleteEntry(_entry!.id);
      ref.invalidate(allPasswordsProvider);
      ref.invalidate(favoritePasswordsProvider);
      ref.invalidate(passwordSecurityAuditProvider);
      if (mounted) context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: CircularProgressIndicator(color: colors.primaryAccent),
        ),
      );
    }

    if (_entry == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Password Details')),
        body: const Center(child: Text('Password record not found.')),
      );
    }

    final entry = _entry!;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text(entry.title),
        actions: [
          IconButton(
            icon: Icon(
              entry.isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
              color: entry.isFavorite ? Colors.amber : null,
            ),
            tooltip: 'Favorite',
            onPressed: _toggleFavorite,
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
            onPressed: () async {
              final verified = await ref
                  .read(authenticationGateProvider)
                  .authenticateForAction(
                    context,
                    action: PendingVaultAction(
                      type: VaultActionType.editPassword,
                      targetId: entry.id,
                      targetName: entry.title,
                      returnRoute: '/password/${entry.id}',
                    ),
                    title: 'Authorize Password Edit',
                    reason:
                        'Confirm with biometrics before editing this password.',
                  );
              if (!verified) return;
              if (context.mounted) {
                await context.push('/edit-password/${entry.id}');
                if (mounted) _loadEntry();
              }
            },
          ),
          IconButton(
            icon: Icon(Icons.delete_outline_rounded, color: colors.error),
            tooltip: 'Delete',
            onPressed: _deleteEntry,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        children: [
          // Header card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colors.cardBackground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.cardBorder),
            ),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: colors.primaryAccent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.key_rounded,
                      color: colors.primaryAccent,
                      size: 28,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (entry.websiteUrl != null &&
                          entry.websiteUrl!.isNotEmpty)
                        Text(
                          entry.websiteUrl!,
                          style: TextStyle(
                            fontSize: 13,
                            color: colors.primaryAccent,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Username / Email Tile
          if (entry.decryptedUsername != null &&
              entry.decryptedUsername!.isNotEmpty)
            _buildDetailTile(
              context,
              title: 'Username',
              value: entry.decryptedUsername!,
              icon: Icons.person_outline_rounded,
              onCopy: _copyUsername,
              colors: colors,
            ),
          if (entry.decryptedEmail != null && entry.decryptedEmail!.isNotEmpty)
            _buildDetailTile(
              context,
              title: 'Email Address',
              value: entry.decryptedEmail!,
              icon: Icons.email_outlined,
              onCopy: () => ClipboardSecurityService.instance.copySensitive(
                context,
                text: entry.decryptedEmail!,
                label: 'Email',
              ),
              colors: colors,
            ),

          // Sensitive Password Tile
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.cardBackground,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _isPasswordRevealed
                    ? colors.primaryAccent.withOpacity(0.5)
                    : colors.cardBorder,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 18,
                          color: colors.primaryAccent,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Password',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: _revealPassword,
                          icon: Icon(
                            _isPasswordRevealed
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            size: 16,
                          ),
                          label: Text(_isPasswordRevealed ? 'Hide' : 'Reveal'),
                          style: TextButton.styleFrom(
                            foregroundColor: colors.primaryAccent,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy_rounded, size: 18),
                          tooltip: 'Copy with 30s auto-clear',
                          onPressed: _copyPassword,
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SelectableText(
                  _isPasswordRevealed
                      ? (entry.decryptedPassword ?? '')
                      : '••••••••••••••••',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: _isPasswordRevealed ? 0.5 : 2.5,
                    fontFamily: _isPasswordRevealed ? 'monospace' : null,
                  ),
                ),
                if (_isPasswordRevealed) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.timer_outlined,
                        size: 13,
                        color: colors.warning,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Visible for this screen session. Re-hides automatically.',
                        style: TextStyle(fontSize: 11, color: colors.warning),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // Notes
          if (entry.decryptedNotes != null && entry.decryptedNotes!.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.cardBackground,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colors.cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.notes_rounded,
                        size: 18,
                        color: colors.primaryAccent,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Notes (AES-256-GCM Encrypted)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SelectableText(
                    entry.decryptedNotes!,
                    style: const TextStyle(fontSize: 14, height: 1.4),
                  ),
                ],
              ),
            ),

          // Metadata Info
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.cardBackground.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Added',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    ),
                    Text(
                      DateFormatter.formatDate(entry.createdAt),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Last Modified',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    ),
                    Text(
                      DateFormatter.formatDate(entry.updatedAt),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildDetailTile(
    BuildContext context, {
    required String title,
    required String value,
    required IconData icon,
    required VoidCallback onCopy,
    required AppThemeColors colors,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.cardBorder),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: colors.primaryAccent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 11, color: colors.textSecondary),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded, size: 18),
            tooltip: 'Copy with 30s auto-clear',
            onPressed: onCopy,
          ),
        ],
      ),
    );
  }
}
