import 'package:cryptography/cryptography.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/database/vault_database.dart';
import '../../../core/errors/exceptions.dart';
import '../../../core/security/encryption_service.dart';
import '../domain/password_category_model.dart';
import '../domain/password_entry_model.dart';

class PasswordRepository {
  final VaultDatabase _db;
  final EncryptionService _encryptionService;

  PasswordRepository({VaultDatabase? db, EncryptionService? encryptionService})
    : _db = db ?? VaultDatabase.instance,
      _encryptionService = encryptionService ?? EncryptionService();

  Future<List<PasswordCategoryModel>> getAllCategories() async {
    try {
      final db = await _db.database;
      final rows = await db.query(
        'password_categories',
        orderBy: 'is_default DESC, name ASC',
      );
      return rows.map((r) => PasswordCategoryModel.fromMap(r)).toList();
    } catch (e) {
      throw DatabaseOperationException(
        'Failed to load password categories.',
        e,
      );
    }
  }

  Future<void> createCategory(PasswordCategoryModel category) async {
    try {
      final db = await _db.database;
      await db.insert('password_categories', category.toMap());
    } catch (e) {
      throw DatabaseOperationException(
        'Failed to create password category.',
        e,
      );
    }
  }

  Future<List<PasswordEntryModel>> getAllEntries(SecretKey masterKey) async {
    try {
      final db = await _db.database;
      final rows = await db.query(
        'password_entries',
        orderBy: 'title COLLATE NOCASE ASC',
      );

      final List<PasswordEntryModel> list = [];
      for (final row in rows) {
        final entry = PasswordEntryModel.fromMap(row);
        final decrypted = await entry.decrypt(
          masterKey: masterKey,
          encryptionService: _encryptionService,
        );
        list.add(decrypted);
      }
      return list;
    } catch (e) {
      throw DatabaseOperationException('Failed to load password entries.', e);
    }
  }

  Future<List<PasswordEntryModel>> getEntriesByCategory(
    String categoryId,
    SecretKey masterKey,
  ) async {
    try {
      final db = await _db.database;
      final rows = await db.query(
        'password_entries',
        where: 'category_id = ?',
        whereArgs: [categoryId],
        orderBy: 'title COLLATE NOCASE ASC',
      );

      final List<PasswordEntryModel> list = [];
      for (final row in rows) {
        final entry = PasswordEntryModel.fromMap(row);
        final decrypted = await entry.decrypt(
          masterKey: masterKey,
          encryptionService: _encryptionService,
        );
        list.add(decrypted);
      }
      return list;
    } catch (e) {
      throw DatabaseOperationException(
        'Failed to load category password entries.',
        e,
      );
    }
  }

  Future<List<PasswordEntryModel>> getFavoriteEntries(
    SecretKey masterKey,
  ) async {
    try {
      final db = await _db.database;
      final rows = await db.query(
        'password_entries',
        where: 'is_favorite = 1',
        orderBy: 'title COLLATE NOCASE ASC',
      );

      final List<PasswordEntryModel> list = [];
      for (final row in rows) {
        final entry = PasswordEntryModel.fromMap(row);
        final decrypted = await entry.decrypt(
          masterKey: masterKey,
          encryptionService: _encryptionService,
        );
        list.add(decrypted);
      }
      return list;
    } catch (e) {
      throw DatabaseOperationException('Failed to load favorite passwords.', e);
    }
  }

  Future<PasswordEntryModel?> getEntryById(
    String id,
    SecretKey masterKey,
  ) async {
    try {
      final db = await _db.database;
      final rows = await db.query(
        'password_entries',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (rows.isEmpty) return null;
      final entry = PasswordEntryModel.fromMap(rows.first);
      return await entry.decrypt(
        masterKey: masterKey,
        encryptionService: _encryptionService,
      );
    } catch (e) {
      throw DatabaseOperationException('Failed to load password entry.', e);
    }
  }

  Future<void> insertEntry(PasswordEntryModel entry) async {
    try {
      final db = await _db.database;
      await db.transaction((txn) async {
        await txn.insert(
          'password_entries',
          entry.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });
    } catch (e) {
      throw DatabaseOperationException('Failed to save password entry.', e);
    }
  }

  Future<void> updateEntry(PasswordEntryModel entry) async {
    try {
      final db = await _db.database;
      await db.transaction((txn) async {
        await txn.update(
          'password_entries',
          entry.toMap(),
          where: 'id = ?',
          whereArgs: [entry.id],
        );
      });
    } catch (e) {
      throw DatabaseOperationException('Failed to update password entry.', e);
    }
  }

  Future<void> deleteEntry(String id) async {
    try {
      final db = await _db.database;
      await db.transaction((txn) async {
        await txn.delete('password_entries', where: 'id = ?', whereArgs: [id]);
      });
    } catch (e) {
      throw DatabaseOperationException('Failed to delete password entry.', e);
    }
  }

  Future<void> toggleFavorite(String id, bool isFavorite) async {
    try {
      final db = await _db.database;
      await db.update(
        'password_entries',
        {
          'is_favorite': isFavorite ? 1 : 0,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      throw DatabaseOperationException(
        'Failed to toggle password favorite.',
        e,
      );
    }
  }

  Future<void> updateLastAccessed(String id) async {
    try {
      final db = await _db.database;
      await db.update(
        'password_entries',
        {'last_accessed_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (_) {}
  }
}
