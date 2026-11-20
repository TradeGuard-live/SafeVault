import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/empty_state_view.dart';
import '../../../core/widgets/error_dialog.dart';
import '../../authentication/presentation/auth_providers.dart';
import '../../documents/domain/document_model.dart';

class TrashScreen extends ConsumerWidget {
  const TrashScreen({super.key});

  Future<void> _restoreDoc(BuildContext context, WidgetRef ref, DocumentModel doc) async {
    final repo = ref.read(documentRepositoryProvider);
    await repo.restoreFromTrash(doc.id);
    ref.invalidate(trashDocumentsProvider);
    ref.invalidate(activeDocumentsProvider);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Restored "${doc.name}"')),
      );
    }
  }

  Future<void> _permanentlyDelete(BuildContext context, WidgetRef ref, DocumentModel doc) async {
    final confirmed = await ErrorDialog.confirm(
      context,
      title: 'Permanently Delete?',
      message: 'This will securely overwrite and permanently destroy the encrypted file for "${doc.name}". This action cannot be undone.',
      confirmLabel: 'Delete Forever',
      isDestructive: true,
    );

    if (confirmed && context.mounted) {
      final repo = ref.read(documentRepositoryProvider);
      await repo.permanentlyDeleteDocument(doc.id);
      ref.invalidate(trashDocumentsProvider);
    }
  }

  Future<void> _emptyTrash(BuildContext context, WidgetRef ref) async {
    final confirmed = await ErrorDialog.confirm(
      context,
      title: 'Empty Trash?',
      message: 'All documents in Trash will be permanently deleted and purged from device storage. This action cannot be undone.',
      confirmLabel: 'Empty Trash',
      isDestructive: true,
    );

    if (confirmed && context.mounted) {
      final repo = ref.read(documentRepositoryProvider);
      final count = await repo.emptyTrash();
      ref.invalidate(trashDocumentsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Permanently removed $count documents.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final trashAsync = ref.watch(trashDocumentsProvider);

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.lightBackground,
      appBar: AppBar(
        title: const Text('Trash & Recovery', style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          trashAsync.maybeWhen(
            data: (docs) => docs.isNotEmpty
                ? TextButton(
                    onPressed: () => _emptyTrash(context, ref),
                    child: const Text('Empty Trash', style: TextStyle(color: AppColors.statusDanger)),
                  )
                : const SizedBox.shrink(),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: trashAsync.when(
        data: (trashDocs) {
          if (trashDocs.isEmpty) {
            return const EmptyStateView(
              icon: Icons.delete_outline_rounded,
              title: 'Trash is Empty',
              description: 'Documents moved to trash remain safely recoverable here until permanently purged.',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            itemCount: trashDocs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (ctx, i) {
              final doc = trashDocs[i];

              return Container(
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkCard : AppColors.lightCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                  ),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.statusDanger.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.delete_outline_rounded, color: AppColors.statusDanger, size: 22),
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
                    'Deleted: ${DateFormatter.formatDisplay(doc.deletedAt)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.restore_from_trash_rounded, color: AppColors.primaryTeal),
                        tooltip: 'Restore',
                        onPressed: () => _restoreDoc(context, ref, doc),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_forever_rounded, color: AppColors.statusDanger),
                        tooltip: 'Permanently Delete',
                        onPressed: () => _permanentlyDelete(context, ref, doc),
                      ),
                    ],
                  ),
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

