import 'package:cryptography/cryptography.dart';
import 'package:sqflite/sqflite.dart';
import '../../../core/database/vault_database.dart';
import '../../../core/errors/exceptions.dart';
import '../../../core/security/encryption_service.dart';
import '../domain/bank_account_model.dart';

class BankVaultRepository {
  final VaultDatabase _db;
  final EncryptionService _encryptionService;

  BankVaultRepository({
    VaultDatabase? db,
    EncryptionService? encryptionService,
  })  : _db = db ?? VaultDatabase.instance,
        _encryptionService = encryptionService ?? EncryptionService();

  Future<List<BankAccountModel>> getAllAccounts(SecretKey masterKey) async {
    try {
      final db = await _db.database;
      final rows = await db.query(
        'bank_accounts',
        orderBy: 'bank_name COLLATE NOCASE ASC',
      );

      final List<BankAccountModel> list = [];
      for (final row in rows) {
        final account = BankAccountModel.fromMap(row);
        final decrypted = await account.decrypt(
          masterKey: masterKey,
          encryptionService: _encryptionService,
        );
        list.add(decrypted);
      }
      return list;
    } catch (e) {
      throw DatabaseOperationException('Failed to load bank accounts.', e);
    }
  }

  Future<List<BankAccountModel>> getFavoriteAccounts(SecretKey masterKey) async {
    try {
      final db = await _db.database;
      final rows = await db.query(
        'bank_accounts',
        where: 'is_favorite = 1',
        orderBy: 'bank_name COLLATE NOCASE ASC',
      );

      final List<BankAccountModel> list = [];
      for (final row in rows) {
        final account = BankAccountModel.fromMap(row);
        final decrypted = await account.decrypt(
          masterKey: masterKey,
          encryptionService: _encryptionService,
        );
        list.add(decrypted);
      }
      return list;
    } catch (e) {
      throw DatabaseOperationException('Failed to load favorite bank accounts.', e);
    }
  }

  Future<BankAccountModel?> getAccountById(String id, SecretKey masterKey) async {
    try {
      final db = await _db.database;
      final rows = await db.query(
        'bank_accounts',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (rows.isEmpty) return null;
      final account = BankAccountModel.fromMap(rows.first);
      return await account.decrypt(
        masterKey: masterKey,
        encryptionService: _encryptionService,
      );
    } catch (e) {
      throw DatabaseOperationException('Failed to load bank account.', e);
    }
  }

  Future<void> insertAccount(BankAccountModel account) async {
    try {
      final db = await _db.database;
      await db.transaction((txn) async {
        await txn.insert(
          'bank_accounts',
          account.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });
    } catch (e) {
      throw DatabaseOperationException('Failed to save bank account.', e);
    }
  }

  Future<void> updateAccount(BankAccountModel account) async {
    try {
      final db = await _db.database;
      await db.transaction((txn) async {
        await txn.update(
          'bank_accounts',
          account.toMap(),
          where: 'id = ?',
          whereArgs: [account.id],
        );
      });
    } catch (e) {
      throw DatabaseOperationException('Failed to update bank account.', e);
    }
  }

  Future<void> deleteAccount(String id) async {
    try {
      final db = await _db.database;
      await db.transaction((txn) async {
        await txn.delete(
          'bank_accounts',
          where: 'id = ?',
          whereArgs: [id],
        );
      });
    } catch (e) {
      throw DatabaseOperationException('Failed to delete bank account.', e);
    }
  }

  Future<void> toggleFavorite(String id, bool isFavorite) async {
    try {
      final db = await _db.database;
      await db.update(
        'bank_accounts',
        {
          'is_favorite': isFavorite ? 1 : 0,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      throw DatabaseOperationException('Failed to toggle bank account favorite.', e);
    }
  }
}

