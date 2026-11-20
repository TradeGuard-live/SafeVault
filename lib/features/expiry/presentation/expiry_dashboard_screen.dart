import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/masked_text_formatter.dart';
import '../../../core/widgets/empty_state_view.dart';
import '../../../core/widgets/status_badge.dart';
import '../../authentication/presentation/auth_providers.dart';
import '../../documents/domain/document_model.dart';

class ExpiryDashboardScreen extends ConsumerWidget {
  const ExpiryDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final docsAsync = ref.watch(activeDocumentsProvider);

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        backgroundColor: isDark ? AppColors.darkBackground : AppColors.lightBackground,
        appBar: AppBar(
          title: const Text('Expiry Reminders', style: TextStyle(fontWeight: FontWeight.w700)),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: AppColors.primaryTeal,
            unselectedLabelColor: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
            indicatorColor: AppColors.primaryTeal,
            tabs: const [
              Tab(text: 'Expiring Soon (30d)'),
              Tab(text: 'Critical (≤7d)'),
              Tab(text: 'Expired'),
              Tab(text: 'All Upcoming'),
              Tab(text: 'No Expiry'),
            ],
          ),
        ),
        body: docsAsync.when(
          data: (allDocs) {
            final now = DateTime.now();

            final expired = allDocs.where((d) => d.expiryDate != null && DateFormatter.daysRemaining(d.expiryDate!) < 0).toList();
            final critical = allDocs.where((d) {
              if (d.expiryDate == null) return false;
              final days = DateFormatter.daysRemaining(d.expiryDate!);
              return days >= 0 && days <= 7;
            }).toList();
            final within30 = allDocs.where((d) {
              if (d.expiryDate == null) return false;
              final days = DateFormatter.daysRemaining(d.expiryDate!);
              return days >= 0 && days <= 30;
            }).toList();
            final upcoming = allDocs.where((d) => d.expiryDate != null && d.expiryDate!.isAfter(now)).toList();
            final noExpiry = allDocs.where((d) => d.expiryDate == null).toList();

            return TabBarView(
              children: [
                _buildDocList(context, within30, 'No documents expiring within 30 days.'),
                _buildDocList(context, critical, 'No documents expiring in the next 7 days.'),
                _buildDocList(context, expired, 'No expired documents. Everything is up to date!'),
                _buildDocList(context, upcoming, 'No documents with upcoming expiry dates.'),
                _buildDocList(context, noExpiry, 'No documents without expiry dates.'),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primaryTeal)),
          error: (e, _) => Center(child: Text('Error loading documents: $e')),
        ),
      ),
    );
  }

  Widget _buildDocList(BuildContext context, List<DocumentModel> docs, String emptyMessage) {
    if (docs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_outline_rounded, size: 48, color: AppColors.primaryTeal),
              const SizedBox(height: 14),
              Text(
                emptyMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: AppColors.darkTextSecondary),
              ),
            ],
          ),
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      itemCount: docs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (ctx, i) {
        final doc = docs[i];
        return Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCard : AppColors.lightCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            ),
          ),
          child: ListTile(
            onTap: () => context.push('/document/${doc.id}'),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primaryTeal.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.calendar_month_outlined, color: AppColors.primaryTeal, size: 22),
            ),
            title: Text(
              doc.name,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 2),
                Text(
                  'Expiry: ${DateFormatter.formatDisplay(doc.expiryDate)}',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                  ),
                ),
              ],
            ),
            trailing: StatusBadge.fromExpiry(doc.expiryDate),
          ),
        );
      },
    );
  }
}

