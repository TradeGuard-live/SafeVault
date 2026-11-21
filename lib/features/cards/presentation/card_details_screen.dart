import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/security/authentication_gate.dart';
import '../../../core/security/clipboard_security_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../../core/utils/date_formatter.dart';
import '../../authentication/presentation/auth_providers.dart';
import '../domain/payment_card_model.dart';
import 'widgets/payment_card_widget.dart';

class CardDetailsScreen extends ConsumerStatefulWidget {
  final String cardId;

  const CardDetailsScreen({super.key, required this.cardId});

  @override
  ConsumerState<CardDetailsScreen> createState() => _CardDetailsScreenState();
}

class _CardDetailsScreenState extends ConsumerState<CardDetailsScreen> {
  bool _isDetailsRevealed = false;
  PaymentCardModel? _card;
  bool _isLoading = true;
  Timer? _visibilityTimer;

  @override
  void initState() {
    super.initState();
    _loadCard();
  }

  @override
  void deactivate() {
    _visibilityTimer?.cancel();
    _isDetailsRevealed = false;
    super.deactivate();
  }

  @override
  void dispose() {
    _visibilityTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadCard() async {
    final session = ref.read(vaultSessionProvider);
    if (!session.isUnlocked || session.masterKey == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final repo = ref.read(cardRepositoryProvider);
    final card = await repo.getCardById(widget.cardId, session.masterKey!);
    if (mounted) {
      setState(() {
        _card = card;
        _isLoading = false;
      });

      // Resume any pending action targeting this card
      final gate = ref.read(authenticationGateProvider);
      final pending = gate.consumePendingAction(widget.cardId);
      if (pending != null && mounted) {
        if (pending.type == VaultActionType.revealCardDetails) {
          setState(() => _isDetailsRevealed = true);
        } else if (pending.type == VaultActionType.copyCardDetails &&
            card != null) {
          _copyCardNumber();
        } else if (pending.type == VaultActionType.editCard) {
          context.push('/edit-card/${widget.cardId}');
        } else if (pending.type == VaultActionType.deleteCard) {
          _confirmAndDeleteCard();
        }
      }
    }
  }

  Future<void> _revealDetails() async {
    if (_isDetailsRevealed) {
      setState(() => _isDetailsRevealed = false);
      return;
    }

    final gate = ref.read(authenticationGateProvider);
    final verified = await gate.authenticateForAction(
      context,
      action: PendingVaultAction(
        type: VaultActionType.revealCardDetails,
        targetId: widget.cardId,
        targetName: _card?.cardNickname ?? 'Payment Card',
        returnRoute: '/card/${widget.cardId}',
      ),
    );

    if (verified && mounted) {
      setState(() => _isDetailsRevealed = true);
      _visibilityTimer?.cancel();
      _visibilityTimer = Timer(const Duration(seconds: 60), () {
        if (mounted) {
          setState(() => _isDetailsRevealed = false);
        }
      });
    }
  }

  Future<void> _copyCardNumber() async {
    if (_card == null) return;
    if (!_isDetailsRevealed) {
      final gate = ref.read(authenticationGateProvider);
      final verified = await gate.authenticateForAction(
        context,
        action: PendingVaultAction(
          type: VaultActionType.copyCardDetails,
          targetId: widget.cardId,
          targetName: _card?.cardNickname ?? 'Payment Card',
          returnRoute: '/card/${widget.cardId}',
        ),
      );
      if (!mounted || !verified) return;
    }

    final numberToCopy = _card!.decryptedCardNumber ?? _card!.lastFourDigits;
    await ClipboardSecurityService.instance.copySensitive(
      context,
      text: numberToCopy,
      label: 'Card Number',
    );
  }

  Future<void> _copyMaskedNumber() async {
    if (_card == null) return;
    await ClipboardSecurityService.instance.copySensitive(
      context,
      text: _card!.maskedCardNumber,
      label: 'Masked Card Number',
    );
  }

  Future<void> _copyLast4Digits() async {
    if (_card == null) return;
    await ClipboardSecurityService.instance.copySensitive(
      context,
      text: _card!.lastFourDigits,
      label: 'Last 4 Digits',
    );
  }

  Future<void> _toggleFavorite() async {
    if (_card == null) return;
    final repo = ref.read(cardRepositoryProvider);
    final newFav = !_card!.isFavorite;
    await repo.toggleFavorite(_card!.id, newFav);
    setState(() {
      _card = _card!.copyWith(isFavorite: newFav);
    });
    ref.invalidate(allPaymentCardsProvider);
    ref.invalidate(favoritePaymentCardsProvider);
  }

  Future<void> _requestEdit() async {
    if (_card == null) return;
    final gate = ref.read(authenticationGateProvider);
    final verified = await gate.authenticateForAction(
      context,
      action: PendingVaultAction(
        type: VaultActionType.editCard,
        targetId: widget.cardId,
        targetName: _card?.cardNickname ?? 'Payment Card',
        returnRoute: '/card/${widget.cardId}',
      ),
    );

    if (verified && mounted) {
      await context.push('/edit-card/${widget.cardId}');
      _loadCard();
    }
  }

  Future<void> _requestDelete() async {
    if (_card == null) return;
    final gate = ref.read(authenticationGateProvider);
    final verified = await gate.authenticateForAction(
      context,
      action: PendingVaultAction(
        type: VaultActionType.deleteCard,
        targetId: widget.cardId,
        targetName: _card?.cardNickname ?? 'Payment Card',
        returnRoute: '/card/${widget.cardId}',
      ),
    );

    if (verified && mounted) {
      _confirmAndDeleteCard();
    }
  }

  Future<void> _confirmAndDeleteCard() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Payment Card'),
        content: Text(
          'Are you sure you want to permanently remove "${_card?.cardNickname ?? 'this card'}" from your vault?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final repo = ref.read(cardRepositoryProvider);
      await repo.deleteCard(widget.cardId);
      ref.invalidate(allPaymentCardsProvider);
      ref.invalidate(favoritePaymentCardsProvider);
      ref.invalidate(expiringPaymentCardsProvider);

      if (mounted) {
        context.pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(title: const Text('Card Details')),
        body: Center(
          child: CircularProgressIndicator(color: colors.primaryAccent),
        ),
      );
    }

    if (_card == null) {
      return Scaffold(
        backgroundColor: colors.background,
        appBar: AppBar(title: const Text('Card Details')),
        body: Center(
          child: Text(
            'Card not found or could not be loaded.',
            style: TextStyle(color: colors.textSecondary),
          ),
        ),
      );
    }

    final card = _card!;
    final isExpired = card.isExpired();
    final isExpiringSoon = card.isExpiringSoon();

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text(
          card.cardNickname,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: Icon(
              card.isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
              color: card.isFavorite ? Colors.amber : colors.textSecondary,
            ),
            tooltip: 'Favorite',
            onPressed: _toggleFavorite,
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit Card',
            onPressed: _requestEdit,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
            tooltip: 'Delete Card',
            onPressed: _requestDelete,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        children: [
          // Visual Card Widget
          Center(
            child: PaymentCardWidget(
              card: card,
              isInteractive: false,
              showFullWidth: true,
              isRevealed: _isDetailsRevealed,
            ),
          ),
          const SizedBox(height: 20),

          // Expiry Status Banner (if expired or expiring soon)
          if (isExpired)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: colors.error.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.error.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    color: colors.error,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'This card expired on ${card.formattedExpiry}. Contact ${card.bankName} if a renewed replacement has been issued.',
                      style: TextStyle(
                        color: colors.error,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else if (isExpiringSoon)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.amber,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'This card expires soon (${card.formattedExpiry}, ${card.daysRemaining()} days remaining).',
                      style: const TextStyle(
                        color: Colors.amber,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Security 2FA Reveal Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: colors.cardBackground,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.cardBorder),
            ),
            child: Row(
              children: [
                Icon(
                  _isDetailsRevealed
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                  color: colors.primaryAccent,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _isDetailsRevealed
                        ? 'Decrypted details active (Auto-conceals in 60s)'
                        : 'Encrypted fields concealed',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _revealDetails,
                  child: Text(_isDetailsRevealed ? 'Hide' : 'Reveal (2FA)'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Card Information Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.cardBackground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailRow(
                  label: 'Card Nickname',
                  value: card.cardNickname,
                  colors: colors,
                ),
                const Divider(height: 20),
                _buildDetailRow(
                  label: 'Bank / Issuer',
                  value: card.bankName,
                  colors: colors,
                ),
                const Divider(height: 20),
                _buildDetailRow(
                  label: 'Card Type',
                  value: card.cardType.displayName,
                  colors: colors,
                ),
                const Divider(height: 20),
                _buildDetailRow(
                  label: 'Payment Network',
                  value: card.network.displayName,
                  colors: colors,
                ),
                const Divider(height: 20),
                _buildDetailRow(
                  label: 'Card Number',
                  value: _isDetailsRevealed
                      ? (card.decryptedCardNumber != null
                            ? card.formattedFullCardNumber
                            : card.maskedCardNumber)
                      : card.maskedCardNumber,
                  colors: colors,
                  trailing: IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    tooltip: 'Copy Card Number',
                    onPressed: _copyCardNumber,
                  ),
                ),
                if (card.formattedStartDate != null) ...[
                  const Divider(height: 20),
                  _buildDetailRow(
                    label: 'Start Date (Valid From)',
                    value: card.formattedStartDate!,
                    colors: colors,
                  ),
                ],
                const Divider(height: 20),
                _buildDetailRow(
                  label: 'Expiry Date (Valid Thru)',
                  value:
                      '${card.formattedExpiry} (${card.expiryMonth}/${card.expiryYear})',
                  colors: colors,
                  badge: isExpired
                      ? _buildBadge('EXPIRED', Colors.red)
                      : isExpiringSoon
                      ? _buildBadge('EXPIRING SOON', Colors.amber)
                      : _buildBadge('VALID', Colors.green),
                ),
                const Divider(height: 20),
                _buildDetailRow(
                  label: 'Cardholder Name',
                  value: _isDetailsRevealed
                      ? (card.decryptedCardholderName ?? 'None specified')
                      : (card.decryptedCardholderName != null
                            ? '•••••••••••• (Tap Reveal)'
                            : 'None specified'),
                  colors: colors,
                ),
                if (card.decryptedNotes != null &&
                    card.decryptedNotes!.isNotEmpty) ...[
                  const Divider(height: 20),
                  _buildDetailRow(
                    label: 'Notes',
                    value: _isDetailsRevealed
                        ? card.decryptedNotes!
                        : '•••••••••••• (Tap Reveal)',
                    colors: colors,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Metadata & Audit Timestamps
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.cardBackground,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.cardBorder),
            ),
            child: Column(
              children: [
                _buildAuditRow(
                  'Created',
                  DateFormatter.formatDateTimeDisplay(card.createdAt),
                  colors,
                ),
                const SizedBox(height: 6),
                _buildAuditRow(
                  'Last Updated',
                  DateFormatter.formatDateTimeDisplay(card.updatedAt),
                  colors,
                ),
                const SizedBox(height: 6),
                _buildAuditRow(
                  'Encryption',
                  'AES-256-GCM + Hardware Keystore AAD',
                  colors,
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildDetailRow({
    required String label,
    required String value,
    required AppThemeColors colors,
    Widget? trailing,
    Widget? badge,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          flex: 2,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              color: colors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (badge != null) ...[const SizedBox(width: 6), badge],
              if (trailing != null) trailing,
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAuditRow(String label, String value, AppThemeColors colors) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11.5, color: colors.textSecondary),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 11.5,
            color: colors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.4), width: 0.8),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
