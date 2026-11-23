import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum ExpiryStatus { valid, expiringSoon, expired, none }

class StatusBadge extends StatelessWidget {
  final String label;
  final Color? backgroundColor;
  final Color? textColor;
  final IconData? icon;
  final ExpiryStatus status;

  const StatusBadge({
    super.key,
    required this.label,
    this.backgroundColor,
    this.textColor,
    this.icon,
    this.status = ExpiryStatus.none,
  });

  factory StatusBadge.fromExpiry(DateTime? expiryDate) {
    if (expiryDate == null) {
      return const StatusBadge(
        label: 'No Expiry',
        status: ExpiryStatus.none,
        icon: Icons.all_inclusive_rounded,
      );
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final expiry = DateTime(expiryDate.year, expiryDate.month, expiryDate.day);
    final days = expiry.difference(today).inDays;

    if (days < 0) {
      return const StatusBadge(
        label: 'Expired',
        status: ExpiryStatus.expired,
        icon: Icons.error_outline_rounded,
      );
    } else if (days <= 30) {
      return StatusBadge(
        label: days == 0 ? 'Expires Today' : '$days Days Left',
        status: ExpiryStatus.expiringSoon,
        icon: Icons.warning_amber_rounded,
      );
    } else {
      return const StatusBadge(
        label: 'Valid',
        status: ExpiryStatus.valid,
        icon: Icons.check_circle_outline_rounded,
      );
    }
  }

  factory StatusBadge.fromTemporary(DateTime? expiresAt, {bool isTemporary = true}) {
    if (!isTemporary || expiresAt == null) {
      return const StatusBadge(
        label: 'Permanent',
        status: ExpiryStatus.none,
        icon: Icons.shield_outlined,
      );
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final expiry = DateTime(expiresAt.year, expiresAt.month, expiresAt.day);
    final days = expiry.difference(today).inDays;

    if (days < 0) {
      return const StatusBadge(
        label: 'Expired',
        status: ExpiryStatus.expired,
        icon: Icons.hourglass_disabled_rounded,
      );
    } else if (days == 0) {
      return const StatusBadge(
        label: 'Expires Today',
        status: ExpiryStatus.expired,
        icon: Icons.warning_rounded,
      );
    } else if (days == 1) {
      return const StatusBadge(
        label: 'Expires Tomorrow',
        status: ExpiryStatus.expiringSoon,
        icon: Icons.access_time_filled_rounded,
      );
    } else if (days <= 7) {
      return StatusBadge(
        label: 'Expires in $days days',
        status: ExpiryStatus.expiringSoon,
        icon: Icons.hourglass_bottom_rounded,
      );
    } else {
      return StatusBadge(
        label: 'Temporary • $days d left',
        status: ExpiryStatus.valid,
        icon: Icons.hourglass_top_rounded,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;

    Color bg;
    Color fg;

    switch (status) {
      case ExpiryStatus.valid:
        bg = backgroundColor ?? colors.successContainer;
        fg = textColor ?? colors.success;
        break;
      case ExpiryStatus.expiringSoon:
        bg = backgroundColor ?? colors.warningContainer;
        fg =
            textColor ??
            (colors.isDark ? colors.warning : const Color(0xFFD97706));
        break;
      case ExpiryStatus.expired:
        bg = backgroundColor ?? colors.errorContainer;
        fg = textColor ?? colors.error;
        break;
      case ExpiryStatus.none:
        bg =
            backgroundColor ??
            (colors.isDark ? const Color(0x3394A3B8) : const Color(0x1594A3B8));
        fg = textColor ?? colors.textSecondary;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withOpacity(0.2), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
