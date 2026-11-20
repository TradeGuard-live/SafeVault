import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/security/clipboard_security_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_formatter.dart';
import '../../authentication/presentation/auth_providers.dart';
import '../../authentication/presentation/two_factor_verification_dialog.dart';
import '../domain/bank_account_model.dart';

class BankAccountDetailsScreen extends ConsumerStatefulWidget {
  final String accountId;

  const BankAccountDetailsScreen({super.key, required this.accountId});

  @override
  ConsumerState<BankAccountDetailsScreen> createState() => _BankAccountDetailsScreenState();
}

class _BankAccountDetailsScreenState extends ConsumerState<BankAccountDetailsScreen> {
  bool _isDetailsRevealed = false;
  BankAccountModel? _account;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAccount();
  }

  @override
  void deactivate() {
    // Re-hide account number when navigating away
    _isDetailsRevealed = false;
    super.deactivate();
  }

  Future<void> _loadAccount() async {
    final session = ref.read(vaultSessionProvider);
    if (!session.isUnlocked || session.masterKey == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final repo = ref.read(bankVaultRepositoryProvider);
    final account = await repo.getAccountById(widget.accountId, session.masterKey!);
    if (mounted) {
      setState(() {
        _account = account;
        _isLoading = false;
      });
    }
  }

  Future<void> _revealDetails() async {
    if (_isDetailsRevealed) {
      setState(() => _isDetailsRevealed = false);
      return;
    }

    // Mandatory Two-Factor Verification (Biometric + 6-digit PIN)
    final verified = await TwoFactorVerificationDialog.verify(
      context,
      title: 'Reveal Bank Account',
      reason: 'Factor 1: Authenticate with biometrics to reveal full bank account details',
    );

    if (verified && mounted) {
      setState(() => _isDetailsRevealed = true);
    }
  }

  Future<void> _copyAccountNumber() async {
    if (_account?.decryptedAccountNumber == null) return;
    await ClipboardSecurityService.instance.copySensitive(
      context,
      text: _account!.decryptedAccountNumber!,
      label: 'Account Number',
    );
  }

  Future<void> _copyIFSC() async {
    if (_account?.decryptedIFSC == null) return;
    await ClipboardSecurityService.instance.copySensitive(
      context,
      text: _account!.decryptedIFSC!,
      label: 'IFSC Code',
    );
  }

  Future<void> _toggleFavorite() async {
    if (_account == null) return;
    final repo = ref.read(bankVaultRepositoryProvider);
    final newFav = !_account!.isFavorite;
    await repo.toggleFavorite(_account!.id, newFav);
    setState(() {
      _account = _account!.copyWith(isFavorite: newFav);
    });
    ref.invalidate(allBankAccountsProvider);
    ref.invalidate(favoriteBankAccountsProvider);
  }

  Future<void> _deleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Bank Account?'),
        content: Text('Are you sure you want to permanently delete "${_account?.bankName}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.errorRed),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final repo = ref.read(bankVaultRepositoryProvider);
      await repo.deleteAccount(_account!.id);
      ref.invalidate(allBankAccountsProvider);
      ref.invalidate(favoriteBankAccountsProvider);
      if (mounted) context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator(color: AppColors.primaryTeal)),
      );
    }

    if (_account == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Bank Details')),
        body: const Center(child: Text('Bank account not found.')),
      );
    }

    final account = _account!;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.lightBackground,
      appBar: AppBar(
        title: Text(account.bankName),
        actions: [
          IconButton(
            icon: Icon(account.isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                color: account.isFavorite ? Colors.amber : null),
            tooltip: 'Favorite',
            onPressed: _toggleFavorite,
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
            onPressed: () async {
              await context.push('/edit-bank-account/${account.id}');
              _loadAccount();
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.errorRed),
            tooltip: 'Delete',
            onPressed: _deleteAccount,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        children: [
          // Bank Header card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkCard : AppColors.lightCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.primaryTeal.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Center(
                    child: Icon(Icons.account_balance_rounded, color: AppColors.primaryTeal, size: 28),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account.bankName,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        account.nickname ?? '${account.accountType.toUpperCase()} ACCOUNT',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Account Number Card (Masked by default)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkCard : AppColors.lightCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _isDetailsRevealed
                    ? AppColors.primaryTeal.withOpacity(0.5)
                    : isDark
                        ? AppColors.darkBorder
                        : AppColors.lightBorder,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.numbers_rounded, size: 18, color: AppColors.primaryTeal),
                        SizedBox(width: 8),
                        Text(
                          'Account Number',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: _revealDetails,
                          icon: Icon(
                            _isDetailsRevealed ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                            size: 16,
                          ),
                          label: Text(_isDetailsRevealed ? 'Hide' : 'Reveal (2FA)'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.primaryTeal,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy_rounded, size: 18),
                          tooltip: 'Copy with 30s auto-clear',
                          onPressed: _copyAccountNumber,
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SelectableText(
                  _isDetailsRevealed
                      ? (account.decryptedAccountNumber ?? '')
                      : account.maskedAccountNumber,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: _isDetailsRevealed ? 0.8 : 2.0,
                    fontFamily: _isDetailsRevealed ? 'monospace' : null,
                  ),
                ),
                if (_isDetailsRevealed) ...[
                  const SizedBox(height: 8),
                  const Row(
                    children: [
                      Icon(Icons.timer_outlined, size: 13, color: AppColors.statusWarning),
                      SizedBox(width: 4),
                      Text(
                        'Full number revealed for this screen view. Re-hides automatically.',
                        style: TextStyle(fontSize: 11, color: AppColors.statusWarning),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          // IFSC / SWIFT Code Tile
          if (account.decryptedIFSC != null && account.decryptedIFSC!.isNotEmpty)
            _buildDetailTile(
              context,
              title: 'IFSC / Routing / SWIFT Code',
              value: account.decryptedIFSC!,
              icon: Icons.code_rounded,
              onCopy: _copyIFSC,
              isDark: isDark,
            ),

          // Account Holder Name Tile
          if (account.decryptedAccountHolder != null && account.decryptedAccountHolder!.isNotEmpty)
            _buildDetailTile(
              context,
              title: 'Account Holder Name',
              value: account.decryptedAccountHolder!,
              icon: Icons.person_outline_rounded,
              onCopy: () => ClipboardSecurityService.instance.copySensitive(
                context,
                text: account.decryptedAccountHolder!,
                label: 'Account Holder Name',
              ),
              isDark: isDark,
            ),

          // Branch Name Tile
          if (account.decryptedBranch != null && account.decryptedBranch!.isNotEmpty)
            _buildDetailTile(
              context,
              title: 'Branch Name',
              value: account.decryptedBranch!,
              icon: Icons.location_city_outlined,
              onCopy: () => ClipboardSecurityService.instance.copySensitive(
                context,
                text: account.decryptedBranch!,
                label: 'Branch Name',
              ),
              isDark: isDark,
            ),

          // Notes
          if (account.decryptedNotes != null && account.decryptedNotes!.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkCard : AppColors.lightCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.notes_rounded, size: 18, color: AppColors.primaryTeal),
                      SizedBox(width: 8),
                      Text('Notes (AES-256-GCM Encrypted)',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SelectableText(
                    account.decryptedNotes!,
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
              color: (isDark ? AppColors.darkCard : AppColors.lightCard).withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Created',
                        style: TextStyle(
                            fontSize: 12,
                            color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary)),
                    Text(DateFormatter.formatDate(account.createdAt),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Updated',
                        style: TextStyle(
                            fontSize: 12,
                            color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary)),
                    Text(DateFormatter.formatDate(account.updatedAt),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
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
    required bool isDark,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.primaryTeal),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  value,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
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

