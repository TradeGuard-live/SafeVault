import 'package:uuid/uuid.dart';

import '../../../core/database/vault_database.dart';
import '../domain/activity_model.dart';

class ActivityRepository {
  final VaultDatabase _dbHelper;
  final Uuid _uuid = const Uuid();

  ActivityRepository({VaultDatabase? dbHelper})
    : _dbHelper = dbHelper ?? VaultDatabase.instance;

  Future<void> logActivity({
    String? documentId,
    required String documentName,
    required String activityType,
    String? details,
  }) async {
    try {
      final db = await _dbHelper.database;
      final activity = ActivityModel(
        id: _uuid.v4(),
        documentId: documentId,
        documentName: documentName,
        activityType: activityType,
        details: details,
        timestamp: DateTime.now(),
      );
      await db.insert('activities', activity.toMap());
    } catch (_) {
      // Non-critical logging failure should not abort main document operation
    }
  }

  Future<List<ActivityModel>> getActivities({
    String? documentId,
    String? activityType,
    int limit = 100,
  }) async {
    final db = await _dbHelper.database;
    String whereClause = '';
    List<dynamic> whereArgs = [];

    if (documentId != null) {
      whereClause = 'document_id = ?';
      whereArgs.add(documentId);
    }
    if (activityType != null) {
      if (whereClause.isNotEmpty) whereClause += ' AND ';
      whereClause += 'activity_type = ?';
      whereArgs.add(activityType);
    }

    final rows = await db.query(
      'activities',
      where: whereClause.isEmpty ? null : whereClause,
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'timestamp DESC',
      limit: limit,
    );

    return rows.map((r) => ActivityModel.fromMap(r)).toList();
  }

  Future<void> clearAllActivities() async {
    final db = await _dbHelper.database;
    await db.delete('activities');
  }
}
