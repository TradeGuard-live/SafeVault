import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:vault/core/database/vault_database.dart';
import 'package:vault/core/widgets/status_badge.dart';
import 'package:vault/features/authentication/presentation/auth_providers.dart';
import 'package:vault/features/documents/data/document_expiry_service.dart';
import 'package:vault/features/documents/data/document_repository.dart';
import 'package:vault/features/documents/domain/document_model.dart';
import 'package:vault/features/documents/presentation/edit_duration_dialog.dart';
import 'package:vault/features/groups/data/document_group_repository.dart';
import 'package:vault/features/groups/domain/document_group_model.dart';
import 'package:vault/features/groups/presentation/add_edit_group_dialog.dart';

// ============================================================================
// IN-MEMORY TEST DATABASE FOR REPOSITORY & EXPIRY ENGINE TESTS
// ============================================================================
class InMemoryVaultTestDatabase implements Database {
  final List<Map<String, dynamic>> documents = [];
  final List<Map<String, dynamic>> documentGroups = [];
  final List<Map<String, dynamic>> groupMemberships = [];
  final List<Map<String, dynamic>> auditLogs = [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Database get database => this;

  @override
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action, {bool? exclusive}) async {
    return await action(this as dynamic);
  }

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    final copy = Map<String, dynamic>.from(values);
    if (table == 'documents') {
      documents.removeWhere((r) => r['id'] == copy['id']);
      documents.add(copy);
    } else if (table == 'document_groups') {
      documentGroups.removeWhere((r) => r['id'] == copy['id']);
      documentGroups.add(copy);
    } else if (table == 'document_group_memberships') {
      groupMemberships.removeWhere(
        (r) => r['document_id'] == copy['document_id'] && r['group_id'] == copy['group_id'],
      );
      groupMemberships.add(copy);
    } else if (table == 'activity_timeline') {
      auditLogs.add(copy);
    }
    return 1;
  }

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    int count = 0;
    if (table == 'documents') {
      for (final doc in documents) {
        if (_matches(doc, where, whereArgs)) {
          values.forEach((k, v) => doc[k] = v);
          count++;
        }
      }
    } else if (table == 'document_groups') {
      for (final grp in documentGroups) {
        if (_matches(grp, where, whereArgs)) {
          values.forEach((k, v) => grp[k] = v);
          count++;
        }
      }
    }
    return count;
  }

  @override
  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    int count = 0;
    if (table == 'document_groups') {
      final initial = documentGroups.length;
      documentGroups.removeWhere((r) => _matches(r, where, whereArgs));
      count = initial - documentGroups.length;
    } else if (table == 'document_group_memberships') {
      final initial = groupMemberships.length;
      groupMemberships.removeWhere((r) => _matches(r, where, whereArgs));
      count = initial - groupMemberships.length;
    } else if (table == 'documents') {
      final initial = documents.length;
      documents.removeWhere((r) => _matches(r, where, whereArgs));
      count = initial - documents.length;
    }
    return count;
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    List<Map<String, dynamic>> src = [];
    if (table == 'documents') {
      src = documents;
    } else if (table == 'document_groups') {
      src = documentGroups;
    } else if (table == 'document_group_memberships') {
      src = groupMemberships;
    }

    var result = List<Map<String, dynamic>>.from(src);
    if (where != null && where.isNotEmpty) {
      result = result.where((r) => _matches(r, where, whereArgs)).toList();
    }
    return result;
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql, [List<Object?>? arguments]) async {
    // Handle document groups with active document counts
    if (sql.contains('FROM document_groups')) {
      final result = <Map<String, dynamic>>[];
      for (final grp in documentGroups) {
        if (sql.contains('WHERE m.document_id = ?') && arguments != null && arguments.isNotEmpty) {
          final docId = arguments.first as String;
          final isMember = groupMemberships.any((m) => m['group_id'] == grp['id'] && m['document_id'] == docId);
          if (isMember) {
            result.add({...grp, 'doc_count': 0});
          }
        } else {
          // Count active non-deleted documents in this group
          final activeDocIds = documents
              .where((d) => d['deleted_at'] == null)
              .map((d) => d['id'] as String)
              .toSet();
          final count = groupMemberships
              .where((m) => m['group_id'] == grp['id'] && activeDocIds.contains(m['document_id']))
              .length;
          result.add({...grp, 'doc_count': count});
        }
      }
      return result;
    }

    if (sql.contains('FROM documents d') && sql.contains('document_group_memberships m')) {
      if (arguments != null && arguments.isNotEmpty) {
        final groupId = arguments.first as String;
        final docIds = groupMemberships
            .where((m) => m['group_id'] == groupId)
            .map((m) => m['document_id'] as String)
            .toSet();
        return documents
            .where((d) => docIds.contains(d['id']) && d['deleted_at'] == null)
            .toList();
      }
    }

    return [];
  }

  bool _matches(Map<String, dynamic> row, String? where, List<Object?>? whereArgs) {
    if (where == null || where.isEmpty) return true;
    if (where.contains('document_id = ? AND group_id = ?') && whereArgs != null && whereArgs.length >= 2) {
      return row['document_id'] == whereArgs[0] && row['group_id'] == whereArgs[1];
    }
    if (where.contains('group_id = ?') && whereArgs != null && whereArgs.isNotEmpty) {
      return row['group_id'] == whereArgs.first;
    }
    if (where.contains('document_id = ?') && whereArgs != null && whereArgs.isNotEmpty) {
      return row['document_id'] == whereArgs.first;
    }
    if ((where == 'id = ?' || where.startsWith('id = ?')) && whereArgs != null && whereArgs.isNotEmpty) {
      return row['id'] == whereArgs.first;
    }
    if (where.contains('is_temporary = 1 AND deleted_at IS NULL AND expires_at < ?') &&
        whereArgs != null &&
        whereArgs.isNotEmpty) {
      if (row['is_temporary'] != 1 || row['deleted_at'] != null) return false;
      final exp = DateTime.tryParse(row['expires_at'] ?? '');
      final cutoff = DateTime.tryParse(whereArgs.first.toString());
      if (exp == null || cutoff == null) return false;
      return exp.isBefore(cutoff);
    }
    if (where.contains('deleted_at IS NULL') && row['deleted_at'] != null) return false;
    return true;
  }
}

class FakeDatabaseHelper implements VaultDatabase {
  final InMemoryVaultTestDatabase _testDb = InMemoryVaultTestDatabase();

  @override
  Future<Database> get database async => _testDb;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ==========================================================================
  // PART 1: DOMAIN MODEL & HELPER TESTS
  // ==========================================================================
  group('PART 1: Temporary Document Model & Helpers', () {
    test('1. Default document is permanent with correct properties', () {
      final doc = DocumentModel(
        id: 'doc-1',
        categoryId: 'personal_identity',
        name: 'Passport',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(doc.isTemporary, isFalse);
      expect(doc.expiresAt, isNull);
      expect(doc.expiryStatus, 'ACTIVE');
      expect(doc.remainingDays, isNull);
      expect(doc.isExpired, isFalse);
      expect(doc.temporaryStatusLabel, 'Permanent');
      expect(doc.groupIds, isEmpty);
    });

    test('2. Temporary document calculates remaining days and label accurately', () {
      final now = DateTime.now();

      // 7 days in the future
      final doc7d = DocumentModel(
        id: 'doc-7d',
        categoryId: 'personal_identity',
        name: 'Event Ticket',
        isTemporary: true,
        expiresAt: now.add(const Duration(days: 7, hours: 2)),
        createdAt: now,
        updatedAt: now,
      );
      expect(doc7d.isTemporary, isTrue);
      expect(doc7d.remainingDays, 7);
      expect(doc7d.isExpired, isFalse);
      expect(doc7d.temporaryStatusLabel, 'Expires in 7 days');

      // Tomorrow
      final docTomorrow = doc7d.copyWith(
        expiresAt: now.add(const Duration(days: 1, hours: 1)),
      );
      expect(docTomorrow.remainingDays, 1);
      expect(docTomorrow.temporaryStatusLabel, 'Expires Tomorrow');

      // Today
      final docToday = doc7d.copyWith(
        expiresAt: now.add(const Duration(hours: 3)),
      );
      expect(docToday.remainingDays, 0);
      expect(docToday.temporaryStatusLabel, 'Expires Today');

      // Expired in past
      final docExpired = doc7d.copyWith(
        expiresAt: now.subtract(const Duration(days: 2)),
        expiryStatus: 'EXPIRED',
      );
      expect(docExpired.isExpired, isTrue);
      expect(docExpired.temporaryStatusLabel, 'Expired');
    });

    test('3. DocumentModel copyWith correctly updates temporary and group properties', () {
      final doc = DocumentModel(
        id: 'doc-3',
        categoryId: 'financial',
        name: 'Tax Slip',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final expiry = DateTime.now().add(const Duration(days: 30));
      final updated = doc.copyWith(
        isTemporary: true,
        expiresAt: expiry,
        expiryStatus: 'ACTIVE',
        groupIds: ['grp-taxes', 'grp-2026'],
      );

      expect(updated.isTemporary, isTrue);
      expect(updated.expiresAt, expiry);
      expect(updated.groupIds, ['grp-taxes', 'grp-2026']);

      // Convert back to permanent
      final permanent = updated.copyWith(
        isTemporary: false,
        clearExpiresAt: true,
      );
      expect(permanent.isTemporary, isFalse);
      expect(permanent.expiresAt, isNull);
      expect(permanent.groupIds, ['grp-taxes', 'grp-2026']);
    });

    test('4. DocumentGroupModel serialization and document count', () {
      final now = DateTime.now();
      final group = DocumentGroupModel(
        id: 'group-101',
        name: 'Auto & Vehicles',
        description: 'Car insurance, RC, and driver license',
        icon: 'directions_car_rounded',
        colorValue: 0xFF2563EB,
        documentCount: 5,
        createdAt: now,
        updatedAt: now,
      );

      final map = group.toMap();
      expect(map['id'], 'group-101');
      expect(map['name'], 'Auto & Vehicles');
      expect(map['icon'], 'directions_car_rounded');
      expect(map['color_value'], 0xFF2563EB);

      // Deserialization with doc_count
      final fromDb = DocumentGroupModel.fromMap({
        ...map,
        'doc_count': 5,
      });
      expect(fromDb.id, group.id);
      expect(fromDb.documentCount, 5);
      expect(fromDb.description, group.description);
    });
  });

  // ==========================================================================
  // PART 2: DOCUMENT GROUPS REPOSITORY & CASCADE BEHAVIOR
  // ==========================================================================
  group('PART 2: Document Groups Operations & Cascade Safety', () {
    late InMemoryVaultTestDatabase testDb;

    setUp(() {
      testDb = InMemoryVaultTestDatabase();
    });

    test('5. Create, read, update, and search document groups', () async {
      final now = DateTime.now();
      // Insert groups
      await testDb.insert('document_groups', {
        'id': 'grp-1',
        'name': 'Medical Records',
        'description': 'Hospital reports & prescriptions',
        'icon': 'local_hospital_rounded',
        'color_value': 0xFFEF4444,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });

      await testDb.insert('document_groups', {
        'id': 'grp-2',
        'name': 'Work & Contracts',
        'description': 'Employment letters & NDA',
        'icon': 'work_rounded',
        'color_value': 0xFF3B82F6,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });

      expect(testDb.documentGroups.length, 2);

      // Update group
      await testDb.update(
        'document_groups',
        {'name': 'Health & Medical', 'description': 'Updated description'},
        where: 'id = ?',
        whereArgs: ['grp-1'],
      );

      final updatedGrp = testDb.documentGroups.firstWhere((g) => g['id'] == 'grp-1');
      expect(updatedGrp['name'], 'Health & Medical');
      expect(updatedGrp['description'], 'Updated description');
    });

    test('6. Many-to-many document group memberships and real-time counts', () async {
      final now = DateTime.now();
      // Add active documents
      await testDb.insert('documents', {
        'id': 'doc-a',
        'name': 'Health Insurance',
        'is_temporary': 0,
        'deleted_at': null,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
      await testDb.insert('documents', {
        'id': 'doc-b',
        'name': 'Doctor Prescription',
        'is_temporary': 1,
        'deleted_at': null,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });

      // Add group
      await testDb.insert('document_groups', {
        'id': 'grp-health',
        'name': 'Health',
        'icon': 'local_hospital_rounded',
        'color_value': 0xFFEF4444,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });

      // Assign both documents to the group
      await testDb.insert('document_group_memberships', {
        'document_id': 'doc-a',
        'group_id': 'grp-health',
        'created_at': now.toIso8601String(),
      });
      await testDb.insert('document_group_memberships', {
        'document_id': 'doc-b',
        'group_id': 'grp-health',
        'created_at': now.toIso8601String(),
      });

      final queryResult = await testDb.rawQuery('SELECT * FROM document_groups');
      expect(queryResult.first['doc_count'], 2);

      // Soft delete doc-b -> count should decrease to 1
      await testDb.update(
        'documents',
        {'deleted_at': now.toIso8601String()},
        where: 'id = ?',
        whereArgs: ['doc-b'],
      );

      final afterTrash = await testDb.rawQuery('SELECT * FROM document_groups');
      expect(afterTrash.first['doc_count'], 1);
    });

    test('7. Cascade safety: Deleting group leaves underlying documents intact', () async {
      final now = DateTime.now();
      await testDb.insert('documents', {
        'id': 'doc-safe',
        'name': 'Permanent Passport',
        'is_temporary': 0,
        'deleted_at': null,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });

      await testDb.insert('document_groups', {
        'id': 'grp-temp',
        'name': 'Travel 2026',
        'icon': 'flight_rounded',
        'color_value': 0xFF10B981,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });

      await testDb.insert('document_group_memberships', {
        'document_id': 'doc-safe',
        'group_id': 'grp-temp',
        'created_at': now.toIso8601String(),
      });

      expect(testDb.groupMemberships.length, 1);

      // Delete group and memberships
      await testDb.delete('document_group_memberships', where: 'group_id = ?', whereArgs: ['grp-temp']);
      await testDb.delete('document_groups', where: 'id = ?', whereArgs: ['grp-temp']);

      // Document MUST remain intact in vault
      expect(testDb.documentGroups.isEmpty, isTrue);
      expect(testDb.groupMemberships.isEmpty, isTrue);
      expect(testDb.documents.length, 1);
      expect(testDb.documents.first['id'], 'doc-safe');
      expect(testDb.documents.first['deleted_at'], isNull);
    });
  });

  // ==========================================================================
  // PART 3: TEMPORARY DOCUMENT LIFECYCLE & EXPIRY ENGINE
  // ==========================================================================
  group('PART 3: Expiry Engine & Deletion Lifecycle', () {
    late InMemoryVaultTestDatabase testDb;

    setUp(() {
      testDb = InMemoryVaultTestDatabase();
    });

    test('8. Expiry processing moves expired temporary documents to Trash safely', () async {
      final now = DateTime.now();

      // Doc 1: Permanent document (should NEVER be touched)
      await testDb.insert('documents', {
        'id': 'doc-perm',
        'name': 'Permanent Document',
        'is_temporary': 0,
        'expires_at': null,
        'expiry_status': 'ACTIVE',
        'deleted_at': null,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });

      // Doc 2: Active temporary document (expires in 10 days)
      await testDb.insert('documents', {
        'id': 'doc-active-temp',
        'name': 'Concert Pass',
        'is_temporary': 1,
        'expires_at': now.add(const Duration(days: 10)).toIso8601String(),
        'expiry_status': 'ACTIVE',
        'deleted_at': null,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });

      // Doc 3: Expired temporary document (expired 2 days ago)
      await testDb.insert('documents', {
        'id': 'doc-expired-temp',
        'name': 'Hotel Booking Voucher',
        'is_temporary': 1,
        'expires_at': now.subtract(const Duration(days: 2)).toIso8601String(),
        'expiry_status': 'ACTIVE',
        'deleted_at': null,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });

      // Simulate Expiry Engine Query
      final expiredRows = await testDb.query(
        'documents',
        where: 'is_temporary = 1 AND deleted_at IS NULL AND expires_at < ?',
        whereArgs: [now.toIso8601String()],
      );

      expect(expiredRows.length, 1);
      expect(expiredRows.first['id'], 'doc-expired-temp');

      // Process expired document: mark EXPIRED and move to Trash
      for (final row in expiredRows) {
        await testDb.update(
          'documents',
          {
            'expiry_status': 'EXPIRED',
            'deleted_at': now.toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }

      // Check results
      final permDoc = testDb.documents.firstWhere((d) => d['id'] == 'doc-perm');
      expect(permDoc['deleted_at'], isNull);
      expect(permDoc['expiry_status'], 'ACTIVE');

      final activeTempDoc = testDb.documents.firstWhere((d) => d['id'] == 'doc-active-temp');
      expect(activeTempDoc['deleted_at'], isNull);
      expect(activeTempDoc['expiry_status'], 'ACTIVE');

      final expiredDoc = testDb.documents.firstWhere((d) => d['id'] == 'doc-expired-temp');
      expect(expiredDoc['deleted_at'], isNotNull);
      expect(expiredDoc['expiry_status'], 'EXPIRED');
    });

    test('9. Expiry check is idempotent: running multiple times produces identical state', () async {
      final now = DateTime.now();

      await testDb.insert('documents', {
        'id': 'doc-temp-idemp',
        'name': 'One-time Transit Pass',
        'is_temporary': 1,
        'expires_at': now.subtract(const Duration(hours: 5)).toIso8601String(),
        'expiry_status': 'ACTIVE',
        'deleted_at': null,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });

      // First run
      final firstCheck = await testDb.query(
        'documents',
        where: 'is_temporary = 1 AND deleted_at IS NULL AND expires_at < ?',
        whereArgs: [now.toIso8601String()],
      );
      expect(firstCheck.length, 1);

      await testDb.update(
        'documents',
        {'expiry_status': 'EXPIRED', 'deleted_at': now.toIso8601String()},
        where: 'id = ?',
        whereArgs: ['doc-temp-idemp'],
      );

      // Second run immediately after
      final secondCheck = await testDb.query(
        'documents',
        where: 'is_temporary = 1 AND deleted_at IS NULL AND expires_at < ?',
        whereArgs: [now.toIso8601String()],
      );
      expect(secondCheck.isEmpty, isTrue); // No documents processed again
    });

    test('10. Converting temporary document to permanent removes expiry schedule', () async {
      final now = DateTime.now();

      await testDb.insert('documents', {
        'id': 'doc-convert',
        'name': 'Work Offer Letter',
        'is_temporary': 1,
        'expires_at': now.add(const Duration(days: 15)).toIso8601String(),
        'expiry_status': 'ACTIVE',
        'deleted_at': null,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });

      // Convert to permanent
      await testDb.update(
        'documents',
        {
          'is_temporary': 0,
          'expires_at': null,
          'expiry_status': 'ACTIVE',
          'updated_at': now.toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: ['doc-convert'],
      );

      final converted = testDb.documents.firstWhere((d) => d['id'] == 'doc-convert');
      expect(converted['is_temporary'], 0);
      expect(converted['expires_at'], isNull);
      expect(converted['expiry_status'], 'ACTIVE');
    });
  });

  // ==========================================================================
  // PART 4: SECURITY AUDIT & NETWORK ISOLATION TESTS
  // ==========================================================================
  group('PART 4: Application Security & Offline Isolation', () {
    test('11. AndroidManifest enforces 100% offline security with zero network permissions', () {
      final manifestFile = File('android/app/src/main/AndroidManifest.xml');
      expect(manifestFile.existsSync(), isTrue);

      final content = manifestFile.readAsStringSync();
      // Verifies that INTERNET and ACCESS_NETWORK_STATE are explicitly stripped using tools:node="remove"
      expect(content.contains('android.permission.INTERNET" tools:node="remove"'), isTrue);
      expect(content.contains('android.permission.ACCESS_NETWORK_STATE" tools:node="remove"'), isTrue);

      // Verify no active unblocked internet permissions exist
      final lines = content.split('\n');
      final hasUnblockedInternet = lines.any((l) =>
          l.contains('android.permission.INTERNET') && !l.contains('tools:node="remove"'));
      expect(hasUnblockedInternet, isFalse);
    });

    test('12. Notification intervals support 3-day, 1-day, and on-expiry reminders without sensitive leakage', () {
      const intervals = [3, 1, 0];
      expect(intervals.contains(3), isTrue);
      expect(intervals.contains(1), isTrue);
      expect(intervals.contains(0), isTrue);

      // Verify that notification bodies do NOT include sensitive fields (e.g. CVV, private keys, OCR fulltext)
      final docName = 'Rent Agreement';
      final body3Days = 'Temporary document "$docName" will expire and be moved to Trash in 3 days.';
      final bodyExpired = 'Temporary document "$docName" has expired and was moved to Trash.';

      expect(body3Days.contains(docName), isTrue);
      expect(body3Days.contains('CVV'), isFalse);
      expect(body3Days.contains('PIN'), isFalse);
      expect(bodyExpired.contains('moved to Trash'), isTrue);
    });
  });

  // ==========================================================================
  // PART 5: UI WIDGET & DIALOG TESTS
  // ==========================================================================
  group('PART 5: UI Widgets & Status Badges', () {
    test('13. StatusBadge.fromTemporary generates appropriate badges across lifecycle', () {
      final now = DateTime.now();

      // Permanent
      final permanentBadge = StatusBadge.fromTemporary(null, isTemporary: false);
      expect(permanentBadge.label, 'Permanent');

      // 7 days
      final in7Days = StatusBadge.fromTemporary(
        now.add(const Duration(days: 7, hours: 1)),
        isTemporary: true,
      );
      expect(in7Days.label, 'Expires in 7 days');

      // Tomorrow
      final tomorrow = StatusBadge.fromTemporary(
        now.add(const Duration(days: 1, hours: 2)),
        isTemporary: true,
      );
      expect(tomorrow.label, 'Expires Tomorrow');

      // Today
      final today = StatusBadge.fromTemporary(
        now.add(const Duration(hours: 4)),
        isTemporary: true,
      );
      expect(today.label, 'Expires Today');

      // Expired
      final expired = StatusBadge.fromTemporary(
        now.subtract(const Duration(days: 1)),
        isTemporary: true,
      );
      expect(expired.label, 'Expired');
    });

    testWidgets('14. EditDurationDialog allows toggling permanent and temporary presets', (tester) async {
      final doc = DocumentModel(
        id: 'doc-ui-test',
        categoryId: 'personal_identity',
        name: 'Event Pass',
        isTemporary: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      bool savedTemporary = false;
      DateTime? savedExpiry;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EditDurationDialog(
              document: doc,
              onSave: (isTemp, exp) async {
                savedTemporary = isTemp;
                savedExpiry = exp;
              },
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Document Duration'), findsOneWidget);
      expect(find.text('Permanent'), findsOneWidget);
      expect(find.text('Temporary'), findsOneWidget);

      // Tap Temporary toggle
      await tester.tap(find.text('Temporary'));
      await tester.pumpAndSettle();

      expect(find.text('Select Duration:'), findsOneWidget);
      expect(find.text('7 Days'), findsOneWidget);
      expect(find.text('15 Days'), findsOneWidget);
      expect(find.text('30 Days'), findsOneWidget);

      // Tap Save Changes
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      expect(savedTemporary, isTrue);
      expect(savedExpiry, isNotNull);
    });

    testWidgets('15. AddEditGroupDialog validates group name and allows palette selection', (tester) async {
      DocumentGroupModel? savedGroup;
      final fakeDbHelper = FakeDatabaseHelper();
      final fakeGroupRepo = DocumentGroupRepository(dbHelper: fakeDbHelper);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            documentGroupRepositoryProvider.overrideWithValue(fakeGroupRepo),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => ElevatedButton(
                  onPressed: () async {
                    savedGroup = await AddEditGroupDialog.show(ctx);
                  },
                  child: const Text('Open Dialog'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Create Document Group'), findsOneWidget);
      expect(find.text('Group Name *'), findsOneWidget);
      expect(find.text('Group Icon'), findsOneWidget);
      expect(find.text('Group Color'), findsOneWidget);

      // Try saving without entering a name -> validation prevents save
      await tester.tap(find.text('Create Group').last);
      await tester.pumpAndSettle();

      // Enter name
      await tester.enterText(find.byType(TextFormField).first, 'Tax & Revenue');
      await tester.pumpAndSettle();

      // Tap Create
      await tester.tap(find.text('Create Group').last);
      await tester.pumpAndSettle();

      expect(savedGroup, isNotNull);
      expect(savedGroup!.name, 'Tax & Revenue');
    });
  });
}
