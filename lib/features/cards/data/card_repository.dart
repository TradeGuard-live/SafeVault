import 'package:cryptography/cryptography.dart';
import 'package:sqflite/sqflite.dart';

import '../../../core/database/vault_database.dart';
import '../../../core/errors/exceptions.dart';
import '../../../core/notifications/local_notification_service.dart';
import '../../../core/security/encryption_service.dart';
import '../domain/payment_card_model.dart';

class CardRepository {
  final VaultDatabase _db;
  final EncryptionService _encryptionService;
  final LocalNotificationService _notificationService;

  CardRepository({
    VaultDatabase? db,
    EncryptionService? encryptionService,
    LocalNotificationService? notificationService,
  }) : _db = db ?? VaultDatabase.instance,
       _encryptionService = encryptionService ?? EncryptionService(),
       _notificationService =
           notificationService ?? LocalNotificationService.instance;

  int _notificationIdFor(String cardId) =>
      (cardId.hashCode.abs() % 100000) + 700000;

  /// Loads all payment cards decrypted.
  Future<List<PaymentCardModel>> getCards(SecretKey masterKey) async {
    try {
      final db = await _db.database;
      final rows = await db.query(
        'payment_cards',
        orderBy:
            'bank_name COLLATE NOCASE ASC, card_nickname COLLATE NOCASE ASC',
      );

      final List<PaymentCardModel> list = [];
      for (final row in rows) {
        final card = PaymentCardModel.fromMap(row);
        final decrypted = await card.decrypt(
          masterKey: masterKey,
          encryptionService: _encryptionService,
        );
        list.add(decrypted);
      }
      return list;
    } catch (e) {
      throw DatabaseOperationException('Failed to load payment cards.', e);
    }
  }

  /// Loads favorite payment cards decrypted.
  Future<List<PaymentCardModel>> getFavoriteCards(SecretKey masterKey) async {
    try {
      final db = await _db.database;
      final rows = await db.query(
        'payment_cards',
        where: 'is_favorite = 1',
        orderBy:
            'bank_name COLLATE NOCASE ASC, card_nickname COLLATE NOCASE ASC',
      );

      final List<PaymentCardModel> list = [];
      for (final row in rows) {
        final card = PaymentCardModel.fromMap(row);
        final decrypted = await card.decrypt(
          masterKey: masterKey,
          encryptionService: _encryptionService,
        );
        list.add(decrypted);
      }
      return list;
    } catch (e) {
      throw DatabaseOperationException('Failed to load favorite cards.', e);
    }
  }

  /// Loads cards expiring within [withinDays] (default 60 days).
  Future<List<PaymentCardModel>> getExpiringCards(
    SecretKey masterKey, {
    int withinDays = 60,
  }) async {
    try {
      final all = await getCards(masterKey);
      return all.where((c) => c.isExpiringSoon(days: withinDays)).toList();
    } catch (e) {
      throw DatabaseOperationException('Failed to load expiring cards.', e);
    }
  }

  /// Loads a single payment card by ID decrypted.
  Future<PaymentCardModel?> getCardById(String id, SecretKey masterKey) async {
    try {
      final db = await _db.database;
      final rows = await db.query(
        'payment_cards',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (rows.isEmpty) return null;
      final card = PaymentCardModel.fromMap(rows.first);
      return await card.decrypt(
        masterKey: masterKey,
        encryptionService: _encryptionService,
      );
    } catch (e) {
      throw DatabaseOperationException('Failed to load payment card.', e);
    }
  }

  /// Inserts a new payment card and schedules an expiry reminder if future-dated.
  Future<void> createCard(PaymentCardModel card) async {
    try {
      final db = await _db.database;
      await db.transaction((txn) async {
        await txn.insert(
          'payment_cards',
          card.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });

      await _scheduleReminderForCard(card);
    } catch (e) {
      throw DatabaseOperationException('Failed to save payment card.', e);
    }
  }

  /// Updates an existing payment card and recalculates its expiry reminder.
  Future<void> updateCard(PaymentCardModel card) async {
    try {
      final db = await _db.database;
      await db.transaction((txn) async {
        await txn.update(
          'payment_cards',
          card.toMap(),
          where: 'id = ?',
          whereArgs: [card.id],
        );
      });

      await _scheduleReminderForCard(card);
    } catch (e) {
      throw DatabaseOperationException('Failed to update payment card.', e);
    }
  }

  /// Deletes a payment card and cancels any scheduled expiry notification.
  Future<void> deleteCard(String id) async {
    try {
      final db = await _db.database;
      await db.transaction((txn) async {
        await txn.delete('payment_cards', where: 'id = ?', whereArgs: [id]);
      });

      try {
        await _notificationService.cancelNotification(_notificationIdFor(id));
      } catch (_) {}
    } catch (e) {
      throw DatabaseOperationException('Failed to delete payment card.', e);
    }
  }

  /// Toggles favorite status for a card.
  Future<void> toggleFavorite(String id, bool isFavorite) async {
    try {
      final db = await _db.database;
      await db.update(
        'payment_cards',
        {
          'is_favorite': isFavorite ? 1 : 0,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      throw DatabaseOperationException('Failed to toggle card favorite.', e);
    }
  }

  /// Searches and filters payment cards without unnecessary full table scans.
  Future<List<PaymentCardModel>> searchCards(
    String query,
    SecretKey masterKey, {
    CardType? type,
    CardNetwork? network,
    bool? favoriteOnly,
    bool? expiredOnly,
  }) async {
    try {
      final cleanQuery = query.trim();
      final whereClauses = <String>[];
      final whereArgs = <dynamic>[];

      if (type != null) {
        whereClauses.add('card_type = ?');
        whereArgs.add(type.name);
      }

      if (network != null) {
        whereClauses.add('network = ?');
        whereArgs.add(network.name);
      }

      if (favoriteOnly == true) {
        whereClauses.add('is_favorite = 1');
      }

      final db = await _db.database;
      final rows = await db.query(
        'payment_cards',
        where: whereClauses.isNotEmpty ? whereClauses.join(' AND ') : null,
        whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
        orderBy: 'bank_name COLLATE NOCASE ASC',
      );

      final List<PaymentCardModel> results = [];
      for (final row in rows) {
        final card = PaymentCardModel.fromMap(row);

        // Fast metadata check on plaintext indexed fields
        final matchesQuery =
            cleanQuery.isEmpty ||
            card.bankName.toLowerCase().contains(cleanQuery.toLowerCase()) ||
            card.cardNickname.toLowerCase().contains(
              cleanQuery.toLowerCase(),
            ) ||
            card.lastFourDigits.contains(cleanQuery);

        if (matchesQuery) {
          final decrypted = await card.decrypt(
            masterKey: masterKey,
            encryptionService: _encryptionService,
          );

          if (expiredOnly != null) {
            if (expiredOnly && !decrypted.isExpired()) continue;
            if (!expiredOnly && decrypted.isExpired()) continue;
          }

          results.add(decrypted);
        } else {
          // If query didn't match metadata, decrypt to see if cardholder matches
          final decrypted = await card.decrypt(
            masterKey: masterKey,
            encryptionService: _encryptionService,
          );
          final holder = decrypted.decryptedCardholderName?.toLowerCase() ?? '';
          if (holder.contains(cleanQuery.toLowerCase())) {
            if (expiredOnly != null) {
              if (expiredOnly && !decrypted.isExpired()) continue;
              if (!expiredOnly && decrypted.isExpired()) continue;
            }
            results.add(decrypted);
          }
        }
      }

      return results;
    } catch (e) {
      throw DatabaseOperationException('Failed to search payment cards.', e);
    }
  }

  Future<void> _scheduleReminderForCard(PaymentCardModel card) async {
    try {
      final notifId = _notificationIdFor(card.id);
      await _notificationService.cancelNotification(notifId);

      final now = DateTime.now();
      final lastDayOfMonth = DateTime(
        card.expiryYear,
        card.expiryMonth + 1,
        0,
        9,
        0,
        0,
      );

      if (lastDayOfMonth.isBefore(now)) {
        return; // Already expired, no future reminder to schedule
      }

      // Schedule reminder 30 days before expiration
      final reminderDate = lastDayOfMonth.subtract(const Duration(days: 30));
      final scheduledDate = reminderDate.isBefore(now)
          ? now.add(const Duration(days: 1))
          : reminderDate;

      final daysBefore = lastDayOfMonth.difference(scheduledDate).inDays;

      await _notificationService.scheduleCardExpiryReminder(
        notificationId: notifId,
        bankName: card.bankName,
        cardType: card.cardType.name,
        scheduledDate: scheduledDate,
        daysBefore: daysBefore,
      );
    } catch (_) {
      // Offline notification scheduling failures should not prevent card saving
    }
  }
}
