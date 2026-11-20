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
    final rows = await db.query('categories', orderBy: 'is_default DESC, name ASC');
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

    await db.insert('categories', newCategory.toMap());
    return newCategory;
  }

  Future<void> renameCategory(String id, String newName) async {
    final db = await _dbHelper.database;
    await db.update(
      'categories',
      {'name': newName.trim()},
      where: 'id = ? AND is_default = 0',
      whereArgs: [id],
    );
  }

  /// Deletes a custom category safely.
  /// Reassigns any documents belonging to this category to the 'other' category first.
  Future<void> deleteCustomCategory(String id) async {
    final db = await _dbHelper.database;
    final category = await getCategoryById(id);
    if (category == null) return;
    if (category.isDefault) {
      throw const DatabaseOperationException('Default system categories cannot be deleted.');
    }

    await db.transaction((txn) async {
      // 1. Reassign documents to 'other' category
      await txn.update(
        'documents',
        {'category_id': 'other'},
        where: 'category_id = ?',
        whereArgs: [id],
      );

      // 2. Delete custom category
      await txn.delete(
        'categories',
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }
}
