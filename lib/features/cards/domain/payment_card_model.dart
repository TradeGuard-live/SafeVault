import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../../../core/security/encryption_service.dart';

/// Card Type: Credit or Debit.
enum CardType {
  credit,
  debit;

  String get displayName =>
      this == CardType.credit ? 'Credit Card' : 'Debit Card';
  String get shortLabel => this == CardType.credit ? 'CREDIT' : 'DEBIT';

  static CardType fromString(String value) {
    switch (value.toLowerCase().trim()) {
      case 'credit':
        return CardType.credit;
      case 'debit':
      default:
        return CardType.debit;
    }
  }
}

/// Payment Card Network.
enum CardNetwork {
  visa,
  mastercard,
  rupay,
  amex,
  other;

  String get displayName {
    switch (this) {
      case CardNetwork.visa:
        return 'Visa';
      case CardNetwork.mastercard:
        return 'Mastercard';
      case CardNetwork.rupay:
        return 'RuPay';
      case CardNetwork.amex:
        return 'American Express';
      case CardNetwork.other:
        return 'Other';
    }
  }

  static CardNetwork fromString(String value) {
    switch (value.toLowerCase().trim()) {
      case 'visa':
        return CardNetwork.visa;
      case 'mastercard':
        return CardNetwork.mastercard;
      case 'rupay':
        return CardNetwork.rupay;
      case 'amex':
      case 'american express':
        return CardNetwork.amex;
      default:
        return CardNetwork.other;
    }
  }
}

/// Visual theme presets for card rendering.
class CardVisualPreset {
  final int id;
  final String name;
  final List<int> gradientColors; // 0xAARRGGBB
  final int textColor;

  const CardVisualPreset({
    required this.id,
    required this.name,
    required this.gradientColors,
    required this.textColor,
  });

  static const List<CardVisualPreset> presets = [
    CardVisualPreset(
      id: 0,
      name: 'Titanium Obsidian',
      gradientColors: [0xFF1F2937, 0xFF111827],
      textColor: 0xFFF9FAFB,
    ),
    CardVisualPreset(
      id: 1,
      name: 'Ocean Sapphire',
      gradientColors: [0xFF1E3A8A, 0xFF0F172A],
      textColor: 0xFFF8FAFC,
    ),
    CardVisualPreset(
      id: 2,
      name: 'Emerald Prime',
      gradientColors: [0xFF065F46, 0xFF064E3B],
      textColor: 0xFFF0FDF4,
    ),
    CardVisualPreset(
      id: 3,
      name: 'Crimson Velvet',
      gradientColors: [0xFF881337, 0xFF4C0519],
      textColor: 0xFFFFF1F2,
    ),
    CardVisualPreset(
      id: 4,
      name: 'Royal Amethyst',
      gradientColors: [0xFF581C87, 0xFF3B0764],
      textColor: 0xFFFAF5FF,
    ),
    CardVisualPreset(
      id: 5,
      name: 'Midnight Gold',
      gradientColors: [0xFF78350F, 0xFF451A03],
      textColor: 0xFFFFFBEB,
    ),
  ];

  static CardVisualPreset getPreset(int id) {
    if (id < 0 || id >= presets.length) {
      return presets.first;
    }
    return presets[id];
  }
}

/// Payment Card Model (Credit / Debit).
///
/// STRICT SECURITY RESTRICTION:
/// This model stores REFERENCE information ONLY.
/// UNDER NO CIRCUMSTANCES DOES IT STORE OR ACCEPT:
/// - CVV / CVC / Security codes
/// - ATM PINs
/// - UPI PINs
/// - One-Time Passwords (OTPs)
/// - Magnetic stripe or chip cryptograms
///
/// Full Primary Account Numbers (PAN) and sensitive fields (cardholder name,
/// notes) are authenticated and encrypted at rest with AES-256-GCM + AAD.
/// Full PAN display and clipboard operations require biometric / 2FA.
class PaymentCardModel {
  final String id;
  final String cardNickname;
  final String? cardholderNameEnc;
  final String? cardNumberEnc; // AES-256-GCM encrypted full PAN
  final String bankName;
  final CardType cardType;
  final CardNetwork network;
  final String lastFourDigits;
  final int? startMonth; // 1 - 12 (Valid From / Start Date, optional)
  final int? startYear; // 4-digit year, e.g. 2024
  final int expiryMonth; // 1 - 12 (Valid Thru / Expiry Date)
  final int expiryYear; // 4-digit year, e.g. 2028
  final int cardColor; // 0 - 5
  final String? notesEnc;
  final bool isFavorite;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Ephemeral decrypted values (in-memory only, never persisted in plain SQLite)
  final String? decryptedCardholderName;
  final String? decryptedCardNumber;
  final String? decryptedNotes;

  const PaymentCardModel({
    required this.id,
    required this.cardNickname,
    this.cardholderNameEnc,
    this.cardNumberEnc,
    required this.bankName,
    required this.cardType,
    required this.network,
    required this.lastFourDigits,
    this.startMonth,
    this.startYear,
    required this.expiryMonth,
    required this.expiryYear,
    this.cardColor = 0,
    this.notesEnc,
    this.isFavorite = false,
    required this.createdAt,
    required this.updatedAt,
    this.decryptedCardholderName,
    this.decryptedCardNumber,
    this.decryptedNotes,
  });

  /// Formatted expiry as MM/YY (e.g. "08/28").
  String get formattedExpiry {
    final mm = expiryMonth.toString().padLeft(2, '0');
    final yy = (expiryYear % 100).toString().padLeft(2, '0');
    return '$mm/$yy';
  }

  /// Formatted start date as MM/YY (e.g. "06/24"), or null if not set.
  String? get formattedStartDate {
    if (startMonth == null || startYear == null) return null;
    final mm = startMonth!.toString().padLeft(2, '0');
    final yy = (startYear! % 100).toString().padLeft(2, '0');
    return '$mm/$yy';
  }

  /// Masked card number display: •••• •••• •••• 1234
  String get maskedCardNumber {
    final cleanDigits = lastFourDigits.padLeft(4, '•');
    return '•••• •••• •••• $cleanDigits';
  }

  /// Formatted full card number (spaced in 4-digit chunks or 4-6-5 for Amex),
  /// or falls back to maskedCardNumber if not yet decrypted.
  String get formattedFullCardNumber {
    if (decryptedCardNumber == null || decryptedCardNumber!.isEmpty) {
      return maskedCardNumber;
    }
    final digits = decryptedCardNumber!.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 15 && network == CardNetwork.amex) {
      // Amex format: 4-6-5
      return '${digits.substring(0, 4)} ${digits.substring(4, 10)} ${digits.substring(10)}';
    }
    final buffer = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  /// Whether the card has expired relative to the given [now] or current DateTime.
  bool isExpired([DateTime? now]) {
    final current = now ?? DateTime.now();
    final lastDayOfMonth = DateTime(expiryYear, expiryMonth + 1, 0, 23, 59, 59);
    return current.isAfter(lastDayOfMonth);
  }

  /// Whether the card expires within [days] (default 60 days).
  bool isExpiringSoon({int days = 60, DateTime? now}) {
    if (isExpired(now)) return false;
    final current = now ?? DateTime.now();
    final lastDayOfMonth = DateTime(expiryYear, expiryMonth + 1, 0, 23, 59, 59);
    final difference = lastDayOfMonth.difference(current).inDays;
    return difference >= 0 && difference <= days;
  }

  /// Days remaining until expiration. Negative if already expired.
  int daysRemaining([DateTime? now]) {
    final current = now ?? DateTime.now();
    final lastDayOfMonth = DateTime(expiryYear, expiryMonth + 1, 0, 23, 59, 59);
    return lastDayOfMonth.difference(current).inDays;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'card_nickname': cardNickname,
      'cardholder_name_enc': cardholderNameEnc,
      'card_number_enc': cardNumberEnc,
      'bank_name': bankName,
      'card_type': cardType.name,
      'network': network.name,
      'last_four_digits': lastFourDigits,
      'start_month': startMonth,
      'start_year': startYear,
      'expiry_month': expiryMonth,
      'expiry_year': expiryYear,
      'card_color': cardColor,
      'notes_enc': notesEnc,
      'is_favorite': isFavorite ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory PaymentCardModel.fromMap(Map<String, dynamic> map) {
    return PaymentCardModel(
      id: map['id'] as String,
      cardNickname: map['card_nickname'] as String,
      cardholderNameEnc: map['cardholder_name_enc'] as String?,
      cardNumberEnc: map['card_number_enc'] as String?,
      bankName: map['bank_name'] as String,
      cardType: CardType.fromString(map['card_type'] as String? ?? 'debit'),
      network: CardNetwork.fromString(map['network'] as String? ?? 'other'),
      lastFourDigits: (map['last_four_digits'] as String? ?? '0000').padLeft(
        4,
        '0',
      ),
      startMonth: (map['start_month'] as num?)?.toInt(),
      startYear: (map['start_year'] as num?)?.toInt(),
      expiryMonth: (map['expiry_month'] as num? ?? 1).toInt(),
      expiryYear: (map['expiry_year'] as num? ?? DateTime.now().year).toInt(),
      cardColor: (map['card_color'] as num? ?? 0).toInt(),
      notesEnc: map['notes_enc'] as String?,
      isFavorite: (map['is_favorite'] as int? ?? 0) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  /// Creates an encrypted instance from plaintext details using AES-256-GCM
  /// with Associated Authenticated Data (AAD) bound to the record ID and field name.
  static Future<PaymentCardModel> createEncrypted({
    required String id,
    required String cardNickname,
    String? cardholderName,
    String? fullCardNumber,
    String? lastFourDigits,
    required String bankName,
    required CardType cardType,
    required CardNetwork network,
    int? startMonth,
    int? startYear,
    required int expiryMonth,
    required int expiryYear,
    int cardColor = 0,
    String? notes,
    bool isFavorite = false,
    required SecretKey masterKey,
    required EncryptionService encryptionService,
  }) async {
    final now = DateTime.now();

    final cleanPan = fullCardNumber?.replaceAll(RegExp(r'\D'), '');

    // Derive last 4 digits from full PAN if provided, otherwise fallback to lastFourDigits
    final derivedLast4 = (cleanPan != null && cleanPan.length >= 4)
        ? cleanPan.substring(cleanPan.length - 4)
        : (lastFourDigits?.replaceAll(RegExp(r'\D'), '').padLeft(4, '0') ??
              '0000');

    final panEnc = cleanPan != null && cleanPan.isNotEmpty
        ? await encryptionService.encryptString(
            cleanPan,
            masterKey,
            aad: utf8.encode('$id:card_num'),
          )
        : null;

    final holderEnc = cardholderName != null && cardholderName.trim().isNotEmpty
        ? await encryptionService.encryptString(
            cardholderName.trim(),
            masterKey,
            aad: utf8.encode('$id:holder'),
          )
        : null;

    final notesEnc = notes != null && notes.trim().isNotEmpty
        ? await encryptionService.encryptString(
            notes.trim(),
            masterKey,
            aad: utf8.encode('$id:notes'),
          )
        : null;

    return PaymentCardModel(
      id: id,
      cardNickname: cardNickname.trim(),
      cardholderNameEnc: holderEnc,
      cardNumberEnc: panEnc,
      bankName: bankName.trim(),
      cardType: cardType,
      network: network,
      lastFourDigits: derivedLast4,
      startMonth: startMonth,
      startYear: startYear,
      expiryMonth: expiryMonth,
      expiryYear: expiryYear,
      cardColor: cardColor,
      notesEnc: notesEnc,
      isFavorite: isFavorite,
      createdAt: now,
      updatedAt: now,
      decryptedCardholderName: cardholderName?.trim(),
      decryptedCardNumber: cleanPan,
      decryptedNotes: notes?.trim(),
    );
  }

  /// Decrypts sensitive fields using the Vault Master Key and verifies AAD.
  Future<PaymentCardModel> decrypt({
    required SecretKey masterKey,
    required EncryptionService encryptionService,
  }) async {
    String? holder;
    String? pan;
    String? notes;

    try {
      if (cardholderNameEnc != null && cardholderNameEnc!.isNotEmpty) {
        holder = await encryptionService.decryptString(
          cardholderNameEnc!,
          masterKey,
          aad: utf8.encode('$id:holder'),
        );
      }
    } catch (_) {
      holder = null;
    }

    try {
      if (cardNumberEnc != null && cardNumberEnc!.isNotEmpty) {
        pan = await encryptionService.decryptString(
          cardNumberEnc!,
          masterKey,
          aad: utf8.encode('$id:card_num'),
        );
      }
    } catch (_) {
      pan = null;
    }

    try {
      if (notesEnc != null && notesEnc!.isNotEmpty) {
        notes = await encryptionService.decryptString(
          notesEnc!,
          masterKey,
          aad: utf8.encode('$id:notes'),
        );
      }
    } catch (_) {
      notes = null;
    }

    return PaymentCardModel(
      id: id,
      cardNickname: cardNickname,
      cardholderNameEnc: cardholderNameEnc,
      cardNumberEnc: cardNumberEnc,
      bankName: bankName,
      cardType: cardType,
      network: network,
      lastFourDigits: lastFourDigits,
      startMonth: startMonth,
      startYear: startYear,
      expiryMonth: expiryMonth,
      expiryYear: expiryYear,
      cardColor: cardColor,
      notesEnc: notesEnc,
      isFavorite: isFavorite,
      createdAt: createdAt,
      updatedAt: updatedAt,
      decryptedCardholderName: holder,
      decryptedCardNumber: pan,
      decryptedNotes: notes,
    );
  }

  PaymentCardModel copyWith({
    String? id,
    String? cardNickname,
    String? cardholderNameEnc,
    String? cardNumberEnc,
    String? bankName,
    CardType? cardType,
    CardNetwork? network,
    String? lastFourDigits,
    int? startMonth,
    int? startYear,
    int? expiryMonth,
    int? expiryYear,
    int? cardColor,
    String? notesEnc,
    bool? isFavorite,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? decryptedCardholderName,
    String? decryptedCardNumber,
    String? decryptedNotes,
  }) {
    return PaymentCardModel(
      id: id ?? this.id,
      cardNickname: cardNickname ?? this.cardNickname,
      cardholderNameEnc: cardholderNameEnc ?? this.cardholderNameEnc,
      cardNumberEnc: cardNumberEnc ?? this.cardNumberEnc,
      bankName: bankName ?? this.bankName,
      cardType: cardType ?? this.cardType,
      network: network ?? this.network,
      lastFourDigits: lastFourDigits ?? this.lastFourDigits,
      startMonth: startMonth ?? this.startMonth,
      startYear: startYear ?? this.startYear,
      expiryMonth: expiryMonth ?? this.expiryMonth,
      expiryYear: expiryYear ?? this.expiryYear,
      cardColor: cardColor ?? this.cardColor,
      notesEnc: notesEnc ?? this.notesEnc,
      isFavorite: isFavorite ?? this.isFavorite,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      decryptedCardholderName:
          decryptedCardholderName ?? this.decryptedCardholderName,
      decryptedCardNumber: decryptedCardNumber ?? this.decryptedCardNumber,
      decryptedNotes: decryptedNotes ?? this.decryptedNotes,
    );
  }

  @override
  String toString() {
    // Redact sensitive details in logs and debugging outputs
    return 'PaymentCardModel(id: $id, bank: $bankName, nickname: $cardNickname, type: ${cardType.name}, network: ${network.name}, last4: $lastFourDigits, start: $formattedStartDate, expiry: $formattedExpiry, fav: $isFavorite)';
  }
}
