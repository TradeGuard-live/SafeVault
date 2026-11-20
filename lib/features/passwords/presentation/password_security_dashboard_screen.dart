import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../authentication/presentation/auth_providers.dart';
import '../data/password_security_analyzer.dart';

class PasswordSecurityDashboardScreen extends ConsumerWidget {
  const PasswordSecurityDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final auditAsync = ref.watch(passwordSecurityAuditProvider);
    final passwordsAsync = ref.watch(allPasswordsProvider);

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.lightBackground,
      appBar: AppBar(
        title: const Text('Security Audit'),
      ),
      body: auditAsync.when(
        data: (audit) {
          final score = audit.overallScore;
          final scoreColor = score >= 80
              ? AppColors.successGreen
              : score >= 50
                  ? AppColors.statusWarning
                  : AppColors.errorRed;

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            children: [
              // Security Score Hero Card
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkCard : AppColors.lightCard,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: scoreColor.withOpacity(0.35), width: 1.5),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: scoreColor.withOpacity(0.12),
                        shape: BoxShape.circle,
                        border: Border.all(color: scoreColor.withOpacity(0.4), width: 3),
                      ),
                      child: Center(
                        child: Text(
                          '$score',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: scoreColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      score >= 80
                          ? 'Vault Health: Excellent'
                          : score >= 50
                              ? 'Vault Health: Needs Attention'
                              : 'Vault Health: Vulnerable',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Evaluated across ${audit.totalPasswords} saved password records.',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Metrics Breakdown Grid
              Row(
                children: [
                  Expanded(
                    child: _buildStatTile(
                      'Reused',
                      audit.reusedCount.toString(),
                      audit.reusedCount > 0 ? AppColors.errorRed : AppColors.successGreen,
                      Icons.repeat_rounded,
                      isDark,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildStatTile(
                      'Short (<8)',
                      audit.shortCount.toString(),
                      audit.shortCount > 0 ? AppColors.errorRed : AppColors.successGreen,
                      Icons.warning_amber_rounded,
                      isDark,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildStatTile(
                      'Weak',
                      audit.weakCount.toString(),
                      audit.weakCount > 0 ? AppColors.statusWarning : AppColors.successGreen,
                      Icons.shield_outlined,
                      isDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Issues List
              const Text(
                'Actionable Recommendations',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),

              if (audit.issues.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkCard : AppColors.lightCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.verified_user_rounded, color: AppColors.successGreen, size: 28),
                      SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          'No security issues found. All your passwords are long, strong, and unique.',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                )
              else
                ...audit.issues.map((issue) {
                  return _buildIssueCard(context, issue, passwordsAsync.valueOrNull ?? [], isDark);
                }),

              const SizedBox(height: 24),

              // Offline privacy notice
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkCard : AppColors.lightCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.privacy_tip_outlined,
                        color: AppColors.primaryTeal, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '100% Offline Analysis: Vault audits your credentials entirely in local device memory. Passwords, hashes, and metadata are never transmitted over any network.',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
            ],
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primaryTeal),
        ),
        error: (err, _) => Center(child: Text('Error: $err')),
      ),
    );
  }

  Widget _buildStatTile(
    String title,
    String count,
    Color color,
    IconData icon,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(
            count,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIssueCard(
    BuildContext context,
    PasswordSecurityIssue issue,
    List<dynamic> allPasswords,
    bool isDark,
  ) {
    final isCritical = issue.severity == SecurityIssueSeverity.critical;
    final color = isCritical
        ? AppColors.errorRed
        : issue.severity == SecurityIssueSeverity.warning
            ? AppColors.statusWarning
            : AppColors.primaryTeal;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isCritical ? Icons.dangerous_rounded : Icons.warning_rounded,
                color: color,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  issue.title,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            issue.description,
            style: TextStyle(
              fontSize: 12.5,
              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: issue.affectedEntryIds.map((id) {
              final p = allPasswords.firstWhere(
                (element) => element.id == id,
                orElse: () => null,
              );
              final title = p?.title ?? 'Account';
              return ActionChip(
                label: Text('Fix: $title', style: const TextStyle(fontSize: 11)),
                avatar: const Icon(Icons.edit, size: 12),
                onPressed: () => context.push('/edit-password/$id'),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

