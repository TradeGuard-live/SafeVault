import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_theme_colors.dart';
import '../../../core/widgets/error_dialog.dart';
import '../../authentication/presentation/auth_providers.dart';
import '../domain/category_model.dart';

class CategoryManagementScreen extends ConsumerWidget {
  const CategoryManagementScreen({super.key});

  Future<void> _showAddCategoryDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final colors = context.themeColors;
    final nameController = TextEditingController();
    int selectedColor = colors.primaryAccent.value;
    String selectedIcon = 'folder';

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: colors.cardElevated,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text(
                'New Custom Category',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Category Name',
                      hintText: 'e.g. Travel Visas, Employment',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children:
                        [
                          colors.primaryAccent.value,
                          0xFF2563EB,
                          0xFF7C3AED,
                          0xFFD97706,
                          0xFFE11D48,
                          0xFF059669,
                        ].map((col) {
                          final isSel = selectedColor == col;
                          return GestureDetector(
                            onTap: () =>
                                setDialogState(() => selectedColor = col),
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: Color(col),
                                shape: BoxShape.circle,
                                border: isSel
                                    ? Border.all(color: Colors.white, width: 3)
                                    : null,
                              ),
                            ),
                          );
                        }).toList(),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (nameController.text.trim().isEmpty) return;
                    Navigator.of(ctx).pop(true);
                  },
                  child: const Text('Create'),
                ),
              ],
            );
          },
        );
      },
    );

    if (created == true) {
      final repo = ref.read(categoryRepositoryProvider);
      await repo.createCustomCategory(
        name: nameController.text.trim(),
        icon: selectedIcon,
        colorValue: selectedColor,
      );
      ref.invalidate(categoriesProvider);
    }
  }

  Future<void> _showRenameDialog(
    BuildContext context,
    WidgetRef ref,
    CategoryModel cat,
  ) async {
    final colors = context.themeColors;
    final nameController = TextEditingController(text: cat.name);

    final renamed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: colors.cardElevated,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Text(
            'Rename Category',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          content: TextField(
            controller: nameController,
            decoration: const InputDecoration(labelText: 'Category Name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (nameController.text.trim().isEmpty) return;
                Navigator.of(ctx).pop(true);
              },
              child: const Text('Rename'),
            ),
          ],
        );
      },
    );

    if (renamed == true) {
      final repo = ref.read(categoryRepositoryProvider);
      await repo.renameCategory(cat.id, nameController.text.trim());
      ref.invalidate(categoriesProvider);
    }
  }

  Future<void> _deleteCategory(
    BuildContext context,
    WidgetRef ref,
    CategoryModel cat,
  ) async {
    final confirmed = await ErrorDialog.confirm(
      context,
      title: 'Delete Category "${cat.name}"?',
      message: 'All documents in this category will be safely preserved and moved to the "Other" category.',
      confirmLabel: 'Delete Category',
      isDestructive: true,
    );

    if (confirmed) {
      final repo = ref.read(categoryRepositoryProvider);
      await repo.deleteCustomCategory(cat.id);
      ref.invalidate(categoriesProvider);
      ref.invalidate(activeDocumentsProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.themeColors;
    final catsAsync = ref.watch(categoriesProvider);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text(
          'Manage Categories',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Add Custom Category',
            onPressed: () => _showAddCategoryDialog(context, ref),
          ),
        ],
      ),
      body: catsAsync.when(
        data: (categories) {
          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            itemCount: categories.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (ctx, i) {
              final cat = categories[i];
              final color = Color(cat.colorValue);

              return Container(
                decoration: BoxDecoration(
                  color: colors.cardBackground,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colors.cardBorder),
                ),
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.folder_outlined, color: color, size: 22),
                  ),
                  title: Row(
                    children: [
                      Text(
                        cat.name,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: cat.isDefault
                              ? Colors.grey.withOpacity(0.15)
                              : colors.primaryAccent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          cat.isDefault ? 'Default' : 'Custom',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: cat.isDefault
                                ? colors.textSecondary
                                : colors.primaryAccent,
                          ),
                        ),
                      ),
                    ],
                  ),
                  trailing: cat.isDefault
                      ? null
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              onPressed: () =>
                                  _showRenameDialog(context, ref, cat),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.delete_outline,
                                size: 18,
                                color: colors.error,
                              ),
                              onPressed: () =>
                                  _deleteCategory(context, ref, cat),
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
