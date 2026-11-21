import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/database/vault_database.dart';
import '../../../core/security/encryption_service.dart';
import '../domain/document_draft_model.dart';

final documentDraftRepositoryProvider = Provider<DocumentDraftRepository>((
  ref,
) {
  return DocumentDraftRepository();
});

/// Repository for persisting unsaved document creation state
/// encrypted with AES-256-GCM using the active vault master key.
class DocumentDraftRepository {
  final VaultDatabase _dbHelper;
  final EncryptionService _encryptionService;

  DocumentDraftRepository({
    VaultDatabase? dbHelper,
    EncryptionService? encryptionService,
  }) : _dbHelper = dbHelper ?? VaultDatabase.instance,
       _encryptionService = encryptionService ?? EncryptionService();

  /// Saves the document draft encrypted with the master key.
  Future<void> saveDraft(DocumentDraftModel draft, SecretKey masterKey) async {
    final db = await _dbHelper.database;
    final jsonStr = jsonEncode(draft.toMap());
    final encryptedData = await _encryptionService.encryptString(
      jsonStr,
      masterKey,
    );
    final nowIso = DateTime.now().toIso8601String();

    await db.insert('document_drafts', {
      'id': draft.id,
      'encrypted_draft_data': encryptedData,
      'updated_at': nowIso,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Retrieves and decrypts the document draft. Returns null if none exists.
  Future<DocumentDraftModel?> getDraft(
    SecretKey masterKey, {
    String id = 'active_draft',
  }) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'document_drafts',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (rows.isEmpty) return null;

    final encData = rows.first['encrypted_draft_data'] as String?;
    if (encData == null || encData.isEmpty) return null;

    try {
      final decryptedJson = await _encryptionService.decryptString(
        encData,
        masterKey,
      );
      final map = jsonDecode(decryptedJson) as Map<String, dynamic>;
      return DocumentDraftModel.fromMap(map);
    } catch (_) {
      // In case key changed or decryption fails, ignore corrupted draft
      return null;
    }
  }

  /// Checks if an encrypted draft currently exists.
  Future<bool> hasDraft({String id = 'active_draft'}) async {
    final db = await _dbHelper.database;
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM document_drafts WHERE id = ?', [
        id,
      ]),
    );
    return (count ?? 0) > 0;
  }

  /// Deletes the draft after saving or on explicit user discard.
  Future<void> deleteDraft({String id = 'active_draft'}) async {
    final db = await _dbHelper.database;
    await db.delete('document_drafts', where: 'id = ?', whereArgs: [id]);
  }
}
