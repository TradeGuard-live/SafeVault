import '../domain/password_entry_model.dart';

enum SecurityIssueSeverity { critical, warning, info }

class PasswordSecurityIssue {
  final String title;
  final String description;
  final SecurityIssueSeverity severity;
  final List<String> affectedEntryIds;

  const PasswordSecurityIssue({
    required this.title,
    required this.description,
    required this.severity,
    required this.affectedEntryIds,
  });
}

class PasswordAuditResult {
  final int totalPasswords;
  final int overallScore; // 0 to 100
  final int weakCount;
  final int reusedCount;
  final int shortCount;
  final int missingCredentialsCount;
  final int duplicateCount;
  final List<PasswordSecurityIssue> issues;

  const PasswordAuditResult({
    required this.totalPasswords,
    required this.overallScore,
    required this.weakCount,
    required this.reusedCount,
    required this.shortCount,
    required this.missingCredentialsCount,
    required this.duplicateCount,
    required this.issues,
  });
}

/// 100% Offline, on-device Password Security Analyzer.
/// Evaluates password entropy, detects password reuse across accounts,
/// flags weak/short credentials, and duplicate account records.
/// Never sends passwords or hashes anywhere.
class PasswordSecurityAnalyzer {
  static PasswordAuditResult analyze(List<PasswordEntryModel> entries) {
    if (entries.isEmpty) {
      return const PasswordAuditResult(
        totalPasswords: 0,
        overallScore: 100,
        weakCount: 0,
        reusedCount: 0,
        shortCount: 0,
        missingCredentialsCount: 0,
        duplicateCount: 0,
        issues: [],
      );
    }

    final issues = <PasswordSecurityIssue>[];
    final weakIds = <String>[];
    final shortIds = <String>[];
    final missingIds = <String>[];

    // Password reuse tracking
    final passwordMap = <String, List<String>>{};
    // Duplicate account tracking (website + username)
    final accountKeyMap = <String, List<String>>{};

    for (final entry in entries) {
      final pwd = entry.decryptedPassword ?? '';

      // Check short passwords
      if (pwd.length < 8) {
        shortIds.add(entry.id);
      } else if (pwd.length < 12) {
        weakIds.add(entry.id);
      } else {
        // Check character complexity
        final hasUpper = pwd.contains(RegExp(r'[A-Z]'));
        final hasLower = pwd.contains(RegExp(r'[a-z]'));
        final hasDigit = pwd.contains(RegExp(r'[0-9]'));
        final hasSymbol = pwd.contains(RegExp(r'[^A-Za-z0-9]'));
        final complexityScore =
            (hasUpper ? 1 : 0) +
            (hasLower ? 1 : 0) +
            (hasDigit ? 1 : 0) +
            (hasSymbol ? 1 : 0);

        if (complexityScore < 3) {
          weakIds.add(entry.id);
        }
      }

      // Check missing username/email
      final hasUsername =
          entry.decryptedUsername != null &&
          entry.decryptedUsername!.isNotEmpty;
      final hasEmail =
          entry.decryptedEmail != null && entry.decryptedEmail!.isNotEmpty;
      if (!hasUsername && !hasEmail) {
        missingIds.add(entry.id);
      }

      // Track reuse
      if (pwd.isNotEmpty) {
        passwordMap.putIfAbsent(pwd, () => []).add(entry.id);
      }

      // Track duplicate records
      final site = (entry.websiteUrl ?? entry.title).trim().toLowerCase();
      final user = (entry.decryptedUsername ?? entry.decryptedEmail ?? '')
          .trim()
          .toLowerCase();
      if (site.isNotEmpty && user.isNotEmpty) {
        final key = '$site::$user';
        accountKeyMap.putIfAbsent(key, () => []).add(entry.id);
      }
    }

    final reusedIds = <String>{};
    for (final group in passwordMap.values) {
      if (group.length > 1) {
        reusedIds.addAll(group);
      }
    }

    final duplicateIds = <String>{};
    for (final group in accountKeyMap.values) {
      if (group.length > 1) {
        duplicateIds.addAll(group);
      }
    }

    // Build structured issues
    if (shortIds.isNotEmpty) {
      issues.add(
        PasswordSecurityIssue(
          title: 'Critically Short Passwords (${shortIds.length})',
          description: 'Passwords under 8 characters can be cracked rapidly. Upgrade to at least 16 characters.',
          severity: SecurityIssueSeverity.critical,
          affectedEntryIds: shortIds,
        ),
      );
    }

    if (reusedIds.isNotEmpty) {
      issues.add(
        PasswordSecurityIssue(
          title: 'Reused Passwords (${reusedIds.length})',
          description: 'Using the same password across multiple accounts creates a single point of failure if one site is breached.',
          severity: SecurityIssueSeverity.critical,
          affectedEntryIds: reusedIds.toList(),
        ),
      );
    }

    if (weakIds.isNotEmpty) {
      issues.add(
        PasswordSecurityIssue(
          title: 'Weak Passwords (${weakIds.length})',
          description: 'Passwords under 12 characters or missing a mix of uppercase, numbers, and symbols are vulnerable.',
          severity: SecurityIssueSeverity.warning,
          affectedEntryIds: weakIds,
        ),
      );
    }

    if (missingIds.isNotEmpty) {
      issues.add(
        PasswordSecurityIssue(
          title: 'Missing Username / Email (${missingIds.length})',
          description: 'These accounts are missing username or email information, making sign-in ambiguous.',
          severity: SecurityIssueSeverity.info,
          affectedEntryIds: missingIds,
        ),
      );
    }

    if (duplicateIds.isNotEmpty) {
      issues.add(
        PasswordSecurityIssue(
          title: 'Duplicate Accounts (${duplicateIds.length})',
          description: 'Multiple accounts exist for the same website and username. Consider merging or removing duplicates.',
          severity: SecurityIssueSeverity.info,
          affectedEntryIds: duplicateIds.toList(),
        ),
      );
    }

    // Calculate score out of 100
    int score = 100;
    score -= (shortIds.length * 15);
    score -= (reusedIds.length * 10);
    score -= (weakIds.length * 5);
    score -= (missingIds.length * 2);
    score -= (duplicateIds.length * 2);
    if (score < 0) score = 0;

    return PasswordAuditResult(
      totalPasswords: entries.length,
      overallScore: score,
      weakCount: weakIds.length,
      reusedCount: reusedIds.length,
      shortCount: shortIds.length,
      missingCredentialsCount: missingIds.length,
      duplicateCount: duplicateIds.length,
      issues: issues,
    );
  }
}
