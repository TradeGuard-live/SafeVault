import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/security/biometric_service.dart';
import '../../../core/security/key_management_service.dart';
import '../../../core/security/pin_service.dart';
import '../../../core/security/two_factor_auth_coordinator.dart';
import '../../../core/security/vault_session.dart';
import '../../../core/storage/encrypted_file_storage.dart';
import '../../categories/data/category_repository.dart';
import '../../categories/domain/category_model.dart';
import '../../documents/data/document_repository.dart';
import '../../documents/domain/document_model.dart';
import '../../passwords/data/password_repository.dart';
import '../../passwords/data/password_security_analyzer.dart';
import '../../passwords/domain/password_category_model.dart';
import '../../passwords/domain/password_entry_model.dart';
import '../../bank_vault/data/bank_vault_repository.dart';
import '../../bank_vault/domain/bank_account_model.dart';
import '../../settings/data/settings_repository.dart';
import '../../settings/domain/vault_settings_model.dart';
import '../../timeline/data/activity_repository.dart';
import '../../timeline/domain/activity_model.dart';

// Core Services
final vaultSessionProvider = ChangeNotifierProvider<VaultSession>((ref) {
  return VaultSession();
});

final twoFactorCoordinatorProvider =
    ChangeNotifierProvider<TwoFactorAuthCoordinator>((ref) {
      return TwoFactorAuthCoordinator();
    });

final keyManagementServiceProvider = Provider<KeyManagementService>((ref) {
  return KeyManagementService();
});

final biometricServiceProvider = Provider<BiometricService>((ref) {
  return BiometricService();
});

final pinServiceProvider = Provider<PinService>((ref) {
  return PinService();
});

final storageServiceProvider = Provider<EncryptedFileStorage>((ref) {
  return EncryptedFileStorage();
});

final categoryRepositoryProvider = Provider<CategoryRepository>((ref) {
  return CategoryRepository();
});

final activityRepositoryProvider = Provider<ActivityRepository>((ref) {
  return ActivityRepository();
});

final documentRepositoryProvider = Provider<DocumentRepository>((ref) {
  return DocumentRepository();
});

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository();
});

// App Settings State Notifier
class SettingsNotifier extends StateNotifier<VaultSettingsModel> {
  final SettingsRepository _repo;

  SettingsNotifier(this._repo) : super(const VaultSettingsModel()) {
    loadSettings();
  }

  Future<void> loadSettings() async {
    final s = await _repo.getSettings();
    state = s;
  }

  Future<void> setThemeMode(String mode) async {
    await _repo.setThemeMode(mode);
    state = state.copyWith(themeMode: mode);
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    await _repo.setBiometricEnabled(enabled);
    state = state.copyWith(biometricEnabled: enabled);
  }

  Future<void> setAutoLockDuration(int seconds) async {
    await _repo.setAutoLockDuration(seconds);
    state = state.copyWith(autoLockDuration: seconds);
  }

  Future<void> setScreenshotProtection(bool enabled) async {
    await _repo.setScreenshotProtection(enabled);
    state = state.copyWith(screenshotProtection: enabled);
  }

  Future<void> setNotificationsEnabled(bool enabled) async {
    await _repo.setNotificationsEnabled(enabled);
    state = state.copyWith(notificationsEnabled: enabled);
  }

  Future<void> setTrashRetentionDays(int days) async {
    await _repo.setTrashRetentionDays(days);
    state = state.copyWith(trashRetentionDays: days);
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, VaultSettingsModel>((ref) {
      final repo = ref.watch(settingsRepositoryProvider);
      return SettingsNotifier(repo);
    });

// Categories Provider
final categoriesProvider = FutureProvider<List<CategoryModel>>((ref) async {
  final repo = ref.watch(categoryRepositoryProvider);
  return await repo.getAllCategories();
});

// Active Documents Provider
final activeDocumentsProvider = FutureProvider<List<DocumentModel>>((
  ref,
) async {
  final session = ref.watch(vaultSessionProvider);
  if (!session.isUnlocked || session.masterKey == null) {
    return [];
  }
  final repo = ref.watch(documentRepositoryProvider);
  return await repo.getAllActiveDocuments(session.masterKey!);
});

// Favorite Documents Provider
final favoriteDocumentsProvider = FutureProvider<List<DocumentModel>>((
  ref,
) async {
  final session = ref.watch(vaultSessionProvider);
  if (!session.isUnlocked || session.masterKey == null) {
    return [];
  }
  final repo = ref.watch(documentRepositoryProvider);
  return await repo.getFavoriteDocuments(session.masterKey!);
});

// Trash Documents Provider
final trashDocumentsProvider = FutureProvider<List<DocumentModel>>((ref) async {
  final session = ref.watch(vaultSessionProvider);
  if (!session.isUnlocked || session.masterKey == null) {
    return [];
  }
  final repo = ref.watch(documentRepositoryProvider);
  return await repo.getTrashDocuments(session.masterKey!);
});

// Expiring Documents Provider (within 30 days)
final expiringDocumentsProvider = FutureProvider<List<DocumentModel>>((
  ref,
) async {
  final session = ref.watch(vaultSessionProvider);
  if (!session.isUnlocked || session.masterKey == null) {
    return [];
  }
  final repo = ref.watch(documentRepositoryProvider);
  return await repo.getExpiringDocuments(
    days: 30,
    masterKey: session.masterKey!,
  );
});

// Activities Provider
final activitiesProvider = FutureProvider<List<ActivityModel>>((ref) async {
  final repo = ref.watch(activityRepositoryProvider);
  return await repo.getActivities();
});

// Password Manager Providers
final passwordRepositoryProvider = Provider<PasswordRepository>((ref) {
  return PasswordRepository();
});

final passwordCategoriesProvider = FutureProvider<List<PasswordCategoryModel>>((
  ref,
) async {
  final repo = ref.watch(passwordRepositoryProvider);
  return await repo.getAllCategories();
});

final allPasswordsProvider = FutureProvider<List<PasswordEntryModel>>((
  ref,
) async {
  final session = ref.watch(vaultSessionProvider);
  if (!session.isUnlocked || session.masterKey == null) {
    return [];
  }
  final repo = ref.watch(passwordRepositoryProvider);
  return await repo.getAllEntries(session.masterKey!);
});

final favoritePasswordsProvider = FutureProvider<List<PasswordEntryModel>>((
  ref,
) async {
  final session = ref.watch(vaultSessionProvider);
  if (!session.isUnlocked || session.masterKey == null) {
    return [];
  }
  final repo = ref.watch(passwordRepositoryProvider);
  return await repo.getFavoriteEntries(session.masterKey!);
});

final passwordSecurityAuditProvider = FutureProvider<PasswordAuditResult>((
  ref,
) async {
  final passwords = await ref.watch(allPasswordsProvider.future);
  return PasswordSecurityAnalyzer.analyze(passwords);
});

// Bank Vault Providers
final bankVaultRepositoryProvider = Provider<BankVaultRepository>((ref) {
  return BankVaultRepository();
});

final allBankAccountsProvider = FutureProvider<List<BankAccountModel>>((
  ref,
) async {
  final session = ref.watch(vaultSessionProvider);
  if (!session.isUnlocked || session.masterKey == null) {
    return [];
  }
  final repo = ref.watch(bankVaultRepositoryProvider);
  return await repo.getAllAccounts(session.masterKey!);
});

final favoriteBankAccountsProvider = FutureProvider<List<BankAccountModel>>((
  ref,
) async {
  final session = ref.watch(vaultSessionProvider);
  if (!session.isUnlocked || session.masterKey == null) {
    return [];
  }
  final repo = ref.watch(bankVaultRepositoryProvider);
  return await repo.getFavoriteAccounts(session.masterKey!);
});
