import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:vault/core/database/vault_database.dart';
import 'package:vault/core/notifications/local_notification_service.dart';
import 'package:vault/core/security/encryption_service.dart';
import 'package:vault/features/cards/data/card_repository.dart';
import 'package:vault/features/cards/domain/payment_card_model.dart';
import 'package:vault/features/cards/presentation/add_edit_card_screen.dart';
import 'package:vault/features/cards/presentation/card_details_screen.dart';
import 'package:vault/features/cards/presentation/widgets/payment_card_widget.dart';

// --- IN-MEMORY TEST DATABASE FOR REPOSITORY TESTS ---
class InMemoryTestDatabase implements Database {
  final List<Map<String, dynamic>> _cardRows = [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Database get database => this;

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    final copy = Map<String, dynamic>.from(values);
    _cardRows.removeWhere((r) => r['id'] == copy['id']);
    _cardRows.add(copy);
    return 1;
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
    var result = List<Map<String, dynamic>>.from(_cardRows);

    if (where != null && where.isNotEmpty) {
      if (where.contains('id = ?') &&
          whereArgs != null &&
          whereArgs.isNotEmpty) {
        final targetId = whereArgs.first as String;
        result = result.where((r) => r['id'] == targetId).toList();
      } else if (where.contains('is_favorite = 1')) {
        result = result.where((r) => r['is_favorite'] == 1).toList();
      } else if (where.contains('card_type = ?') && whereArgs != null) {
        final targetType = whereArgs.first as String;
        result = result.where((r) => r['card_type'] == targetType).toList();
      }
    }

    if (orderBy != null && orderBy.contains('bank_name')) {
      result.sort(
        (a, b) => (a['bank_name'] as String).toLowerCase().compareTo(
          (b['bank_name'] as String).toLowerCase(),
        ),
      );
    }

    return result.map((r) => Map<String, Object?>.from(r)).toList();
  }

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    int updatedCount = 0;
    if (where != null && where.contains('id = ?') && whereArgs != null) {
      final targetId = whereArgs.first as String;
      for (int i = 0; i < _cardRows.length; i++) {
        if (_cardRows[i]['id'] == targetId) {
          _cardRows[i].addAll(values);
          updatedCount++;
        }
      }
    }
    return updatedCount;
  }

  @override
  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    int count = 0;
    if (where != null && where.contains('id = ?') && whereArgs != null) {
      final targetId = whereArgs.first as String;
      final before = _cardRows.length;
      _cardRows.removeWhere((r) => r['id'] == targetId);
      count = before - _cardRows.length;
    }
    return count;
  }

  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction txn) action, {
    bool? exclusive,
  }) async {
    final fakeTxn = FakeTransaction(this);
    return await action(fakeTxn);
  }
}

class FakeTransaction implements Transaction {
  final InMemoryTestDatabase _db;
  FakeTransaction(this._db);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Database get database => _db;

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) => _db.insert(
    table,
    values,
    nullColumnHack: nullColumnHack,
    conflictAlgorithm: conflictAlgorithm,
  );

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) => _db.update(
    table,
    values,
    where: where,
    whereArgs: whereArgs,
    conflictAlgorithm: conflictAlgorithm,
  );

  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) =>
      _db.delete(table, where: where, whereArgs: whereArgs);

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
  }) => _db.query(
    table,
    distinct: distinct,
    columns: columns,
    where: where,
    whereArgs: whereArgs,
    groupBy: groupBy,
    having: having,
    orderBy: orderBy,
    limit: limit,
    offset: offset,
  );
}

class FakeVaultDatabase implements VaultDatabase {
  final InMemoryTestDatabase _testDb;
  FakeVaultDatabase(this._testDb);

  @override
  Future<Database> get database async => _testDb;

  @override
  Future<void> close() async {}
  @override
  Future<void> deleteDatabaseFile() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late EncryptionService encService;
  late InMemoryTestDatabase inMemoryDb;
  late FakeVaultDatabase fakeVaultDb;
  late CardRepository cardRepo;

  setUp(() {
    encService = EncryptionService();
    inMemoryDb = InMemoryTestDatabase();
    fakeVaultDb = FakeVaultDatabase(inMemoryDb);
    cardRepo = CardRepository(
      db: fakeVaultDb,
      encryptionService: encService,
      notificationService: LocalNotificationService.instance,
    );
  });

  group('PART 1: PaymentCardModel Tests', () {
    test('1. Valid card creation and getters', () {
      final now = DateTime.now();
      final card = PaymentCardModel(
        id: 'test-card-1',
        cardNickname: 'Rewards Platinum',
        bankName: 'HDFC Bank',
        cardType: CardType.credit,
        network: CardNetwork.visa,
        lastFourDigits: '4321',
        expiryMonth: 12,
        expiryYear: 2029,
        cardColor: 1,
        isFavorite: true,
        createdAt: now,
        updatedAt: now,
      );

      expect(card.id, equals('test-card-1'));
      expect(card.cardNickname, equals('Rewards Platinum'));
      expect(card.bankName, equals('HDFC Bank'));
      expect(card.cardType, equals(CardType.credit));
      expect(card.network, equals(CardNetwork.visa));
      expect(card.lastFourDigits, equals('4321'));
      expect(card.formattedExpiry, equals('12/29'));
      expect(card.maskedCardNumber, equals('•••• •••• •••• 4321'));
      expect(card.isExpired(DateTime(2028, 1, 1)), isFalse);
      expect(card.isExpired(DateTime(2030, 1, 1)), isTrue);
    });

    test('2. CardType enum fallback and short labels', () {
      expect(CardType.fromString('credit'), equals(CardType.credit));
      expect(CardType.fromString('debit'), equals(CardType.debit));
      expect(CardType.fromString('CREDIT'), equals(CardType.credit));
      expect(CardType.fromString('unknown_type'), equals(CardType.debit));

      expect(CardType.credit.shortLabel, equals('CREDIT'));
      expect(CardType.debit.shortLabel, equals('DEBIT'));
    });

    test('3. CardNetwork enum fallback and display names', () {
      expect(CardNetwork.fromString('visa'), equals(CardNetwork.visa));
      expect(
        CardNetwork.fromString('mastercard'),
        equals(CardNetwork.mastercard),
      );
      expect(CardNetwork.fromString('rupay'), equals(CardNetwork.rupay));
      expect(CardNetwork.fromString('amex'), equals(CardNetwork.amex));
      expect(
        CardNetwork.fromString('other_network'),
        equals(CardNetwork.other),
      );

      expect(CardNetwork.visa.displayName, equals('Visa'));
      expect(CardNetwork.rupay.displayName, equals('RuPay'));
      expect(CardNetwork.amex.displayName, equals('American Express'));
    });

    test('4. CardVisualPreset validation and fallback', () {
      expect(CardVisualPreset.presets.length, equals(6));
      final defaultPreset = CardVisualPreset.getPreset(0);
      expect(defaultPreset.name, contains('Titanium'));

      // Out of bounds preset fallback
      expect(CardVisualPreset.getPreset(99).id, equals(0));
      expect(CardVisualPreset.getPreset(-1).id, equals(0));
    });

    test('5. Map serialization and deserialization', () {
      final now = DateTime(2026, 11, 21, 12, 0, 0);
      final original = PaymentCardModel(
        id: 'ser-1',
        cardNickname: 'Salary Debit',
        bankName: 'SBI',
        cardType: CardType.debit,
        network: CardNetwork.rupay,
        lastFourDigits: '9876',
        expiryMonth: 5,
        expiryYear: 2028,
        cardColor: 2,
        isFavorite: false,
        createdAt: now,
        updatedAt: now,
      );

      final map = original.toMap();
      expect(map['id'], equals('ser-1'));
      expect(map['bank_name'], equals('SBI'));
      expect(map['card_type'], equals('debit'));
      expect(map['network'], equals('rupay'));
      expect(map['last_four_digits'], equals('9876'));

      final restored = PaymentCardModel.fromMap(map);
      expect(restored.id, equals(original.id));
      expect(restored.bankName, equals(original.bankName));
      expect(restored.cardNickname, equals(original.cardNickname));
      expect(restored.cardType, equals(original.cardType));
      expect(restored.network, equals(original.network));
      expect(restored.lastFourDigits, equals('9876'));
      expect(restored.formattedExpiry, equals('05/28'));
    });

    test('6. Expired card detection and days remaining calculation', () {
      final now = DateTime(2026, 6, 15);
      final activeCard = PaymentCardModel(
        id: 'active-1',
        cardNickname: 'Active Card',
        bankName: 'ICICI',
        cardType: CardType.credit,
        network: CardNetwork.mastercard,
        lastFourDigits: '1111',
        expiryMonth: 12,
        expiryYear: 2026,
        createdAt: now,
        updatedAt: now,
      );

      expect(activeCard.isExpired(now), isFalse);
      expect(activeCard.daysRemaining(now), greaterThan(0));

      final expiredCard = PaymentCardModel(
        id: 'expired-1',
        cardNickname: 'Old Card',
        bankName: 'Axis Bank',
        cardType: CardType.debit,
        network: CardNetwork.visa,
        lastFourDigits: '2222',
        expiryMonth: 5,
        expiryYear: 2026,
        createdAt: now,
        updatedAt: now,
      );

      expect(expiredCard.isExpired(now), isTrue);
      expect(expiredCard.daysRemaining(now), lessThan(0));
    });
  });

  group('PART 2: Encryption & Security Tests', () {
    test('7. Sensitive cardholder name and notes are encrypted with AES-256-GCM + AAD', () async {
      final masterKey = await encService.generateRandomMasterKey();

      final encryptedCard = await PaymentCardModel.createEncrypted(
        id: 'sec-card-1',
        cardNickname: 'Confidential Card',
        cardholderName: 'Alice Secret Cardholder',
        bankName: 'Bank of Baroda',
        cardType: CardType.credit,
        network: CardNetwork.visa,
        lastFourDigits: '5544',
        expiryMonth: 8,
        expiryYear: 2030,
        notes: 'Secret limit is 500k rupees',
        masterKey: masterKey,
        encryptionService: encService,
      );

      // Ciphertext fields must NOT contain raw plaintext
      expect(encryptedCard.cardholderNameEnc, isNotNull);
      expect(encryptedCard.cardholderNameEnc, isNot(contains('Alice')));
      expect(encryptedCard.notesEnc, isNotNull);
      expect(encryptedCard.notesEnc, isNot(contains('Secret limit')));

      // Decryption roundtrip
      final decrypted = await encryptedCard.decrypt(
        masterKey: masterKey,
        encryptionService: encService,
      );

      expect(
        decrypted.decryptedCardholderName,
        equals('Alice Secret Cardholder'),
      );
      expect(decrypted.decryptedNotes, equals('Secret limit is 500k rupees'));
    });

    test('8. Decryption fails safely when wrong key is provided', () async {
      final keyA = await encService.generateRandomMasterKey();
      final keyB = await encService.generateRandomMasterKey();

      final card = await PaymentCardModel.createEncrypted(
        id: 'wrong-key-card',
        cardNickname: 'Locked Card',
        cardholderName: 'Bob Vance',
        bankName: 'Canara Bank',
        cardType: CardType.debit,
        network: CardNetwork.rupay,
        lastFourDigits: '3333',
        expiryMonth: 10,
        expiryYear: 2027,
        masterKey: keyA,
        encryptionService: encService,
      );

      final decryptedWithWrongKey = await card.decrypt(
        masterKey: keyB,
        encryptionService: encService,
      );

      // Safe failure: Decrypted value becomes null rather than crashing
      expect(decryptedWithWrongKey.decryptedCardholderName, isNull);
    });

    test(
      '9. Strict Financial Constraint: ZERO CVV, ATM PIN, UPI PIN, OTP fields',
      () {
        final map = PaymentCardModel(
          id: 'test',
          cardNickname: 'Nick',
          bankName: 'Bank',
          cardType: CardType.debit,
          network: CardNetwork.visa,
          lastFourDigits: '1234',
          expiryMonth: 1,
          expiryYear: 2030,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ).toMap();

        expect(map.containsKey('cvv'), isFalse);
        expect(map.containsKey('cvc'), isFalse);
        expect(map.containsKey('atm_pin'), isFalse);
        expect(map.containsKey('upi_pin'), isFalse);
        expect(map.containsKey('pin'), isFalse);
        expect(map.containsKey('otp'), isFalse);
        expect(map.containsKey('pan'), isFalse);
        expect(map.containsKey('card_number'), isFalse);
      },
    );

    test(
      '10. toString() redacts sensitive cardholder details and notes',
      () async {
        final masterKey = await encService.generateRandomMasterKey();
        final card = await PaymentCardModel.createEncrypted(
          id: 'redact-card',
          cardNickname: 'Redacted Card',
          cardholderName: 'Super Secret Name',
          bankName: 'Punjab National Bank',
          cardType: CardType.credit,
          network: CardNetwork.amex,
          lastFourDigits: '7890',
          expiryMonth: 11,
          expiryYear: 2028,
          notes: 'Top secret private notes',
          masterKey: masterKey,
          encryptionService: encService,
        );

        final str = card.toString();
        expect(str, contains('Redacted Card'));
        expect(str, contains('Punjab National Bank'));
        expect(str, contains('7890'));
        expect(str, isNot(contains('Super Secret Name')));
        expect(str, isNot(contains('Top secret private notes')));
      },
    );
  });

  group('PART 3: Repository & CRUD Operations Tests', () {
    test('11. Create, Read, Update, and Delete card in repository', () async {
      final masterKey = await encService.generateRandomMasterKey();

      final newCard = await PaymentCardModel.createEncrypted(
        id: 'crud-1',
        cardNickname: 'Shopping Card',
        cardholderName: 'Charlie Brown',
        bankName: 'Kotak Bank',
        cardType: CardType.credit,
        network: CardNetwork.visa,
        lastFourDigits: '1001',
        expiryMonth: 4,
        expiryYear: 2029,
        notes: '5% cashback on groceries',
        masterKey: masterKey,
        encryptionService: encService,
      );

      // 1. Create
      await cardRepo.createCard(newCard);

      // 2. Read by ID
      final fetched = await cardRepo.getCardById('crud-1', masterKey);
      expect(fetched, isNotNull);
      expect(fetched!.bankName, equals('Kotak Bank'));
      expect(fetched.decryptedCardholderName, equals('Charlie Brown'));
      expect(fetched.decryptedNotes, equals('5% cashback on groceries'));

      // 3. Update
      final updated = fetched.copyWith(cardNickname: 'Primary Shopping Card');
      await cardRepo.updateCard(updated);

      final fetchedUpdated = await cardRepo.getCardById('crud-1', masterKey);
      expect(fetchedUpdated!.cardNickname, equals('Primary Shopping Card'));

      // 4. Delete
      await cardRepo.deleteCard('crud-1');
      final fetchedAfterDelete = await cardRepo.getCardById(
        'crud-1',
        masterKey,
      );
      expect(fetchedAfterDelete, isNull);
    });

    test('12. Toggle favorite status in repository', () async {
      final masterKey = await encService.generateRandomMasterKey();

      final card = await PaymentCardModel.createEncrypted(
        id: 'fav-card-1',
        cardNickname: 'Travel Card',
        bankName: 'IndusInd Bank',
        cardType: CardType.credit,
        network: CardNetwork.mastercard,
        lastFourDigits: '2002',
        expiryMonth: 9,
        expiryYear: 2031,
        isFavorite: false,
        masterKey: masterKey,
        encryptionService: encService,
      );

      await cardRepo.createCard(card);

      // Toggle to favorite
      await cardRepo.toggleFavorite('fav-card-1', true);
      final favList = await cardRepo.getFavoriteCards(masterKey);
      expect(favList.length, equals(1));
      expect(favList.first.id, equals('fav-card-1'));

      // Toggle back to not favorite
      await cardRepo.toggleFavorite('fav-card-1', false);
      final emptyFavList = await cardRepo.getFavoriteCards(masterKey);
      expect(emptyFavList.isEmpty, isTrue);
    });

    test('13. Search cards by bank, nickname, holder, and last 4', () async {
      final masterKey = await encService.generateRandomMasterKey();

      final c1 = await PaymentCardModel.createEncrypted(
        id: 's-1',
        cardNickname: 'Airport Lounge Card',
        cardholderName: 'David Miller',
        bankName: 'HDFC Bank',
        cardType: CardType.credit,
        network: CardNetwork.visa,
        lastFourDigits: '8877',
        expiryMonth: 7,
        expiryYear: 2028,
        masterKey: masterKey,
        encryptionService: encService,
      );

      final c2 = await PaymentCardModel.createEncrypted(
        id: 's-2',
        cardNickname: 'Salary Debit Card',
        cardholderName: 'Emma Watson',
        bankName: 'SBI',
        cardType: CardType.debit,
        network: CardNetwork.rupay,
        lastFourDigits: '4455',
        expiryMonth: 3,
        expiryYear: 2027,
        masterKey: masterKey,
        encryptionService: encService,
      );

      await cardRepo.createCard(c1);
      await cardRepo.createCard(c2);

      // Search by bank
      final r1 = await cardRepo.searchCards('HDFC', masterKey);
      expect(r1.length, equals(1));
      expect(r1.first.id, equals('s-1'));

      // Search by nickname
      final r2 = await cardRepo.searchCards('Salary', masterKey);
      expect(r2.length, equals(1));
      expect(r2.first.id, equals('s-2'));

      // Search by last 4
      final r3 = await cardRepo.searchCards('8877', masterKey);
      expect(r3.length, equals(1));
      expect(r3.first.id, equals('s-1'));

      // Search by cardholder name
      final r4 = await cardRepo.searchCards('Emma', masterKey);
      expect(r4.length, equals(1));
      expect(r4.first.id, equals('s-2'));
    });
  });

  group('PART 4: UI Widget Tests', () {
    testWidgets('14. PaymentCardWidget renders all required visual elements', (
      WidgetTester tester,
    ) async {
      final card = PaymentCardModel(
        id: 'widget-card-1',
        cardNickname: 'Platinum Premier',
        bankName: 'HDFC Bank',
        cardType: CardType.credit,
        network: CardNetwork.visa,
        lastFourDigits: '6543',
        expiryMonth: 8,
        expiryYear: 2029,
        cardColor: 1, // Ocean Sapphire
        isFavorite: true,
        decryptedCardholderName: 'VIKRAM SHARMA',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PaymentCardWidget(card: card)),
        ),
      );

      // Verify Bank Name
      expect(find.text('HDFC BANK'), findsOneWidget);
      // Verify Card Type Label
      expect(find.text('CREDIT'), findsOneWidget);
      // Verify Masked Number
      expect(find.text('••••  ••••  ••••  6543'), findsOneWidget);
      // Verify Cardholder Name
      expect(find.text('VIKRAM SHARMA'), findsOneWidget);
      // Verify Formatted Expiry
      expect(find.text('08/29'), findsOneWidget);
      // Verify Visa network logo badge
      expect(find.text('VISA'), findsOneWidget);
      // Verify Contactless Wave Icon
      expect(find.byIcon(Icons.contactless_rounded), findsOneWidget);
      // Verify Favorite Star Icon
      expect(find.byIcon(Icons.star_rounded), findsOneWidget);
    });

    testWidgets(
      '15. AddEditCardScreen enforces form validation and rejects invalid last4',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          const ProviderScope(child: MaterialApp(home: AddEditCardScreen())),
        );

        // Verify screen title
        expect(find.text('Add Payment Card'), findsOneWidget);

        // Verify NO CVV or ATM PIN input form fields exist on the screen!
        expect(find.widgetWithText(TextFormField, 'CVV'), findsNothing);
        expect(find.widgetWithText(TextFormField, 'CVC'), findsNothing);
        expect(find.widgetWithText(TextFormField, 'ATM PIN'), findsNothing);
        expect(find.widgetWithText(TextFormField, 'UPI PIN'), findsNothing);
        expect(find.widgetWithText(TextFormField, 'OTP'), findsNothing);

        // Tap Save without entering required fields
        final saveBtn = find.text('Save Card');
        expect(saveBtn, findsOneWidget);
        await tester.tap(saveBtn);
        await tester.pumpAndSettle();

        // Check validation error messages
        expect(find.text('Bank name is required'), findsOneWidget);
        expect(find.text('Card nickname is required'), findsOneWidget);
        expect(find.text('Card number is required'), findsOneWidget);
      },
    );

    test(
      '16. Full Card Number AES-256-GCM encryption, decryption, and formatting',
      () async {
        final masterKey = await encService.generateRandomMasterKey();

        final card = await PaymentCardModel.createEncrypted(
          id: 'full-pan-1',
          cardNickname: 'Corporate Amex',
          cardholderName: 'Elena Gilbert',
          fullCardNumber: '378282246310005', // 15-digit Amex
          bankName: 'American Express',
          cardType: CardType.credit,
          network: CardNetwork.amex,
          startMonth: 4,
          startYear: 2024,
          expiryMonth: 4,
          expiryYear: 2029,
          masterKey: masterKey,
          encryptionService: encService,
        );

        // Ciphertext must be encrypted
        expect(card.cardNumberEnc, isNotNull);
        expect(card.cardNumberEnc, isNot(contains('378282246310005')));
        // Last 4 digits automatically extracted
        expect(card.lastFourDigits, equals('0005'));
        expect(card.maskedCardNumber, equals('•••• •••• •••• 0005'));

        // Decryption roundtrip
        final decrypted = await card.decrypt(
          masterKey: masterKey,
          encryptionService: encService,
        );

        expect(decrypted.decryptedCardNumber, equals('378282246310005'));
        // Amex 4-6-5 formatting
        expect(decrypted.formattedFullCardNumber, equals('3782 822463 10005'));
        // Standard 16-digit Visa/Mastercard test
        final visaCard = await PaymentCardModel.createEncrypted(
          id: 'full-pan-2',
          cardNickname: 'Personal Visa',
          fullCardNumber: '4111222233334444',
          bankName: 'HDFC Bank',
          cardType: CardType.debit,
          network: CardNetwork.visa,
          expiryMonth: 12,
          expiryYear: 2028,
          masterKey: masterKey,
          encryptionService: encService,
        );
        final decryptedVisa = await visaCard.decrypt(
          masterKey: masterKey,
          encryptionService: encService,
        );
        expect(
          decryptedVisa.formattedFullCardNumber,
          equals('4111 2222 3333 4444'),
        );
      },
    );

    test(
      '17. Start Date (Valid From) formatting, persistence, and optionality',
      () async {
        final masterKey = await encService.generateRandomMasterKey();

        // Card with start date
        final cardWithStart = await PaymentCardModel.createEncrypted(
          id: 'start-card-1',
          cardNickname: 'RuPay Card',
          fullCardNumber: '6071123456789999',
          bankName: 'PNB',
          cardType: CardType.debit,
          network: CardNetwork.rupay,
          startMonth: 1,
          startYear: 2023,
          expiryMonth: 1,
          expiryYear: 2028,
          masterKey: masterKey,
          encryptionService: encService,
        );

        expect(cardWithStart.formattedStartDate, equals('01/23'));
        expect(cardWithStart.formattedExpiry, equals('01/28'));

        // Card without start date (optional)
        final cardWithoutStart = await PaymentCardModel.createEncrypted(
          id: 'start-card-2',
          cardNickname: 'Basic Card',
          fullCardNumber: '5123456789012345',
          bankName: 'SBI',
          cardType: CardType.credit,
          network: CardNetwork.mastercard,
          expiryMonth: 8,
          expiryYear: 2027,
          masterKey: masterKey,
          encryptionService: encService,
        );

        expect(cardWithoutStart.formattedStartDate, isNull);
        expect(cardWithoutStart.startMonth, isNull);
        expect(cardWithoutStart.startYear, isNull);

        // Verify persistence roundtrip via map
        final map = cardWithStart.toMap();
        expect(map['start_month'], equals(1));
        expect(map['start_year'], equals(2023));
        expect(map['card_number_enc'], isNotNull);

        final fromMap = PaymentCardModel.fromMap(map);
        expect(fromMap.formattedStartDate, equals('01/23'));
        expect(fromMap.cardNumberEnc, equals(cardWithStart.cardNumberEnc));
      },
    );

    test('16. Full Card Number AES-256-GCM encryption, decryption, and formatting', () async {
      final masterKey = await encService.generateRandomMasterKey();

      final card = await PaymentCardModel.createEncrypted(
        id: 'full-pan-1',
        cardNickname: 'Corporate Amex',
        cardholderName: 'Elena Gilbert',
        fullCardNumber: '378282246310005', // 15-digit Amex
        bankName: 'American Express',
        cardType: CardType.credit,
        network: CardNetwork.amex,
        startMonth: 4,
        startYear: 2024,
        expiryMonth: 4,
        expiryYear: 2029,
        masterKey: masterKey,
        encryptionService: encService,
      );

      // Ciphertext must be encrypted
      expect(card.cardNumberEnc, isNotNull);
      expect(card.cardNumberEnc, isNot(contains('378282246310005')));
      // Last 4 digits automatically extracted
      expect(card.lastFourDigits, equals('0005'));
      expect(card.maskedCardNumber, equals('•••• •••• •••• 0005'));

      // Decryption roundtrip
      final decrypted = await card.decrypt(
        masterKey: masterKey,
        encryptionService: encService,
      );

      expect(decrypted.decryptedCardNumber, equals('378282246310005'));
      // Amex 4-6-5 formatting
      expect(decrypted.formattedFullCardNumber, equals('3782 822463 10005'));
      // Standard 16-digit Visa/Mastercard test
      final visaCard = await PaymentCardModel.createEncrypted(
        id: 'full-pan-2',
        cardNickname: 'Personal Visa',
        fullCardNumber: '4111222233334444',
        bankName: 'HDFC Bank',
        cardType: CardType.debit,
        network: CardNetwork.visa,
        expiryMonth: 12,
        expiryYear: 2028,
        masterKey: masterKey,
        encryptionService: encService,
      );
      final decryptedVisa = await visaCard.decrypt(
        masterKey: masterKey,
        encryptionService: encService,
      );
      expect(decryptedVisa.formattedFullCardNumber, equals('4111 2222 3333 4444'));
    });

    test('17. Start Date (Valid From) formatting, persistence, and optionality', () async {
      final masterKey = await encService.generateRandomMasterKey();

      // Card with start date
      final cardWithStart = await PaymentCardModel.createEncrypted(
        id: 'start-card-1',
        cardNickname: 'RuPay Card',
        fullCardNumber: '6071123456789999',
        bankName: 'PNB',
        cardType: CardType.debit,
        network: CardNetwork.rupay,
        startMonth: 1,
        startYear: 2023,
        expiryMonth: 1,
        expiryYear: 2028,
        masterKey: masterKey,
        encryptionService: encService,
      );

      expect(cardWithStart.formattedStartDate, equals('01/23'));
      expect(cardWithStart.formattedExpiry, equals('01/28'));

      // Card without start date (optional)
      final cardWithoutStart = await PaymentCardModel.createEncrypted(
        id: 'start-card-2',
        cardNickname: 'Basic Card',
        fullCardNumber: '5123456789012345',
        bankName: 'SBI',
        cardType: CardType.credit,
        network: CardNetwork.mastercard,
        expiryMonth: 8,
        expiryYear: 2027,
        masterKey: masterKey,
        encryptionService: encService,
      );

      expect(cardWithoutStart.formattedStartDate, isNull);
      expect(cardWithoutStart.startMonth, isNull);
      expect(cardWithoutStart.startYear, isNull);

      // Verify persistence roundtrip via map
      final map = cardWithStart.toMap();
      expect(map['start_month'], equals(1));
      expect(map['start_year'], equals(2023));
      expect(map['card_number_enc'], isNotNull);

      final fromMap = PaymentCardModel.fromMap(map);
      expect(fromMap.formattedStartDate, equals('01/23'));
      expect(fromMap.cardNumberEnc, equals(cardWithStart.cardNumberEnc));
    });
  });
}
