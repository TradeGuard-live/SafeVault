import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../../../core/security/encryption_service.dart';

/// Bank Account Reference Model.
///
/// STRICT SECURITY RESTRICTION:
/// This model stores REFERENCE information ONLY.
/// UNDER NO CIRCUMSTANCES DOES IT STORE OR ACCEPT:
/// - ATM PINs
/// - Debit or Credit Card CVVs
/// - UPI PINs
/// - OTPs
/// - Netbanking login or transaction passwords
class BankAccountModel {
  final String id;
  final String bankName;
  final String? accountHolderEnc;
  final String accountNumberEnc;
  final String? ifscEnc;
  final String? branchEnc;
  final String accountType; // savings, current, salary, other
  final String? nickname;
  final String? notesEnc;
  final bool isFavorite;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Ephemeral decrypted values (never written to SQLite directly)
  final String? decryptedAccountHolder;
  final String? decryptedAccountNumber;
  final String? decryptedIFSC;
  final String? decryptedBranch;
  final String? decryptedNotes;

  const BankAccountModel({
    required this.id,
    required this.bankName,
    this.accountHolderEnc,
    required this.accountNumberEnc,
    this.ifscEnc,
    this.branchEnc,
    this.accountType = 'savings',
    this.nickname,
    this.notesEnc,
    this.isFavorite = false,
    required this.createdAt,
    required this.updatedAt,
    this.decryptedAccountHolder,
    this.decryptedAccountNumber,
    this.decryptedIFSC,
    this.decryptedBranch,
    this.decryptedNotes,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'bank_name': bankName,
      'account_holder_enc': accountHolderEnc,
      'account_number_enc': accountNumberEnc,
      'ifsc_enc': ifscEnc,
      'branch_enc': branchEnc,
      'account_type': accountType,
      'nickname': nickname,
      'notes_enc': notesEnc,
      'is_favorite': isFavorite ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory BankAccountModel.fromMap(Map<String, dynamic> map) {
    return BankAccountModel(
      id: map['id'] as String,
      bankName: map['bank_name'] as String,
      accountHolderEnc: map['account_holder_enc'] as String?,
      accountNumberEnc: map['account_number_enc'] as String,
      ifscEnc: map['ifsc_enc'] as String?,
      branchEnc: map['branch_enc'] as String?,
      accountType: map['account_type'] as String? ?? 'savings',
      nickname: map['nickname'] as String?,
      notesEnc: map['notes_enc'] as String?,
      isFavorite: (map['is_favorite'] as int? ?? 0) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  /// Creates an encrypted instance from plaintext details using AES-256-GCM
  /// with Associated Authenticated Data (AAD) bound to the record ID and field name.
  static Future<BankAccountModel> createEncrypted({
    required String id,
    required String bankName,
    String? accountHolder,
    required String accountNumber,
    String? ifsc,
    String? branch,
    String accountType = 'savings',
    String? nickname,
    String? notes,
    bool isFavorite = false,
    required SecretKey masterKey,
    required EncryptionService encryptionService,
  }) async {
    final now = DateTime.now();

    final holderEnc = accountHolder != null && accountHolder.isNotEmpty
        ? await encryptionService.encryptString(
            accountHolder,
            masterKey,
            aad: utf8.encode('$id:holder'),
          )
        : null;

    final numberEnc = await encryptionService.encryptString(
      accountNumber,
      masterKey,
      aad: utf8.encode('$id:acc_num'),
    );

    final ifscEnc = ifsc != null && ifsc.isNotEmpty
        ? await encryptionService.encryptString(
            ifsc,
            masterKey,
            aad: utf8.encode('$id:ifsc'),
          )
        : null;

    final branchEnc = branch != null && branch.isNotEmpty
        ? await encryptionService.encryptString(
            branch,
            masterKey,
            aad: utf8.encode('$id:branch'),
          )
        : null;

    final notesEnc = notes != null && notes.isNotEmpty
        ? await encryptionService.encryptString(
            notes,
            masterKey,
            aad: utf8.encode('$id:notes'),
          )
        : null;

    return BankAccountModel(
      id: id,
      bankName: bankName,
      accountHolderEnc: holderEnc,
      accountNumberEnc: numberEnc,
      ifscEnc: ifscEnc,
      branchEnc: branchEnc,
      accountType: accountType,
      nickname: nickname,
      notesEnc: notesEnc,
      isFavorite: isFavorite,
      createdAt: now,
      updatedAt: now,
      decryptedAccountHolder: accountHolder,
      decryptedAccountNumber: accountNumber,
      decryptedIFSC: ifsc,
      decryptedBranch: branch,
      decryptedNotes: notes,
    );
  }

  /// Decrypts all sensitive fields using the Vault Master Key and verifies AAD.
  Future<BankAccountModel> decrypt({
    required SecretKey masterKey,
    required EncryptionService encryptionService,
  }) async {
    String? holder;
    String? number;
    String? ifsc;
    String? branch;
    String? notes;

    try {
      if (accountHolderEnc != null && accountHolderEnc!.isNotEmpty) {
        holder = await encryptionService.decryptString(
          accountHolderEnc!,
          masterKey,
          aad: utf8.encode('$id:holder'),
        );
      }
    } catch (_) {
      holder = null;
    }

    try {
      number = await encryptionService.decryptString(
        accountNumberEnc,
        masterKey,
        aad: utf8.encode('$id:acc_num'),
      );
    } catch (_) {
      number = null;
    }

    try {
      if (ifscEnc != null && ifscEnc!.isNotEmpty) {
        ifsc = await encryptionService.decryptString(
          ifscEnc!,
          masterKey,
          aad: utf8.encode('$id:ifsc'),
        );
      }
    } catch (_) {
      ifsc = null;
    }

    try {
      if (branchEnc != null && branchEnc!.isNotEmpty) {
        branch = await encryptionService.decryptString(
          branchEnc!,
          masterKey,
          aad: utf8.encode('$id:branch'),
        );
      }
    } catch (_) {
      branch = null;
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

    return BankAccountModel(
      id: id,
      bankName: bankName,
      accountHolderEnc: accountHolderEnc,
      accountNumberEnc: accountNumberEnc,
      ifscEnc: ifscEnc,
      branchEnc: branchEnc,
      accountType: accountType,
      nickname: nickname,
      notesEnc: notesEnc,
      isFavorite: isFavorite,
      createdAt: createdAt,
      updatedAt: updatedAt,
      decryptedAccountHolder: holder,
      decryptedAccountNumber: number,
      decryptedIFSC: ifsc,
      decryptedBranch: branch,
      decryptedNotes: notes,
    );
  }

  /// Formatted masked account number (e.g. "•••• •••• 4589")
  String get maskedAccountNumber {
    if (decryptedAccountNumber != null && decryptedAccountNumber!.isNotEmpty) {
      final num = decryptedAccountNumber!;
      if (num.length <= 4) return '•••• $num';
      final last4 = num.substring(num.length - 4);
      return '•••• •••• •••• $last4';
    }
    return '•••• •••• •••• ••••';
  }

  BankAccountModel copyWith({
    String? id,
    String? bankName,
    String? accountHolderEnc,
    String? accountNumberEnc,
    String? ifscEnc,
    String? branchEnc,
    String? accountType,
    String? nickname,
    String? notesEnc,
    bool? isFavorite,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? decryptedAccountHolder,
    String? decryptedAccountNumber,
    String? decryptedIFSC,
    String? decryptedBranch,
    String? decryptedNotes,
  }) {
    return BankAccountModel(
      id: id ?? this.id,
      bankName: bankName ?? this.bankName,
      accountHolderEnc: accountHolderEnc ?? this.accountHolderEnc,
      accountNumberEnc: accountNumberEnc ?? this.accountNumberEnc,
      ifscEnc: ifscEnc ?? this.ifscEnc,
      branchEnc: branchEnc ?? this.branchEnc,
      accountType: accountType ?? this.accountType,
      nickname: nickname ?? this.nickname,
      notesEnc: notesEnc ?? this.notesEnc,
      isFavorite: isFavorite ?? this.isFavorite,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      decryptedAccountHolder:
          decryptedAccountHolder ?? this.decryptedAccountHolder,
      decryptedAccountNumber:
          decryptedAccountNumber ?? this.decryptedAccountNumber,
      decryptedIFSC: decryptedIFSC ?? this.decryptedIFSC,
      decryptedBranch: decryptedBranch ?? this.decryptedBranch,
      decryptedNotes: decryptedNotes ?? this.decryptedNotes,
    );
  }
}
