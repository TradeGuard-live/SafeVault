class VaultSettingsModel {
  final String themeMode; // 'system', 'dark', 'light'
  final bool biometricEnabled;
  final int autoLockDuration; // 0 = immediate, 30, 60, 300 seconds
  final bool screenshotProtection;
  final bool notificationsEnabled;
  final int trashRetentionDays;

  const VaultSettingsModel({
    this.themeMode = 'system',
    this.biometricEnabled = false,
    this.autoLockDuration = 0,
    this.screenshotProtection = true,
    this.notificationsEnabled = true,
    this.trashRetentionDays = 30,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': 1,
      'theme_mode': themeMode,
      'biometric_enabled': biometricEnabled ? 1 : 0,
      'auto_lock_duration': autoLockDuration,
      'screenshot_protection': screenshotProtection ? 1 : 0,
      'notifications_enabled': notificationsEnabled ? 1 : 0,
      'trash_retention_days': trashRetentionDays,
    };
  }

  factory VaultSettingsModel.fromMap(Map<String, dynamic> map) {
    return VaultSettingsModel(
      themeMode: map['theme_mode'] as String? ?? 'system',
      biometricEnabled: (map['biometric_enabled'] as int? ?? 0) == 1,
      autoLockDuration: map['auto_lock_duration'] as int? ?? 0,
      screenshotProtection: (map['screenshot_protection'] as int? ?? 1) == 1,
      notificationsEnabled: (map['notifications_enabled'] as int? ?? 1) == 1,
      trashRetentionDays: map['trash_retention_days'] as int? ?? 30,
    );
  }

  VaultSettingsModel copyWith({
    String? themeMode,
    bool? biometricEnabled,
    int? autoLockDuration,
    bool? screenshotProtection,
    bool? notificationsEnabled,
    int? trashRetentionDays,
  }) {
    return VaultSettingsModel(
      themeMode: themeMode ?? this.themeMode,
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      autoLockDuration: autoLockDuration ?? this.autoLockDuration,
      screenshotProtection: screenshotProtection ?? this.screenshotProtection,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      trashRetentionDays: trashRetentionDays ?? this.trashRetentionDays,
    );
  }
}

