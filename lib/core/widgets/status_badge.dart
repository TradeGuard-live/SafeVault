import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

enum ExpiryStatus {
  valid,
  expiringSoon,
  expired,
  none,
}

class StatusBadge extends StatelessWidget {
  final String label;
  final Color backgroundColor;
  final Color textColor;
  final IconData? icon;

  const StatusBadge({
    super.key,
    required this.label,
    required this.backgroundColor,
    required this.textColor,
    this.icon,
  });

  factory StatusBadge.fromExpiry(DateTime? expiryDate) {
    if (expiryDate == null) {
      return const StatusBadge(
        label: 'No Expiry',
        backgroundColor: Color(0x1594A3B8),
        textColor: AppColors.darkTextSecondary,
        icon: Icons.all_inclusive,
      );
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final expiry = DateTime(expiryDate.year, expiryDate.month, expiryDate.day);
    final days = expiry.difference(today).inDays;

    if (days < 0) {
      return const StatusBadge(
        label: 'Expired',
        backgroundColor: AppColors.badgeExpiredBg,
        textColor: AppColors.statusDanger,
        icon: Icons.error_outline,
      );
    } else if (days <= 30) {
      return StatusBadge(
        label: days == 0 ? 'Expires Today' : '$days Days Left',
        backgroundColor: AppColors.badgeExpiringSoonBg,
        textColor: AppColors.statusWarning,
        icon: Icons.warning_amber_rounded,
      );
    } else {
      return const StatusBadge(
        label: 'Valid',
        backgroundColor: AppColors.badgeValidBg,
        textColor: AppColors.statusSuccess,
        icon: Icons.check_circle_outline,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: textColor),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

