import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/masked_text_formatter.dart';
import '../../../core/widgets/empty_state_view.dart';
import '../../../core/widgets/status_badge.dart';
import '../../authentication/presentation/auth_providers.dart';
import '../../documents/domain/document_model.dart';

class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final favoritesAsync = ref.watch(favoriteDocumentsProvider);

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.lightBackground,
      appBar: AppBar(
        title: const Text('Favorite Documents', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: favoritesAsync.when(
        data: (favDocs) {
          if (favDocs.isEmpty) {
            return const EmptyStateView(
              icon: Icons.star_border_rounded,
              title: 'No Favorites Yet',
              description: 'Tap the star icon on any document to add it to your favorites for quick access.',
            );
          }

          return RefreshIndicator(
            color: AppColors.primaryTeal,
            onRefresh: () async {
              ref.invalidate(favoriteDocumentsProvider);
            },
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: favDocs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (ctx, i) {
                final doc = favDocs[i];
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
                      child: const Icon(Icons.star_rounded, color: Colors.amber, size: 24),
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
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primaryTeal)),
        error: (e, _) => Center(child: Text('Error loading favorites: $e')),
      ),
    );
  }
}

