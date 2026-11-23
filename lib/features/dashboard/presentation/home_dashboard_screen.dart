import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/security/file_validator.dart';
import '../../../core/services/native_saf_and_share_service.dart';
import '../../../core/storage/encrypted_file_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/masked_text_formatter.dart';
import '../../../core/widgets/error_dialog.dart';
import '../../../core/widgets/rupee_bunny_mascot.dart';
import '../../../core/widgets/status_badge.dart';
import '../../authentication/presentation/auth_providers.dart';
import '../../categories/domain/category_model.dart';
import '../../documents/domain/document_model.dart';

class HomeDashboardScreen extends ConsumerStatefulWidget {
  const HomeDashboardScreen({super.key});

  @override
  ConsumerState<HomeDashboardScreen> createState() =>
      _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends ConsumerState<HomeDashboardScreen> {
  StorageBreakdown? _storageBreakdown;

  @override
  void initState() {
    super.initState();
    _loadStorage();
  }

  Future<void> _loadStorage() async {
    final storage = ref.read(storageServiceProvider);
    final breakdown = await storage.getStorageBreakdown();
    if (mounted) {
      setState(() => _storageBreakdown = breakdown);
    }
  }

  Future<void> _importDocument() async {
    try {
      final safItems = await NativeSafAndShareService.instance.pickDocuments(
        allowMultiple: true,
      );

      if (safItems.isNotEmpty) {
        if (!mounted) return;
        if (safItems.length == 1) {
          final first = safItems.first;
          final file = File(first.path);
          final validation = await FileValidator.validateFile(file);
          if (!mounted) return;
          context.push(
            '/add-document',
            extra: {
              'initialFilePath': first.path,
              'mimeType': validation.mimeType,
              'initialFileName': first.name,
            },
          );
        } else {
          // Multiple documents picked via SAF -> Open incoming share preview
          if (!mounted) return;
          context.push('/incoming-share-preview', extra: safItems);
        }
        return;
      }

      // Fallback for non-Android platforms / tests
      final session = ref.read(vaultSessionProvider);
      session.beginSystemActivity('FILE_PICKER_FALLBACK');
      List<PlatformFile> files;
      try {
        files = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
        );
      } finally {
        Future.microtask(() => session.endSystemActivity());
      }

      if (files.isEmpty) return;
      final path = files.first.path;
      if (path == null) return;

      final file = File(path);
      // Validate magic bytes & size
      final validation = await FileValidator.validateFile(file);

      if (!mounted) return;
      context.push(
        '/add-document',
        extra: {
          'initialFilePath': path,
          'mimeType': validation.mimeType,
          'initialFileName': files.first.name,
        },
      );
    } catch (e) {
      if (mounted) {
        ErrorDialog.show(
          context,
          title: 'Import Failed',
          message: e.toString(),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.themeColors;
    final docsAsync = ref.watch(activeDocumentsProvider);
    final catsAsync = ref.watch(categoriesProvider);
    final expiringAsync = ref.watch(expiringDocumentsProvider);
    final favoritesAsync = ref.watch(favoriteDocumentsProvider);
    final passwordsAsync = ref.watch(allPasswordsProvider);
    final bankAccountsAsync = ref.watch(allBankAccountsProvider);
    final cardsAsync = ref.watch(allPaymentCardsProvider);
    final groupsAsync = ref.watch(documentGroupsProvider);
    final tempDocsAsync = ref.watch(temporaryDocumentsProvider);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        elevation: 0,
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/icon/app_icon.png',
                width: 32,
                height: 32,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Vault',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 22,
                color: colors.textPrimary,
              ),
            ),
          ],
        ),
        actions: [
          // Security Status Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: colors.primaryAccent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: colors.primaryAccent.withOpacity(0.25)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_rounded, size: 12, color: colors.primaryAccent),
                const SizedBox(width: 4),
                Text(
                  '2FA Active',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: colors.primaryAccent,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.search_rounded, color: colors.textPrimary),
            tooltip: 'Search Documents',
            onPressed: () => context.push('/search'),
          ),
          IconButton(
            icon: Icon(Icons.lock_outline_rounded, color: colors.textPrimary),
            tooltip: 'Lock Vault',
            onPressed: () {
              ref.read(vaultSessionProvider).lock();
              context.go('/biometric-unlock');
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        color: colors.primaryAccent,
        backgroundColor: colors.surfaceElevated,
        onRefresh: () async {
          _loadStorage();
          ref.invalidate(activeDocumentsProvider);
          ref.invalidate(expiringDocumentsProvider);
          ref.invalidate(favoriteDocumentsProvider);
          ref.invalidate(allPaymentCardsProvider);
          ref.invalidate(allBankAccountsProvider);
          ref.invalidate(allPasswordsProvider);
          ref.invalidate(documentGroupsProvider);
          ref.invalidate(temporaryDocumentsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          children: [
            // 1. Vault Overview Card (Themed Hero Gradient)
            _buildOverviewCard(
              colors,
              docsAsync,
              passwordsAsync,
              bankAccountsAsync,
              cardsAsync,
            ),
            const SizedBox(height: 20),

            // 2. Quick Actions
            _buildQuickActions(colors),
            const SizedBox(height: 18),

            // 2b. Custom Groups & Temporary Documents Hub
            _buildGroupsAndTemporarySection(colors, groupsAsync, tempDocsAsync),
            const SizedBox(height: 24),

            // 3. Categories Section
            _buildCategoriesSection(colors, catsAsync, docsAsync),
            const SizedBox(height: 24),

            // 4. Expiry Section (if any expiring docs)
            _buildExpirySection(colors, expiringAsync),

            // 5. Favorites Section
            _buildFavoritesSection(colors, favoritesAsync),

            // 6. Recent Documents
            _buildRecentDocumentsSection(colors, docsAsync),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewCard(
    AppThemeColors colors,
    AsyncValue<List<DocumentModel>> docsAsync,
    AsyncValue<dynamic> passwordsAsync,
    AsyncValue<dynamic> bankAccountsAsync,
    AsyncValue<dynamic> cardsAsync,
  ) {
    final docsCount = docsAsync.valueOrNull?.length ?? 0;
    final passwordsCount = passwordsAsync.valueOrNull?.length ?? 0;
    final bankAccountsCount = bankAccountsAsync.valueOrNull?.length ?? 0;
    final cardsCount = cardsAsync.valueOrNull?.length ?? 0;
    final expiringCount =
        docsAsync.valueOrNull
            ?.where(
              (d) =>
                  d.expiryDate != null &&
                  DateFormatter.daysRemaining(d.expiryDate!) <= 30,
            )
            .length ??
        0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: colors.heroGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: colors.heroShadow,
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Personal Vault Status',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.22),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.shield_rounded, color: Colors.white, size: 12),
                    SizedBox(width: 4),
                    Text(
                      'Mandatory 2FA',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStatItem(
                'Documents',
                '$docsCount',
                Icons.description_outlined,
              ),
              _buildStatItem(
                'Passwords',
                '$passwordsCount',
                Icons.vpn_key_outlined,
              ),
              _buildStatItem(
                'Cards',
                '$cardsCount',
                Icons.credit_card_outlined,
              ),
              _buildStatItem(
                'Bank Accts',
                '$bankAccountsCount',
                Icons.account_balance_outlined,
              ),
              _buildStatItem(
                'Expiring',
                '$expiringCount',
                Icons.warning_amber_rounded,
                isWarning: expiringCount > 0,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    String label,
    String value,
    IconData icon, {
    bool isWarning = false,
  }) {
    return Column(
      children: [
        Icon(
          icon,
          color: isWarning
              ? const Color(0xFFFFD98E)
              : Colors.white.withOpacity(0.85),
          size: 20,
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            color: isWarning ? const Color(0xFFFFD98E) : Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActions(AppThemeColors colors) {
    return Row(
      children: [
        Expanded(
          child: _buildActionTile(
            label: 'Scan Doc',
            icon: Icons.document_scanner_rounded,
            color: colors.primaryAccent,
            colors: colors,
            onTap: () => context.push('/camera-scanner'),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _buildActionTile(
            label: 'Import',
            icon: Icons.file_upload_outlined,
            color: colors.info,
            colors: colors,
            onTap: _importDocument,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _buildActionTile(
            label: 'Add Pass',
            icon: Icons.key_rounded,
            color: colors.warning,
            colors: colors,
            onTap: () => context.push('/add-password'),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _buildActionTile(
            label: 'Add Card',
            icon: Icons.credit_card_rounded,
            color: const Color(0xFF8B5CF6),
            colors: colors,
            onTap: () => context.push('/add-card'),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _buildActionTile(
            label: 'Add Bank',
            icon: Icons.account_balance_rounded,
            color: colors.success,
            colors: colors,
            onTap: () => context.push('/add-bank-account'),
          ),
        ),
      ],
    );
  }

  Widget _buildGroupsAndTemporarySection(
    AppThemeColors colors,
    AsyncValue<dynamic> groupsAsync,
    AsyncValue<dynamic> tempDocsAsync,
  ) {
    final groupsCount = groupsAsync.valueOrNull?.length ?? 0;
    final tempDocsCount = tempDocsAsync.valueOrNull?.length ?? 0;

    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: () => context.push('/document-groups'),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: colors.cardBackground,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.cardBorder),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colors.primaryAccent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.folder_special_rounded,
                      color: colors.primaryAccent,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Groups',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: colors.textPrimary,
                          ),
                        ),
                        Text(
                          '$groupsCount custom',
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colors.textSecondary,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: InkWell(
            onTap: () => context.push('/temporary-documents'),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: colors.cardBackground,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.cardBorder),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colors.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.hourglass_top_rounded,
                      color: colors.warning,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Temporary',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: colors.textPrimary,
                          ),
                        ),
                        Text(
                          '$tempDocsCount docs',
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colors.textSecondary,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionTile({
    required String label,
    required IconData icon,
    required Color color,
    required AppThemeColors colors,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: colors.surfaceSecondary,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.cardBorder),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: color.withOpacity(0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoriesSection(
    AppThemeColors colors,
    AsyncValue<List<CategoryModel>> catsAsync,
    AsyncValue<List<DocumentModel>> docsAsync,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Categories',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            TextButton(
              onPressed: () => context.push('/category-management'),
              child: Text(
                'Manage',
                style: TextStyle(
                  fontSize: 13,
                  color: colors.primaryAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        catsAsync.when(
          data: (categories) {
            final docs = docsAsync.valueOrNull ?? [];
            return SizedBox(
              height: 110,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (ctx, i) {
                  final cat = categories[i];
                  final count = docs
                      .where((d) => d.categoryId == cat.id)
                      .length;
                  return _buildCategoryCard(colors, cat, count);
                },
              ),
            );
          },
          loading: () => Center(
            child: CircularProgressIndicator(color: colors.primaryAccent),
          ),
          error: (e, _) => Text(
            'Error loading categories: $e',
            style: TextStyle(color: colors.error),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryCard(
    AppThemeColors colors,
    CategoryModel cat,
    int docCount,
  ) {
    final color = Color(cat.colorValue);

    return InkWell(
      onTap: () => context.push('/category/${cat.id}', extra: cat.name),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 130,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.surfaceSecondary,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withOpacity(0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_resolveIcon(cat.icon), color: color, size: 20),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cat.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$docCount doc${docCount == 1 ? '' : 's'}',
                  style: TextStyle(fontSize: 11, color: colors.textTertiary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _resolveIcon(String iconName) {
    switch (iconName) {
      case 'badge':
        return Icons.badge_outlined;
      case 'directions_car':
        return Icons.directions_car_outlined;
      case 'account_balance':
        return Icons.account_balance_outlined;
      case 'school':
        return Icons.school_outlined;
      case 'home_work':
        return Icons.home_work_outlined;
      case 'local_hospital':
        return Icons.local_hospital_outlined;
      default:
        return Icons.folder_outlined;
    }
  }

  Widget _buildExpirySection(
    AppThemeColors colors,
    AsyncValue<List<DocumentModel>> expiringAsync,
  ) {
    final docs = expiringAsync.valueOrNull ?? [];
    if (docs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: colors.warning,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  'Upcoming Expiry (${docs.length})',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
              ],
            ),
            TextButton(
              onPressed: () => context.push('/expiry-dashboard'),
              child: Text(
                'View All',
                style: TextStyle(
                  fontSize: 13,
                  color: colors.primaryAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...docs.take(3).map((d) => _buildDocumentListTile(colors, d)),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildFavoritesSection(
    AppThemeColors colors,
    AsyncValue<List<DocumentModel>> favoritesAsync,
  ) {
    final docs = favoritesAsync.valueOrNull ?? [];
    if (docs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Favorites',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            TextButton(
              onPressed: () => context.go('/favorites'),
              child: Text(
                'View All',
                style: TextStyle(
                  fontSize: 13,
                  color: colors.primaryAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...docs.take(3).map((d) => _buildDocumentListTile(colors, d)),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildRecentDocumentsSection(
    AppThemeColors colors,
    AsyncValue<List<DocumentModel>> docsAsync,
  ) {
    final docs = docsAsync.valueOrNull ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent Documents',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            TextButton(
              onPressed: () => context.go('/all-documents'),
              child: Text(
                'View All',
                style: TextStyle(
                  fontSize: 13,
                  color: colors.primaryAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (docs.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colors.surfaceSecondary,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.cardBorder),
            ),
            child: Row(
              children: [
                const RupeeBunnyMascot(pose: MascotPose.thinking, size: 56),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your Vault is Ready',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Tap Scan or Import to safely encrypt your first document.',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
        else
          ...docs.take(5).map((d) => _buildDocumentListTile(colors, d)),
      ],
    );
  }

  Widget _buildDocumentListTile(AppThemeColors colors, DocumentModel doc) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: colors.surfaceSecondary,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.cardBorder),
      ),
      child: ListTile(
        onTap: () => context.push('/document/${doc.id}'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: colors.primaryAccent.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            Icons.description_outlined,
            color: colors.primaryAccent,
            size: 22,
          ),
        ),
        title: Text(
          doc.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              doc.documentNumber != null
                  ? MaskedTextFormatter.maskDocumentNumber(doc.documentNumber)
                  : (doc.documentType ?? 'Personal Document'),
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
          ],
        ),
        trailing: StatusBadge.fromExpiry(doc.expiryDate),
      ),
    );
  }
}
