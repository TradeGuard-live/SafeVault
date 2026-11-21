import 'package:uuid/uuid.dart';

import '../../../core/database/vault_database.dart';
import '../../../core/errors/exceptions.dart';
import '../domain/category_model.dart';

class CategoryRepository {
  final VaultDatabase _dbHelper;
  final Uuid _uuid = const Uuid();

  CategoryRepository({VaultDatabase? dbHelper})
    : _dbHelper = dbHelper ?? VaultDatabase.instance;

  Future<List<CategoryModel>> getAllCategories() async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'categories',
      orderBy: 'is_default DESC, name ASC',
    );
    return rows.map((r) => CategoryModel.fromMap(r)).toList();
  }

  Future<CategoryModel?> getCategoryById(String id) async {
    final db = await _dbHelper.database;
    final rows = await db.query('categories', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return CategoryModel.fromMap(rows.first);
  }

  Future<CategoryModel> createCustomCategory({
    required String name,
    required String icon,
    required int colorValue,
  }) async {
    final db = await _dbHelper.database;
    final now = DateTime.now();
    final newCategory = CategoryModel(
      id: 'cat_${_uuid.v4().substring(0, 8)}',
      name: name.trim(),
      icon: icon,
      colorValue: colorValue,
      isDefault: false,
      createdAt: now,
    );

    // Passwords retain their own built-in categories, but custom categories
    // made in the shared Manage Categories screen must also be selectable when
    // saving a password. Keep the two records in one transaction so no custom
    // category can appear in only one of those screens.
    await db.transaction((txn) async {
      await txn.insert('categories', newCategory.toMap());
      await txn.insert('password_categories', newCategory.toMap());
    });
    return newCategory;
  }

  Future<void> renameCategory(String id, String newName) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.update(
        'categories',
        {'name': newName.trim()},
        where: 'id = ? AND is_default = 0',
        whereArgs: [id],
      );
      await txn.update(
        'password_categories',
        {'name': newName.trim()},
        where: 'id = ? AND is_default = 0',
        whereArgs: [id],
      );
    });
  }

  /// Deletes a custom category safely.
  /// Reassigns documents and passwords belonging to this category to 'other'
  /// before removing the corresponding custom category records.
  Future<void> deleteCustomCategory(String id) async {
    final db = await _dbHelper.database;
    final category = await getCategoryById(id);
    if (category == null) return;
    if (category.isDefault) {
      throw const DatabaseOperationException(
        'Default system categories cannot be deleted.',
      );
    }

    await db.transaction((txn) async {
      // 1. Reassign documents to 'other' category
      await txn.update(
        'documents',
        {'category_id': 'other'},
        where: 'category_id = ?',
        whereArgs: [id],
      );

      // 2. Preserve any password entries that used the mirrored category.
      await txn.update(
        'password_entries',
        {'category_id': 'other'},
        where: 'category_id = ?',
        whereArgs: [id],
      );

      // 3. Delete the matching custom category records.
      await txn.delete('categories', where: 'id = ?', whereArgs: [id]);
      await txn.delete('password_categories', where: 'id = ?', whereArgs: [id]);
    });
  }
}
