import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import '../../../core/database/vault_database.dart';
import '../../../core/errors/exceptions.dart';
import '../../../core/notifications/local_notification_service.dart';
import '../../../core/security/encryption_service.dart';
import '../../../core/storage/encrypted_file_storage.dart';
import '../../ocr/data/document_field_extractor.dart';
import '../../ocr/domain/document_extraction_model.dart';
import '../../timeline/data/activity_repository.dart';
import '../domain/document_file_model.dart';
import '../domain/document_model.dart';

class DocumentRepository {
  final VaultDatabase _dbHelper;
  final EncryptionService _encryptionService;
  final EncryptedFileStorage _storage;
  final LocalNotificationService _notifications;
  final ActivityRepository _activities;
  final Uuid _uuid = const Uuid();

  DocumentRepository({
    VaultDatabase? dbHelper,
    EncryptionService? encryptionService,
    EncryptedFileStorage? storage,
    LocalNotificationService? notifications,
    ActivityRepository? activities,
  })  : _dbHelper = dbHelper ?? VaultDatabase.instance,
        _encryptionService = encryptionService ?? EncryptionService(),
        _storage = storage ?? EncryptedFileStorage(),
        _notifications = notifications ?? LocalNotificationService.instance,
        _activities = activities ?? ActivityRepository();

  /// Adds a new encrypted document with its files and schedules reminders.
  Future<DocumentModel> addDocument({
    required String name,
    required String categoryId,
    String? documentNumber,
    String? ownerName,
    String? issuingAuthority,
    DateTime? issueDate,
    DateTime? expiryDate,
    String? notes,
    List<String> tags = const [],
    String? documentType,
    String? thumbnailEncPath,
    required List<DocumentFileModel> files,
    required SecretKey masterKey,
    bool isScanned = false,
  }) async {
    final db = await _dbHelper.database;
    final now = DateTime.now();
    final docId = _uuid.v4();

    // Encrypt sensitive metadata fields
    String? docNumEnc;
    if (documentNumber != null && documentNumber.trim().isNotEmpty) {
      docNumEnc = await _encryptionService.encryptString(documentNumber.trim(), masterKey);
    }
    String? ownerNameEnc;
    if (ownerName != null && ownerName.trim().isNotEmpty) {
      ownerNameEnc = await _encryptionService.encryptString(ownerName.trim(), masterKey);
    }
    String? authorityEnc;
    if (issuingAuthority != null && issuingAuthority.trim().isNotEmpty) {
      authorityEnc = await _encryptionService.encryptString(issuingAuthority.trim(), masterKey);
    }
    String? notesEnc;
    if (notes != null && notes.trim().isNotEmpty) {
      notesEnc = await _encryptionService.encryptString(notes.trim(), masterKey);
    }

    final docMap = {
      'id': docId,
      'name': name.trim(),
      'category_id': categoryId,
      'document_number_enc': docNumEnc,
      'owner_name_enc': ownerNameEnc,
      'issuing_authority_enc': authorityEnc,
      'issue_date': issueDate?.toIso8601String(),
      'expiry_date': expiryDate?.toIso8601String(),
      'notes_enc': notesEnc,
      'tags_json': jsonEncode(tags),
      'is_favorite': 0,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
      'deleted_at': null,
      'thumbnail_enc_path': thumbnailEncPath,
      'document_type': documentType,
    };

    await db.transaction((txn) async {
      await txn.insert('documents', docMap);

      for (int i = 0; i < files.length; i++) {
        final f = files[i];
        final fileMap = {
          'id': f.id.isEmpty ? _uuid.v4() : f.id,
          'document_id': docId,
          'encrypted_file_path': f.encryptedFilePath,
          'original_file_name': f.originalFileName,
          'mime_type': f.mimeType,
          'file_size': f.fileSize,
          'page_number': i + 1,
          'encryption_version': f.encryptionVersion,
          'created_at': now.toIso8601String(),
        };
        await txn.insert('document_files', fileMap);
      }
    });

    // Schedule expiry reminders if expiry date is provided
    if (expiryDate != null) {
      await _scheduleRemindersForDocument(
        documentId: docId,
        documentName: name,
        expiryDate: expiryDate,
      );
    }

    // Log Activity
    await _activities.logActivity(
      documentId: docId,
      documentName: name,
      activityType: isScanned ? 'DOCUMENT_SCANNED' : 'DOCUMENT_ADDED',
      details: 'Added ${files.length} page(s) to $name',
    );

    return DocumentModel(
      id: docId,
      name: name,
      categoryId: categoryId,
      documentNumber: documentNumber,
      ownerName: ownerName,
      issuingAuthority: issuingAuthority,
      issueDate: issueDate,
      expiryDate: expiryDate,
      notes: notes,
      tags: tags,
      isFavorite: false,
      createdAt: now,
      updatedAt: now,
      thumbnailEncPath: thumbnailEncPath,
      documentType: documentType,
      files: files,
    );
  }

  /// Updates document metadata and schedules/updates reminders.
  Future<void> updateDocumentMetadata({
    required String documentId,
    required String name,
    required String categoryId,
    String? documentNumber,
    String? ownerName,
    String? issuingAuthority,
    DateTime? issueDate,
    DateTime? expiryDate,
    String? notes,
    List<String> tags = const [],
    String? documentType,
    required SecretKey masterKey,
  }) async {
    final db = await _dbHelper.database;
    final now = DateTime.now();

    // Encrypt sensitive metadata fields
    String? docNumEnc;
    if (documentNumber != null && documentNumber.trim().isNotEmpty) {
      docNumEnc = await _encryptionService.encryptString(documentNumber.trim(), masterKey);
    }
    String? ownerNameEnc;
    if (ownerName != null && ownerName.trim().isNotEmpty) {
      ownerNameEnc = await _encryptionService.encryptString(ownerName.trim(), masterKey);
    }
    String? authorityEnc;
    if (issuingAuthority != null && issuingAuthority.trim().isNotEmpty) {
      authorityEnc = await _encryptionService.encryptString(issuingAuthority.trim(), masterKey);
    }
    String? notesEnc;
    if (notes != null && notes.trim().isNotEmpty) {
      notesEnc = await _encryptionService.encryptString(notes.trim(), masterKey);
    }

    await db.update(
      'documents',
      {
        'name': name.trim(),
        'category_id': categoryId,
        'document_number_enc': docNumEnc,
        'owner_name_enc': ownerNameEnc,
        'issuing_authority_enc': authorityEnc,
        'issue_date': issueDate?.toIso8601String(),
        'expiry_date': expiryDate?.toIso8601String(),
        'notes_enc': notesEnc,
        'tags_json': jsonEncode(tags),
        'document_type': documentType,
        'updated_at': now.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [documentId],
    );

    // Refresh reminders
    await _cancelRemindersForDocument(documentId);
    if (expiryDate != null) {
      await _scheduleRemindersForDocument(
        documentId: documentId,
        documentName: name,
        expiryDate: expiryDate,
      );
    }

    await _activities.logActivity(
      documentId: documentId,
      documentName: name,
      activityType: 'DOCUMENT_UPDATED',
      details: 'Updated metadata for $name',
    );
  }

  /// Appends another page file to an existing document.
  Future<void> addDocumentPageFile({
    required String documentId,
    required DocumentFileModel file,
  }) async {
    final db = await _dbHelper.database;
    final existingFiles = await db.query(
      'document_files',
      where: 'document_id = ?',
      whereArgs: [documentId],
    );

    final pageNumber = existingFiles.length + 1;
    await db.insert('document_files', {
      'id': file.id.isEmpty ? _uuid.v4() : file.id,
      'document_id': documentId,
      'encrypted_file_path': file.encryptedFilePath,
      'original_file_name': file.originalFileName,
      'mime_type': file.mimeType,
      'file_size': file.fileSize,
      'page_number': pageNumber,
      'encryption_version': file.encryptionVersion,
      'created_at': DateTime.now().toIso8601String(),
    });

    await db.update(
      'documents',
      {'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [documentId],
    );

    await _activities.logActivity(
      documentId: documentId,
      documentName: file.originalFileName,
      activityType: 'DOCUMENT_UPDATED',
      details: 'Added page $pageNumber to document',
    );
  }

  /// Toggles favorite status.
  Future<bool> toggleFavorite(String documentId, bool currentStatus) async {
    final db = await _dbHelper.database;
    final newStatus = !currentStatus;
    await db.update(
      'documents',
      {'is_favorite': newStatus ? 1 : 0},
      where: 'id = ?',
      whereArgs: [documentId],
    );

    final docRows = await db.query('documents', where: 'id = ?', whereArgs: [documentId]);
    if (docRows.isNotEmpty) {
      final name = docRows.first['name'] as String;
      await _activities.logActivity(
        documentId: documentId,
        documentName: name,
        activityType: 'FAVORITE_TOGGLED',
        details: newStatus ? 'Marked $name as favorite' : 'Removed $name from favorites',
      );
    }

    return newStatus;
  }

  /// Soft deletes a document (moves to trash).
  Future<void> moveToTrash(String documentId) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toIso8601String();

    await db.update(
      'documents',
      {'deleted_at': now},
      where: 'id = ?',
      whereArgs: [documentId],
    );

    await _cancelRemindersForDocument(documentId);

    final docRows = await db.query('documents', where: 'id = ?', whereArgs: [documentId]);
    if (docRows.isNotEmpty) {
      final name = docRows.first['name'] as String;
      await _activities.logActivity(
        documentId: documentId,
        documentName: name,
        activityType: 'MOVED_TO_TRASH',
        details: 'Moved $name to trash',
      );
    }
  }

  /// Restores a soft-deleted document from trash.
  Future<void> restoreFromTrash(String documentId) async {
    final db = await _dbHelper.database;
    await db.update(
      'documents',
      {'deleted_at': null},
      where: 'id = ?',
      whereArgs: [documentId],
    );

    final docRows = await db.query('documents', where: 'id = ?', whereArgs: [documentId]);
    if (docRows.isNotEmpty) {
      final name = docRows.first['name'] as String;
      final expiryStr = docRows.first['expiry_date'] as String?;
      if (expiryStr != null) {
        final expiry = DateTime.tryParse(expiryStr);
        if (expiry != null && expiry.isAfter(DateTime.now())) {
          await _scheduleRemindersForDocument(
            documentId: documentId,
            documentName: name,
            expiryDate: expiry,
          );
        }
      }

      await _activities.logActivity(
        documentId: documentId,
        documentName: name,
        activityType: 'DOCUMENT_RESTORED',
        details: 'Restored $name from trash',
      );
    }
  }

  /// Permanently deletes a document, wiping its encrypted files and database records.
  Future<void> permanentlyDeleteDocument(String documentId) async {
    final db = await _dbHelper.database;

    // 1. Get files and thumbnail to securely delete from disk
    final docRows = await db.query('documents', where: 'id = ?', whereArgs: [documentId]);
    String docName = 'Document';
    if (docRows.isNotEmpty) {
      docName = docRows.first['name'] as String;
      final thumbPath = docRows.first['thumbnail_enc_path'] as String?;
      if (thumbPath != null) {
        await _storage.securelyDeleteFile(thumbPath);
      }
    }

    final fileRows = await db.query('document_files', where: 'document_id = ?', whereArgs: [documentId]);
    for (final row in fileRows) {
      final path = row['encrypted_file_path'] as String;
      await _storage.securelyDeleteFile(path);
    }

    // 2. Cancel reminders
    await _cancelRemindersForDocument(documentId);

    // 3. Delete from database
    await db.transaction((txn) async {
      await txn.delete('reminders', where: 'document_id = ?', whereArgs: [documentId]);
      await txn.delete('document_files', where: 'document_id = ?', whereArgs: [documentId]);
      await txn.delete('documents', where: 'id = ?', whereArgs: [documentId]);
    });

    await _activities.logActivity(
      documentId: null, // detached reference
      documentName: docName,
      activityType: 'PERMANENTLY_DELETED',
      details: 'Permanently deleted $docName and securely purged encrypted storage',
    );
  }

  /// Empties all documents currently in trash.
  Future<int> emptyTrash() async {
    final db = await _dbHelper.database;
    final trashRows = await db.query('documents', where: 'deleted_at IS NOT NULL');
    for (final row in trashRows) {
      final docId = row['id'] as String;
      await permanentlyDeleteDocument(docId);
    }
    return trashRows.length;
  }

  /// Automatically purges trash items older than retention days (e.g. 30 days).
  Future<void> autoCleanupTrash(int retentionDays) async {
    final db = await _dbHelper.database;
    final cutoff = DateTime.now().subtract(Duration(days: retentionDays)).toIso8601String();
    final expiredTrash = await db.query(
      'documents',
      where: 'deleted_at IS NOT NULL AND deleted_at < ?',
      whereArgs: [cutoff],
    );
    for (final row in expiredTrash) {
      final docId = row['id'] as String;
      await permanentlyDeleteDocument(docId);
    }
  }

  /// Loads a single document with decrypted metadata and its files.
  Future<DocumentModel?> getDocumentById(String documentId, SecretKey masterKey) async {
    final db = await _dbHelper.database;
    final docRows = await db.query('documents', where: 'id = ?', whereArgs: [documentId]);
    if (docRows.isEmpty) return null;

    final fileRows = await db.query(
      'document_files',
      where: 'document_id = ?',
      whereArgs: [documentId],
      orderBy: 'page_number ASC',
    );

    final files = fileRows.map((r) => DocumentFileModel.fromMap(r)).toList();
    final doc = await _mapRowToDocument(docRows.first, files, masterKey);
    final extraction = await getExtractionForDocument(documentId, masterKey);
    return doc.copyWith(extraction: extraction);
  }

  /// Queries all non-deleted active documents.
  Future<List<DocumentModel>> getAllActiveDocuments(SecretKey masterKey) async {
    final db = await _dbHelper.database;
    final docRows = await db.query(
      'documents',
      where: 'deleted_at IS NULL',
      orderBy: 'updated_at DESC',
    );

    return await _mapRowsToDocuments(docRows, masterKey);
  }

  /// Queries non-deleted documents in a specific category.
  Future<List<DocumentModel>> getDocumentsByCategory(String categoryId, SecretKey masterKey) async {
    final db = await _dbHelper.database;
    final docRows = await db.query(
      'documents',
      where: 'deleted_at IS NULL AND category_id = ?',
      whereArgs: [categoryId],
      orderBy: 'updated_at DESC',
    );

    return await _mapRowsToDocuments(docRows, masterKey);
  }

  /// Queries favorite documents.
  Future<List<DocumentModel>> getFavoriteDocuments(SecretKey masterKey) async {
    final db = await _dbHelper.database;
    final docRows = await db.query(
      'documents',
      where: 'deleted_at IS NULL AND is_favorite = 1',
      orderBy: 'updated_at DESC',
    );

    return await _mapRowsToDocuments(docRows, masterKey);
  }

  /// Queries trash documents.
  Future<List<DocumentModel>> getTrashDocuments(SecretKey masterKey) async {
    final db = await _dbHelper.database;
    final docRows = await db.query(
      'documents',
      where: 'deleted_at IS NOT NULL',
      orderBy: 'deleted_at DESC',
    );

    return await _mapRowsToDocuments(docRows, masterKey);
  }

  /// Queries upcoming expiring documents.
  Future<List<DocumentModel>> getExpiringDocuments({
    int days = 30,
    required SecretKey masterKey,
  }) async {
    final db = await _dbHelper.database;
    final now = DateTime.now();
    final targetDate = now.add(Duration(days: days));

    final docRows = await db.query(
      'documents',
      where: 'deleted_at IS NULL AND expiry_date IS NOT NULL AND expiry_date <= ?',
      whereArgs: [targetDate.toIso8601String()],
      orderBy: 'expiry_date ASC',
    );

    return await _mapRowsToDocuments(docRows, masterKey);
  }

  /// Performs local offline search across decrypted fields.
  Future<List<DocumentModel>> searchDocuments(String query, SecretKey masterKey) async {
    final allDocs = await getAllActiveDocuments(masterKey);
    final cleanQuery = query.trim().toLowerCase();
    if (cleanQuery.isEmpty) return allDocs;

    return allDocs.where((doc) {
      if (doc.name.toLowerCase().contains(cleanQuery)) return true;
      if (doc.documentType?.toLowerCase().contains(cleanQuery) ?? false) return true;
      if (doc.documentNumber?.toLowerCase().contains(cleanQuery) ?? false) return true;
      if (doc.ownerName?.toLowerCase().contains(cleanQuery) ?? false) return true;
      if (doc.issuingAuthority?.toLowerCase().contains(cleanQuery) ?? false) return true;
      if (doc.notes?.toLowerCase().contains(cleanQuery) ?? false) return true;
      if (doc.tags.any((t) => t.toLowerCase().contains(cleanQuery))) return true;
      return false;
    }).toList();
  }

  Future<List<DocumentModel>> _mapRowsToDocuments(
    List<Map<String, dynamic>> rows,
    SecretKey masterKey,
  ) async {
    final db = await _dbHelper.database;
    final List<DocumentModel> result = [];

    for (final row in rows) {
      final docId = row['id'] as String;
      final fileRows = await db.query(
        'document_files',
        where: 'document_id = ?',
        whereArgs: [docId],
        orderBy: 'page_number ASC',
      );
      final files = fileRows.map((r) => DocumentFileModel.fromMap(r)).toList();
      final doc = await _mapRowToDocument(row, files, masterKey);
      result.add(doc);
    }

    return result;
  }

  Future<DocumentModel> _mapRowToDocument(
    Map<String, dynamic> row,
    List<DocumentFileModel> files,
    SecretKey masterKey,
  ) async {
    String? docNumber;
    final docNumEnc = row['document_number_enc'] as String?;
    if (docNumEnc != null && docNumEnc.isNotEmpty) {
      try {
        docNumber = await _encryptionService.decryptString(docNumEnc, masterKey);
      } catch (_) {}
    }

    String? ownerName;
    final ownerEnc = row['owner_name_enc'] as String?;
    if (ownerEnc != null && ownerEnc.isNotEmpty) {
      try {
        ownerName = await _encryptionService.decryptString(ownerEnc, masterKey);
      } catch (_) {}
    }

    String? issuingAuthority;
    final authEnc = row['issuing_authority_enc'] as String?;
    if (authEnc != null && authEnc.isNotEmpty) {
      try {
        issuingAuthority = await _encryptionService.decryptString(authEnc, masterKey);
      } catch (_) {}
    }

    String? notes;
    final notesEnc = row['notes_enc'] as String?;
    if (notesEnc != null && notesEnc.isNotEmpty) {
      try {
        notes = await _encryptionService.decryptString(notesEnc, masterKey);
      } catch (_) {}
    }

    List<String> tags = [];
    final tagsJson = row['tags_json'] as String?;
    if (tagsJson != null && tagsJson.isNotEmpty) {
      try {
        tags = (jsonDecode(tagsJson) as List).map((e) => e.toString()).toList();
      } catch (_) {}
    }

    return DocumentModel(
      id: row['id'] as String,
      name: row['name'] as String,
      categoryId: row['category_id'] as String,
      documentNumber: docNumber,
      ownerName: ownerName,
      issuingAuthority: issuingAuthority,
      issueDate: row['issue_date'] != null ? DateTime.parse(row['issue_date'] as String) : null,
      expiryDate: row['expiry_date'] != null ? DateTime.parse(row['expiry_date'] as String) : null,
      notes: notes,
      tags: tags,
      isFavorite: (row['is_favorite'] as int) == 1,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      deletedAt: row['deleted_at'] != null ? DateTime.parse(row['deleted_at'] as String) : null,
      thumbnailEncPath: row['thumbnail_enc_path'] as String?,
      documentType: row['document_type'] as String?,
      extractionStatus: row['extraction_status'] as String? ?? 'completed',
      extractedTxtEncPath: row['extracted_txt_enc_path'] as String?,
      files: files,
    );
  }

  /// Saves a complete document extraction and its structured fields encrypted.
  Future<DocumentExtractionModel> saveExtraction({
    required String documentId,
    String? documentType,
    required String extractedText,
    required List<RawExtractedField> fields,
    required String engine,
    required String language,
    required int pageCount,
    required SecretKey masterKey,
    String? encryptedTxtFilePath,
  }) async {
    final db = await _dbHelper.database;
    final now = DateTime.now();
    final extractionId = _uuid.v4();

    // Encrypt the full extracted text with AES-256-GCM
    final encText = await _encryptionService.encryptString(extractedText, masterKey);

    // Get current version count for this document
    final existing = await db.query(
      'document_extractions',
      where: 'document_id = ?',
      whereArgs: [documentId],
      orderBy: 'version DESC',
      limit: 1,
    );
    final version = existing.isNotEmpty ? (existing.first['version'] as int) + 1 : 1;

    final extractionModel = DocumentExtractionModel(
      id: extractionId,
      documentId: documentId,
      documentType: documentType,
      extractedTextEncrypted: encText,
      encryptedTxtFilePath: encryptedTxtFilePath,
      extractionEngine: engine,
      language: language,
      pageCount: pageCount,
      extractionStatus: 'completed',
      createdAt: now,
      updatedAt: now,
      version: version,
    );

    await db.transaction((txn) async {
      await txn.insert('document_extractions', extractionModel.toMap());

      for (final field in fields) {
        final encValue = await _encryptionService.encryptString(field.value, masterKey);
        final fieldId = _uuid.v4();
        await txn.insert('extracted_fields', {
          'id': fieldId,
          'extraction_id': extractionId,
          'document_id': documentId,
          'field_name': field.fieldName,
          'encrypted_value': encValue,
          'confidence': field.confidence,
          'confidence_category': field.confidenceCategory,
          'source_page': field.sourcePage,
          'verification_status': 'unverified',
          'is_selected': field.isSelected ? 1 : 0,
          'is_verified': 0,
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        });
      }

      await txn.update(
        'documents',
        {
          'extraction_status': 'completed',
          if (encryptedTxtFilePath != null) 'extracted_txt_enc_path': encryptedTxtFilePath,
          'updated_at': now.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [documentId],
      );
    });

    await _activities.logActivity(
      documentId: documentId,
      documentName: 'Document',
      activityType: 'TEXT_EXTRACTED',
      details: 'Extracted text and recognized ${fields.length} structured fields via $engine (v$version)',
    );

    return await getExtractionForDocument(documentId, masterKey) ?? extractionModel;
  }

  /// Updates selection flag of a single extracted field.
  Future<void> updateFieldSelection({
    required String fieldId,
    required bool isSelected,
  }) async {
    final db = await _dbHelper.database;
    await db.update(
      'extracted_fields',
      {
        'is_selected': isSelected ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [fieldId],
    );
  }

  /// Updates selection flag for all fields belonging to an extraction.
  Future<void> updateAllFieldsSelection({
    required String extractionId,
    required bool isSelected,
  }) async {
    final db = await _dbHelper.database;
    await db.update(
      'extracted_fields',
      {
        'is_selected': isSelected ? 1 : 0,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'extraction_id = ?',
      whereArgs: [extractionId],
    );
  }

  /// Saves updated or newly added extracted fields for an extraction.
  Future<void> saveExtractedFieldsList({
    required String extractionId,
    required String documentId,
    required List<ExtractedFieldModel> fields,
    required SecretKey masterKey,
  }) async {
    final db = await _dbHelper.database;
    final now = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      // Clear existing fields for this extraction
      await txn.delete(
        'extracted_fields',
        where: 'extraction_id = ?',
        whereArgs: [extractionId],
      );

      for (final field in fields) {
        String encValue = field.encryptedValue;
        if (field.plainValue != null && field.plainValue!.isNotEmpty) {
          encValue = await _encryptionService.encryptString(field.plainValue!, masterKey);
        }

        await txn.insert('extracted_fields', {
          'id': field.id,
          'extraction_id': extractionId,
          'document_id': documentId,
          'field_name': field.fieldName,
          'encrypted_value': encValue,
          'confidence': field.confidence,
          'confidence_category': field.confidenceCategory,
          'source_page': field.sourcePage,
          'verification_status': field.verificationStatus,
          'is_selected': field.isSelected ? 1 : 0,
          'is_verified': field.isVerified ? 1 : 0,
          'created_at': field.createdAt.toIso8601String(),
          'updated_at': now,
        });
      }
    });

    await _activities.logActivity(
      documentId: documentId,
      documentName: 'Document',
      activityType: 'FIELDS_UPDATED',
      details: 'Updated field selections: ${fields.where((f) => f.isSelected).length} selected of ${fields.length} total fields',
    );
  }

  /// Retrieves the latest decrypted extraction record for a document.
  Future<DocumentExtractionModel?> getExtractionForDocument(String documentId, SecretKey masterKey) async {
    final db = await _dbHelper.database;
    final rows = await db.query(
      'document_extractions',
      where: 'document_id = ?',
      whereArgs: [documentId],
      orderBy: 'version DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final row = rows.first;
    final extractionId = row['id'] as String;

    String? decryptedText;
    final encText = row['extracted_text_encrypted'] as String?;
    if (encText != null && encText.isNotEmpty) {
      try {
        decryptedText = await _encryptionService.decryptString(encText, masterKey);
      } catch (_) {}
    }

    final fieldRows = await db.query(
      'extracted_fields',
      where: 'extraction_id = ?',
      whereArgs: [extractionId],
    );

    final fields = <ExtractedFieldModel>[];
    for (final fRow in fieldRows) {
      final encVal = fRow['encrypted_value'] as String;
      String? plain;
      try {
        plain = await _encryptionService.decryptString(encVal, masterKey);
      } catch (_) {}
      fields.add(ExtractedFieldModel.fromMap(fRow, plain));
    }

    return DocumentExtractionModel.fromMap(row, fields).copyWith(
      extractedTextEncrypted: decryptedText,
    );
  }

  /// Updates extraction status for asynchronous tracking (e.g. 'extractingText', 'completed').
  Future<void> updateExtractionStatus(String documentId, String status) async {
    final db = await _dbHelper.database;
    await db.update(
      'documents',
      {
        'extraction_status': status,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [documentId],
    );
  }

  /// Encrypts human-readable extracted TXT content using AES-256-GCM and saves to vault_files.
  Future<String> saveExtractedTxtFile({
    required String documentId,
    required String textContent,
    required SecretKey masterKey,
  }) async {
    final bytes = Uint8List.fromList(utf8.encode(textContent));
    final encryptedPath = await _storage.saveEncryptedFile(
      plainBytes: bytes,
      masterKey: masterKey,
    );

    final db = await _dbHelper.database;
    await db.update(
      'documents',
      {
        'extracted_txt_enc_path': encryptedPath,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [documentId],
    );

    return encryptedPath;
  }

  /// Allows user to manually edit and correct an extracted structured field.
  Future<void> updateExtractedField({
    required String fieldId,
    required String newValue,
    required SecretKey masterKey,
  }) async {
    final db = await _dbHelper.database;
    final encValue = await _encryptionService.encryptString(newValue.trim(), masterKey);
    await db.update(
      'extracted_fields',
      {
        'encrypted_value': encValue,
        'verification_status': 'edited',
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [fieldId],
    );
  }

  Future<void> _scheduleRemindersForDocument({
    required String documentId,
    required String documentName,
    required DateTime expiryDate,
  }) async {
    try {
      final db = await _dbHelper.database;
      final reminderIntervals = [30, 15, 7, 1, 0];
      final now = DateTime.now();

      for (final days in reminderIntervals) {
        final scheduledDate = expiryDate.subtract(Duration(days: days));
        if (scheduledDate.isAfter(now)) {
          final notifId = (documentId.hashCode ^ days).abs() % 2147483647;
          try {
            await _notifications.scheduleExpiryReminder(
              notificationId: notifId,
              documentName: documentName,
              scheduledDate: scheduledDate,
              daysBefore: days,
            );

            await db.insert('reminders', {
              'id': _uuid.v4(),
              'document_id': documentId,
              'reminder_type': 'EXPIRY_$days',
              'days_before': days,
              'scheduled_date': scheduledDate.toIso8601String(),
              'is_enabled': 1,
              'notification_id': notifId,
            });
          } catch (itemError) {
            // Notification failure must never fail document storage
            continue;
          }
        }
      }
    } catch (_) {
      // Gracefully ignore reminder scheduling failures
    }
  }

  Future<void> _cancelRemindersForDocument(String documentId) async {
    final db = await _dbHelper.database;
    final rows = await db.query('reminders', where: 'document_id = ?', whereArgs: [documentId]);
    for (final row in rows) {
      final notifId = row['notification_id'] as int;
      await _notifications.cancelNotification(notifId);
    }
    await db.delete('reminders', where: 'document_id = ?', whereArgs: [documentId]);
  }
}

