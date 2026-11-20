import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/security/file_validator.dart';
import '../../../core/storage/encrypted_file_storage.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/masked_text_formatter.dart';
import '../../../core/widgets/error_dialog.dart';
import '../../../core/widgets/status_badge.dart';
import '../../authentication/presentation/auth_providers.dart';
import '../../categories/domain/category_model.dart';
import '../../documents/domain/document_model.dart';

class HomeDashboardScreen extends ConsumerStatefulWidget {
  const HomeDashboardScreen({super.key});

  @override
  ConsumerState<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
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
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      );

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final docsAsync = ref.watch(activeDocumentsProvider);
    final catsAsync = ref.watch(categoriesProvider);
    final expiringAsync = ref.watch(expiringDocumentsProvider);
    final favoritesAsync = ref.watch(favoriteDocumentsProvider);
    final passwordsAsync = ref.watch(allPasswordsProvider);
    final bankAccountsAsync = ref.watch(allBankAccountsProvider);

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.lightBackground,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.primaryTeal.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.shield_rounded, color: AppColors.primaryTeal, size: 22),
            ),
            const SizedBox(width: 10),
            const Text('Vault', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
          ],
        ),
        actions: [
          // Security Status Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primaryTeal.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.primaryTeal.withOpacity(0.25)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_rounded, size: 12, color: AppColors.primaryTeal),
                SizedBox(width: 4),
                Text(
                  '2FA Active',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryTeal,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.search_rounded),
            tooltip: 'Search Documents',
            onPressed: () => context.push('/search'),
          ),
          IconButton(
            icon: const Icon(Icons.lock_outline_rounded),
            tooltip: 'Lock Vault',
            onPressed: () {
              ref.read(vaultSessionProvider).lock();
              context.go('/biometric-unlock');
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.primaryTeal,
        onRefresh: () async {
          _loadStorage();
          ref.invalidate(activeDocumentsProvider);
          ref.invalidate(expiringDocumentsProvider);
          ref.invalidate(favoriteDocumentsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          children: [
            // 1. Vault Overview Card
            _buildOverviewCard(docsAsync, passwordsAsync, bankAccountsAsync),
            const SizedBox(height: 20),

            // 2. Quick Actions
            _buildQuickActions(),
            const SizedBox(height: 24),

            // 3. Categories Section
            _buildCategoriesSection(catsAsync, docsAsync),
            const SizedBox(height: 24),

            // 4. Expiry Section (if any expiring docs)
            _buildExpirySection(expiringAsync),

            // 5. Favorites Section
            _buildFavoritesSection(favoritesAsync),

            // 6. Recent Documents
            _buildRecentDocumentsSection(docsAsync),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewCard(
    AsyncValue<List<DocumentModel>> docsAsync,
    AsyncValue<dynamic> passwordsAsync,
    AsyncValue<dynamic> bankAccountsAsync,
  ) {
    final docsCount = docsAsync.valueOrNull?.length ?? 0;
    final passwordsCount = passwordsAsync.valueOrNull?.length ?? 0;
    final bankAccountsCount = bankAccountsAsync.valueOrNull?.length ?? 0;
    final expiringCount = docsAsync.valueOrNull
            ?.where((d) => d.expiryDate != null && DateFormatter.daysRemaining(d.expiryDate!) <= 30)
            .length ??
        0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F766E), Color(0xFF064E3B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0D9488).withOpacity(0.25),
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
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.shield_rounded, color: Colors.white, size: 12),
                    SizedBox(width: 4),
                    Text('Mandatory 2FA', style: TextStyle(color: Colors.white, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStatItem('Documents', '$docsCount', Icons.description_outlined),
              _buildStatItem('Passwords', '$passwordsCount', Icons.vpn_key_outlined),
              _buildStatItem('Bank Accounts', '$bankAccountsCount', Icons.account_balance_outlined),
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

  Widget _buildStatItem(String label, String value, IconData icon, {bool isWarning = false}) {
    return Column(
      children: [
        Icon(icon, color: isWarning ? Colors.amberAccent : Colors.white70, size: 20),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            color: isWarning ? Colors.amberAccent : Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white60,
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActions() {
    return Row(
      children: [
        Expanded(
          child: _buildActionTile(
            label: 'Scan Doc',
            icon: Icons.document_scanner_rounded,
            color: AppColors.primaryTeal,
            onTap: () => context.push('/camera-scanner'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildActionTile(
            label: 'Import',
            icon: Icons.file_upload_outlined,
            color: const Color(0xFF2563EB),
            onTap: _importDocument,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildActionTile(
            label: 'Add Pass',
            icon: Icons.key_rounded,
            color: const Color(0xFFF59E0B),
            onTap: () => context.push('/add-password'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildActionTile(
            label: 'Add Bank',
            icon: Icons.account_balance_rounded,
            color: const Color(0xFF10B981),
            onTap: () => context.push('/add-bank-account'),
          ),
        ),
      ],
    );
  }

  Widget _buildActionTile({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : AppColors.lightCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoriesSection(
    AsyncValue<List<CategoryModel>> catsAsync,
    AsyncValue<List<DocumentModel>> docsAsync,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
                color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
              ),
            ),
            TextButton(
              onPressed: () => context.push('/category-management'),
              child: const Text('Manage', style: TextStyle(fontSize: 13, color: AppColors.primaryTeal)),
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
                  final count = docs.where((d) => d.categoryId == cat.id).length;
                  return _buildCategoryCard(cat, count);
                },
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('Error loading categories: $e'),
        ),
      ],
    );
  }

  Widget _buildCategoryCard(CategoryModel cat, int docCount) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = Color(cat.colorValue);

    return InkWell(
      onTap: () => context.push('/category/${cat.id}', extra: cat.name),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 130,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : AppColors.lightCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
          ),
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
                    color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$docCount doc${docCount == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
                  ),
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

  Widget _buildExpirySection(AsyncValue<List<DocumentModel>> expiringAsync) {
    final docs = expiringAsync.valueOrNull ?? [];
    if (docs.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: AppColors.statusWarning, size: 18),
                const SizedBox(width: 6),
                Text(
                  'Upcoming Expiry (${docs.length})',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                  ),
                ),
              ],
            ),
            TextButton(
              onPressed: () => context.push('/expiry-dashboard'),
              child: const Text('View All', style: TextStyle(fontSize: 13, color: AppColors.primaryTeal)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...docs.take(3).map((d) => _buildDocumentListTile(d)),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildFavoritesSection(AsyncValue<List<DocumentModel>> favoritesAsync) {
    final docs = favoritesAsync.valueOrNull ?? [];
    if (docs.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;

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
                color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
              ),
            ),
            TextButton(
              onPressed: () => context.go('/favorites'),
              child: const Text('View All', style: TextStyle(fontSize: 13, color: AppColors.primaryTeal)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...docs.take(3).map((d) => _buildDocumentListTile(d)),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildRecentDocumentsSection(AsyncValue<List<DocumentModel>> docsAsync) {
    final docs = docsAsync.valueOrNull ?? [];
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
                color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
              ),
            ),
            TextButton(
              onPressed: () => context.go('/all-documents'),
              child: const Text('View All', style: TextStyle(fontSize: 13, color: AppColors.primaryTeal)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (docs.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkCard : AppColors.lightCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.lightBorder),
            ),
            child: const Center(
              child: Text(
                'No documents yet. Tap Scan or Import to add your first document.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.darkTextSecondary),
              ),
            ),
          )
        else
          ...docs.take(5).map((d) => _buildDocumentListTile(d)),
      ],
    );
  }

  Widget _buildDocumentListTile(DocumentModel doc) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
        ),
      ),
      child: ListTile(
        onTap: () => context.push('/document/${doc.id}'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.primaryTeal.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.description_outlined, color: AppColors.primaryTeal, size: 22),
        ),
        title: Text(
          doc.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
            color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
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
              style: TextStyle(
                fontSize: 12,
                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
              ),
            ),
          ],
        ),
        trailing: StatusBadge.fromExpiry(doc.expiryDate),
      ),
    );
  }
}
