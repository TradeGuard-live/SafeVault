import 'package:flutter/material.dart';

import '../../domain/payment_card_model.dart';

class PaymentCardWidget extends StatelessWidget {
  final PaymentCardModel card;
  final VoidCallback? onTap;
  final VoidCallback? onFavoriteToggle;
  final bool isInteractive;
  final bool showFullWidth;
  final bool isRevealed;

  const PaymentCardWidget({
    super.key,
    required this.card,
    this.onTap,
    this.onFavoriteToggle,
    this.isInteractive = true,
    this.showFullWidth = false,
    this.isRevealed = false,
  });

  @override
  Widget build(BuildContext context) {
    final preset = CardVisualPreset.getPreset(card.cardColor);
    final gradientColors = preset.gradientColors.map((c) => Color(c)).toList();
    final textColor = Color(preset.textColor);

    final cardContent = Container(
      constraints: BoxConstraints(
        minHeight: 195,
        maxHeight: 220,
        maxWidth: showFullWidth ? double.infinity : 400,
      ),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
        boxShadow: [
          BoxShadow(
            color: gradientColors.first.withOpacity(0.35),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: Colors.white.withOpacity(0.15), width: 1),
      ),
      child: Stack(
        children: [
          // Subtle decorative background curves
          Positioned(
            right: -30,
            bottom: -30,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.04),
              ),
            ),
          ),
          Positioned(
            right: 20,
            bottom: -40,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.03),
              ),
            ),
          ),

          // Main Card Content
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Top Row: Bank Name + Card Type Pill + Favorite Icon
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      card.bankName.toUpperCase(),
                      style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        letterSpacing: 1.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Card Type Pill (CREDIT / DEBIT)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.25),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      card.cardType.shortLabel,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  if (onFavoriteToggle != null || card.isFavorite) ...[
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: onFavoriteToggle,
                      child: Icon(
                        card.isFavorite
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        color: card.isFavorite
                            ? const Color(0xFFFFD700)
                            : textColor.withOpacity(0.5),
                        size: 22,
                      ),
                    ),
                  ],
                ],
              ),

              // Middle Row: EMV Chip & Contactless Wave Indicator
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Metallic EMV Chip
                  _buildEmvChip(),
                  const SizedBox(width: 12),
                  // Contactless Wave
                  Icon(
                    Icons.contactless_rounded,
                    color: textColor.withOpacity(0.7),
                    size: 22,
                  ),
                  const Spacer(),
                  // Nickname Tag
                  if (card.cardNickname.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        card.cardNickname,
                        style: TextStyle(
                          color: textColor.withOpacity(0.85),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),

              // Card Number (Masked by default, or Full PAN when isRevealed is true)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  isRevealed
                      ? card.formattedFullCardNumber
                      : '••••  ••••  ••••  ${card.lastFourDigits}',
                  style: TextStyle(
                    color: textColor,
                    fontSize: isRevealed ? 17 : 19,
                    fontWeight: FontWeight.w600,
                    letterSpacing: isRevealed ? 1.8 : 2.5,
                    fontFamily: 'monospace',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // Bottom Row: Cardholder Name, Dates, and Network Logo Badge
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Cardholder
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'CARDHOLDER',
                          style: TextStyle(
                            color: textColor.withOpacity(0.6),
                            fontSize: 8.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          (card.decryptedCardholderName != null &&
                                  card.decryptedCardholderName!.isNotEmpty)
                              ? card.decryptedCardholderName!.toUpperCase()
                              : 'VALUED CARDHOLDER',
                          style: TextStyle(
                            color: textColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),

                  // Start Date (Valid From) if present
                  if (card.formattedStartDate != null) ...[
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'VALID FROM',
                            style: TextStyle(
                              color: textColor.withOpacity(0.6),
                              fontSize: 8,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.6,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            card.formattedStartDate!,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Expiry
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'EXPIRES',
                          style: TextStyle(
                            color: textColor.withOpacity(0.6),
                            fontSize: 8.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              card.formattedExpiry,
                              style: TextStyle(
                                color: card.isExpired()
                                    ? const Color(0xFFEF4444)
                                    : textColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                            if (card.isExpired()) ...[
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEF4444),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'EXPIRED',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 8,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Network Badge
                  _buildNetworkBadge(card.network, textColor),
                ],
              ),
            ],
          ),
        ],
      ),
    );

    if (!isInteractive || onTap == null) {
      return cardContent;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: cardContent,
    );
  }

  Widget _buildEmvChip() {
    return Container(
      width: 36,
      height: 28,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFDF7A), Color(0xFFD4AF37), Color(0xFFA67C1E)],
        ),
        border: Border.all(color: const Color(0xFF8A6510), width: 0.8),
      ),
      child: Stack(
        children: [
          Center(
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                border: Border.all(
                  color: const Color(0xFF7A580A).withOpacity(0.5),
                  width: 0.8,
                ),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 13,
            child: Container(
              height: 0.8,
              color: const Color(0xFF7A580A).withOpacity(0.5),
            ),
          ),
          Positioned(
            top: 0,
            bottom: 0,
            left: 17,
            child: Container(
              width: 0.8,
              color: const Color(0xFF7A580A).withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkBadge(CardNetwork network, Color textColor) {
    switch (network) {
      case CardNetwork.visa:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.9),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text(
            'VISA',
            style: TextStyle(
              color: Color(0xFF1A1F71),
              fontSize: 13,
              fontWeight: FontWeight.w900,
              fontStyle: FontStyle.italic,
              letterSpacing: 1.0,
            ),
          ),
        );
      case CardNetwork.mastercard:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFEB001B),
              ),
            ),
            Transform.translate(
              offset: const Offset(-6, 0),
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFF79E1B).withOpacity(0.9),
                ),
              ),
            ),
          ],
        );
      case CardNetwork.rupay:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.9),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Ru',
                style: TextStyle(
                  color: Color(0xFF097939),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                'Pay',
                style: TextStyle(
                  color: Color(0xFF005696),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        );
      case CardNetwork.amex:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFF007BC1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: Colors.white.withOpacity(0.8),
              width: 0.8,
            ),
          ),
          child: const Text(
            'AMEX',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
        );
      case CardNetwork.other:
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            'CARD',
            style: TextStyle(
              color: textColor,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        );
    }
  }
}
