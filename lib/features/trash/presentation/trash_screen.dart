import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/security/authentication_gate.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/widgets/empty_state_view.dart';
import '../../../core/widgets/error_dialog.dart';
import '../../../core/widgets/rupee_bunny_mascot.dart';
import '../../authentication/presentation/auth_providers.dart';
import '../../documents/domain/document_model.dart';

class TrashScreen extends ConsumerWidget {
  const TrashScreen({super.key});

  Future<void> _restoreDoc(
    BuildContext context,
    WidgetRef ref,
    DocumentModel doc,
  ) async {
    final gate = ref.read(authenticationGateProvider);
    final verified = await gate.authenticateForAction(
      context,
      action: PendingVaultAction(
        type: VaultActionType.restoreDocument,
        targetId: doc.id,
        targetName: doc.name,
        returnRoute: '/settings',
      ),
      title: 'Authorize Restoration',
      reason:
          'Confirm with biometrics to restore "${doc.name}" from trash.',
    );
    if (!verified || !context.mounted) return;

    final repo = ref.read(documentRepositoryProvider);
    await repo.restoreFromTrash(doc.id);
    ref.invalidate(trashDocumentsProvider);
    ref.invalidate(activeDocumentsProvider);

    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Restored "${doc.name}"')));
    }
  }

  Future<void> _permanentlyDelete(
    BuildContext context,
    WidgetRef ref,
    DocumentModel doc,
  ) async {
    final confirmed = await ErrorDialog.confirm(
      context,
      title: 'Permanently Delete?',
      message:
          'This will securely overwrite and permanently destroy the encrypted file for "${doc.name}". This action cannot be undone.',
      confirmLabel: 'Delete Forever',
      isDestructive: true,
    );

    if (confirmed && context.mounted) {
      final gate = ref.read(authenticationGateProvider);
      final verified = await gate.authenticateForAction(
        context,
        action: PendingVaultAction(
          type: VaultActionType.permanentlyDeleteDocument,
          targetId: doc.id,
          targetName: doc.name,
          returnRoute: '/settings',
        ),
        title: 'Confirm Permanent Destruction',
        reason:
            'Confirm with biometrics to permanently destroy "${doc.name}".',
      );
      if (!verified || !context.mounted) return;

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
      final gate = ref.read(authenticationGateProvider);
      final verified = await gate.authenticateForAction(
        context,
        action: PendingVaultAction(
          type: VaultActionType.permanentlyDeleteDocument,
          targetName: 'All Trash Documents',
          returnRoute: '/settings',
        ),
        title: 'Authorize Empty Trash',
        reason: 'Confirm with biometrics to permanently purge all documents in Trash.',
      );
      if (!verified || !context.mounted) return;

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
    final colors = context.themeColors;
    final trashAsync = ref.watch(trashDocumentsProvider);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text(
          'Trash & Recovery',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          trashAsync.maybeWhen(
            data: (docs) => docs.isNotEmpty
                ? TextButton(
                    onPressed: () => _emptyTrash(context, ref),
                    child: Text(
                      'Empty Trash',
                      style: TextStyle(color: colors.error),
                    ),
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
              mascotPose: MascotPose.happy,
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
                  color: colors.cardBackground,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colors.cardBorder),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: colors.error.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.delete_outline_rounded,
                      color: colors.error,
                      size: 22,
                    ),
                  ),
                  title: Text(
                    doc.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    'Deleted: ${DateFormatter.formatDisplay(doc.deletedAt)}',
                    style: TextStyle(fontSize: 12, color: colors.textSecondary),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.restore_from_trash_rounded,
                          color: colors.primaryAccent,
                        ),
                        tooltip: 'Restore',
                        onPressed: () => _restoreDoc(context, ref, doc),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.delete_forever_rounded,
                          color: colors.error,
                        ),
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
        loading: () => Center(
          child: CircularProgressIndicator(color: colors.primaryAccent),
        ),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}
