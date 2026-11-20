import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/masked_text_formatter.dart';
import '../../../core/widgets/empty_state_view.dart';
import '../../../core/widgets/status_badge.dart';
import '../../authentication/presentation/auth_providers.dart';
import '../domain/document_model.dart';

class CategoryDocumentsScreen extends ConsumerWidget {
  final String categoryId;
  final String categoryName;

  const CategoryDocumentsScreen({
    super.key,
    required this.categoryId,
    required this.categoryName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final docsAsync = ref.watch(activeDocumentsProvider);

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.lightBackground,
      appBar: AppBar(
        title: Text(categoryName, style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: () => context.push(
              '/add-document',
              extra: {'defaultCategoryId': categoryId},
            ),
          ),
        ],
      ),
      body: docsAsync.when(
        data: (allDocs) {
          final catDocs = allDocs.where((d) => d.categoryId == categoryId).toList();

          if (catDocs.isEmpty) {
            return EmptyStateView(
              icon: Icons.folder_open_rounded,
              title: 'No Documents in $categoryName',
              description: 'You haven\'t stored any documents in this category yet.',
              actionLabel: 'Add to $categoryName',
              onAction: () => context.push(
                '/add-document',
                extra: {'defaultCategoryId': categoryId},
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: catDocs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (ctx, i) {
              final doc = catDocs[i];
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
                    child: const Icon(Icons.description_outlined, color: AppColors.primaryTeal, size: 22),
                  ),
                  title: Text(
                    doc.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                    ),
                  ),
                  subtitle: Text(
                    doc.documentNumber != null
                        ? MaskedTextFormatter.maskDocumentNumber(doc.documentNumber)
                        : (doc.documentType ?? 'Document'),
                    style: TextStyle(
                      fontSize: 12.5,
                      color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                    ),
                  ),
                  trailing: StatusBadge.fromExpiry(doc.expiryDate),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primaryTeal)),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

