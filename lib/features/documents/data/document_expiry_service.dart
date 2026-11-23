import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../authentication/presentation/auth_providers.dart';
import '../../settings/data/settings_repository.dart';
import 'document_repository.dart';

final documentExpiryServiceProvider = Provider<DocumentExpiryService>((ref) {
  final docRepo = ref.watch(documentRepositoryProvider);
  final settingsRepo = ref.watch(settingsRepositoryProvider);
  return DocumentExpiryService(
    documentRepository: docRepo,
    settingsRepository: settingsRepo,
    ref: ref,
  );
});

class DocumentExpiryService {
  final DocumentRepository documentRepository;
  final SettingsRepository settingsRepository;
  final Ref? ref;

  bool _isProcessing = false;
  Timer? _periodicCheckTimer;

  DocumentExpiryService({
    required this.documentRepository,
    required this.settingsRepository,
    this.ref,
  });

  /// Starts the periodic expiry monitor (runs every 30 minutes while app is active).
  void startMonitoring() {
    _periodicCheckTimer?.cancel();
    _periodicCheckTimer = Timer.periodic(
      const Duration(minutes: 30),
      (_) => runExpiryCheck(),
    );
  }

  /// Stops periodic monitoring.
  void stopMonitoring() {
    _periodicCheckTimer?.cancel();
    _periodicCheckTimer = null;
  }

  /// Executes an idempotent check for expired temporary documents and trash cleanup.
  Future<int> runExpiryCheck() async {
    if (_isProcessing) return 0;
    _isProcessing = true;

    try {
      // 1. Process expired temporary documents (moves to Trash safely)
      final expiredCount = await documentRepository.processExpiredDocuments();

      // 2. Perform auto-cleanup of expired trash items according to retention policy
      final settings = await settingsRepository.getSettings();
      await documentRepository.autoCleanupTrash(settings.trashRetentionDays);

      if (expiredCount > 0) {
        debugPrint(
          'DocumentExpiryService: Processed $expiredCount expired temporary document(s).',
        );
        // Invalidate providers to immediately refresh UI
        final r = ref;
        if (r != null) {
          r.invalidate(activeDocumentsProvider);
          r.invalidate(temporaryDocumentsProvider);
          r.invalidate(expiringSoonTemporaryDocumentsProvider);
          r.invalidate(trashDocumentsProvider);
          r.invalidate(expiringDocumentsProvider);
        }
      }

      return expiredCount;
    } catch (e) {
      debugPrint('DocumentExpiryService error: $e');
      return 0;
    } finally {
      _isProcessing = false;
    }
  }
}
