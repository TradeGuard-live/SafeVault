import 'package:cryptography/cryptography.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/vault_database.dart';
import '../../../core/errors/exceptions.dart';
import '../../documents/data/document_repository.dart';
import '../../documents/domain/document_model.dart';
import '../domain/document_group_model.dart';

class DocumentGroupRepository {
  final VaultDatabase _dbHelper;
  final DocumentRepository? documentRepository;
  final Uuid _uuid = const Uuid();

  DocumentGroupRepository({
    VaultDatabase? dbHelper,
    this.documentRepository,
  })  : _dbHelper = dbHelper ?? VaultDatabase.instance;

  /// Creates a new custom document group.
  Future<DocumentGroupModel> createGroup({
    required String name,
    String? description,
    required String icon,
    required int colorValue,
  }) async {
    final db = await _dbHelper.database;
    final now = DateTime.now();
    final group = DocumentGroupModel(
      id: _uuid.v4(),
      name: name.trim(),
      description: description?.trim().isEmpty ?? true ? null : description!.trim(),
      icon: icon,
      colorValue: colorValue,
      createdAt: now,
      updatedAt: now,
    );

    await db.insert('document_groups', group.toMap());
    return group;
  }

  /// Retrieves all document groups with real-time active document counts.
  Future<List<DocumentGroupModel>> getGroups() async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery('''
      SELECT g.*, 
        (SELECT COUNT(DISTINCT m.document_id) 
         FROM document_group_memberships m 
         INNER JOIN documents d ON d.id = m.document_id 
         WHERE m.group_id = g.id AND d.deleted_at IS NULL) AS doc_count
      FROM document_groups g
      ORDER BY g.name COLLATE NOCASE ASC;
    ''');

    return rows.map((r) => DocumentGroupModel.fromMap(r)).toList();
  }

  /// Retrieves a specific document group by ID.
  Future<DocumentGroupModel?> getGroupById(String groupId) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery('''
      SELECT g.*, 
        (SELECT COUNT(DISTINCT m.document_id) 
         FROM document_group_memberships m 
         INNER JOIN documents d ON d.id = m.document_id 
         WHERE m.group_id = g.id AND d.deleted_at IS NULL) AS doc_count
      FROM document_groups g
      WHERE g.id = ?;
    ''', [groupId]);

    if (rows.isEmpty) return null;
    return DocumentGroupModel.fromMap(rows.first);
  }

  /// Updates an existing document group.
  Future<DocumentGroupModel> updateGroup({
    required String id,
    String? name,
    String? description,
    String? icon,
    int? colorValue,
  }) async {
    final db = await _dbHelper.database;
    final existing = await getGroupById(id);
    if (existing == null) {
      throw DatabaseOperationException('Document group not found: $id');
    }

    final updated = existing.copyWith(
      name: name?.trim(),
      description: description?.trim(),
      icon: icon,
      colorValue: colorValue,
      updatedAt: DateTime.now(),
    );

    await db.update(
      'document_groups',
      updated.toMap(),
      where: 'id = ?',
      whereArgs: [id],
    );

    return updated;
  }

  /// Deletes a document group.
  /// IMPORTANT: Never deletes the original documents! Only deletes memberships.
  Future<void> deleteGroup(String groupId) async {
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      await txn.delete(
        'document_group_memberships',
        where: 'group_id = ?',
        whereArgs: [groupId],
      );
      await txn.delete(
        'document_groups',
        where: 'id = ?',
        whereArgs: [groupId],
      );
    });
  }

  /// Adds documents to a group (prevents duplicates).
  Future<void> addDocumentsToGroup({
    required String groupId,
    required List<String> documentIds,
  }) async {
    if (documentIds.isEmpty) return;
    final db = await _dbHelper.database;
    final now = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      for (final docId in documentIds) {
        await txn.insert(
          'document_group_memberships',
          {
            'document_id': docId,
            'group_id': groupId,
            'created_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  /// Removes documents from a group (never deletes original documents).
  Future<void> removeDocumentsFromGroup({
    required String groupId,
    required List<String> documentIds,
  }) async {
    if (documentIds.isEmpty) return;
    final db = await _dbHelper.database;
    await db.transaction((txn) async {
      for (final docId in documentIds) {
        await txn.delete(
          'document_group_memberships',
          where: 'document_id = ? AND group_id = ?',
          whereArgs: [docId, groupId],
        );
      }
    });
  }

  /// Retrieves groups that a specific document belongs to.
  Future<List<DocumentGroupModel>> getGroupsForDocument(String documentId) async {
    final db = await _dbHelper.database;
    final rows = await db.rawQuery('''
      SELECT g.*, 0 AS doc_count
      FROM document_groups g
      INNER JOIN document_group_memberships m ON m.group_id = g.id
      WHERE m.document_id = ?
      ORDER BY g.name COLLATE NOCASE ASC;
    ''', [documentId]);

    return rows.map((r) => DocumentGroupModel.fromMap(r)).toList();
  }

  /// Sets all groups for a document in a single transaction.
  Future<void> setDocumentGroups({
    required String documentId,
    required List<String> groupIds,
  }) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      await txn.delete(
        'document_group_memberships',
        where: 'document_id = ?',
        whereArgs: [documentId],
      );
      for (final gId in groupIds) {
        await txn.insert(
          'document_group_memberships',
          {
            'document_id': documentId,
            'group_id': gId,
            'created_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  /// Searches groups by name or description.
  Future<List<DocumentGroupModel>> searchGroups(String query) async {
    final db = await _dbHelper.database;
    final q = '%${query.trim()}%';
    final rows = await db.rawQuery('''
      SELECT g.*, 
        (SELECT COUNT(DISTINCT m.document_id) 
         FROM document_group_memberships m 
         INNER JOIN documents d ON d.id = m.document_id 
         WHERE m.group_id = g.id AND d.deleted_at IS NULL) AS doc_count
      FROM document_groups g
      WHERE g.name LIKE ? OR g.description LIKE ?
      ORDER BY g.name COLLATE NOCASE ASC;
    ''', [q, q]);

    return rows.map((r) => DocumentGroupModel.fromMap(r)).toList();
  }

  /// Queries all active documents belonging to a group.
  Future<List<DocumentModel>> getDocumentsByGroup(
    String groupId,
    SecretKey masterKey,
  ) async {
    final docRepo = documentRepository;
    if (docRepo != null) {
      return await docRepo.getDocumentsByGroup(groupId, masterKey);
    }
    final db = await _dbHelper.database;
    final rows = await db.rawQuery('''
      SELECT d.*
      FROM documents d
      INNER JOIN document_group_memberships m ON m.document_id = d.id
      WHERE m.group_id = ? AND d.deleted_at IS NULL
      ORDER BY d.updated_at DESC;
    ''', [groupId]);

    // Fallback if DocumentRepository is null
    return rows.map((r) => DocumentModel(
      id: r['id'] as String,
      name: r['name'] as String,
      categoryId: r['category_id'] as String,
      createdAt: DateTime.parse(r['created_at'] as String),
      updatedAt: DateTime.parse(r['updated_at'] as String),
      isTemporary: (r['is_temporary'] as int? ?? 0) == 1,
      expiresAt: r['expires_at'] != null ? DateTime.parse(r['expires_at'] as String) : null,
      expiryStatus: r['expiry_status'] as String? ?? 'ACTIVE',
    )).toList();
  }
}
