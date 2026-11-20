import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'rupee_bunny_mascot.dart';

class EmptyStateView extends StatelessWidget {
  final IconData? icon;
  final MascotPose? mascotPose;
  final String title;
  final String description;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const EmptyStateView({
    super.key,
    this.icon,
    this.mascotPose = MascotPose.thinking,
    required this.title,
    String? description,
    String? message,
    this.actionLabel,
    this.onAction,
  })  : message = message ?? description,
        description = description ?? message ?? '';

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (mascotPose != null)
              RupeeBunnyMascot(
                pose: mascotPose!,
                size: 110,
              )
            else
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.primaryAccent.withOpacity(0.12),
                  border: Border.all(
                    color: colors.primaryAccent.withOpacity(0.25),
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  icon ?? Icons.inbox_rounded,
                  size: 38,
                  color: colors.primaryAccent,
                ),
              ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: colors.textSecondary,
                height: 1.4,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: onAction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.primaryAccent,
                  foregroundColor: colors.onPrimaryAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                icon: const Icon(Icons.add, size: 18),
                label: Text(
                  actionLabel!,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
