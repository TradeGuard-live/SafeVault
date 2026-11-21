import '../../../core/database/vault_database.dart';
import '../domain/vault_settings_model.dart';

class SettingsRepository {
  final VaultDatabase _dbHelper;

  SettingsRepository({VaultDatabase? dbHelper})
    : _dbHelper = dbHelper ?? VaultDatabase.instance;

  Future<VaultSettingsModel> getSettings() async {
    final db = await _dbHelper.database;
    final rows = await db.query('settings', where: 'id = 1');
    if (rows.isEmpty) {
      return const VaultSettingsModel();
    }
    return VaultSettingsModel.fromMap(rows.first);
  }

  Future<void> updateSettings(VaultSettingsModel settings) async {
    final db = await _dbHelper.database;
    await db.update('settings', settings.toMap(), where: 'id = 1');
  }

  Future<void> setThemeMode(String themeMode) async {
    final db = await _dbHelper.database;
    await db.update('settings', {'theme_mode': themeMode}, where: 'id = 1');
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    final db = await _dbHelper.database;
    await db.update('settings', {
      'biometric_enabled': enabled ? 1 : 0,
    }, where: 'id = 1');
  }

  Future<void> setAutoLockDuration(int seconds) async {
    final db = await _dbHelper.database;
    await db.update('settings', {
      'auto_lock_duration': seconds,
    }, where: 'id = 1');
  }

  Future<void> setScreenshotProtection(bool enabled) async {
    final db = await _dbHelper.database;
    await db.update('settings', {
      'screenshot_protection': enabled ? 1 : 0,
    }, where: 'id = 1');
  }

  Future<void> setNotificationsEnabled(bool enabled) async {
    final db = await _dbHelper.database;
    await db.update('settings', {
      'notifications_enabled': enabled ? 1 : 0,
    }, where: 'id = 1');
  }

  Future<void> setTrashRetentionDays(int days) async {
    final db = await _dbHelper.database;
    await db.update('settings', {
      'trash_retention_days': days,
    }, where: 'id = 1');
  }
}
