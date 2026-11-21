import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../../../core/security/encryption_service.dart';

class PasswordEntryModel {
  final String id;
  final String title;
  final String? websiteUrl;
  final String? usernameEnc;
  final String? emailEnc;
  final String passwordEnc;
  final String? notesEnc;
  final String categoryId;
  final bool isFavorite;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastAccessedAt;

  // Ephemeral decrypted values (never written to SQLite directly)
  final String? decryptedUsername;
  final String? decryptedEmail;
  final String? decryptedPassword;
  final String? decryptedNotes;

  const PasswordEntryModel({
    required this.id,
    required this.title,
    this.websiteUrl,
    this.usernameEnc,
    this.emailEnc,
    required this.passwordEnc,
    this.notesEnc,
    required this.categoryId,
    this.isFavorite = false,
    required this.createdAt,
    required this.updatedAt,
    this.lastAccessedAt,
    this.decryptedUsername,
    this.decryptedEmail,
    this.decryptedPassword,
    this.decryptedNotes,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'website_url': websiteUrl,
      'username_enc': usernameEnc,
      'email_enc': emailEnc,
      'password_enc': passwordEnc,
      'notes_enc': notesEnc,
      'category_id': categoryId,
      'is_favorite': isFavorite ? 1 : 0,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'last_accessed_at': lastAccessedAt?.toIso8601String(),
    };
  }

  factory PasswordEntryModel.fromMap(Map<String, dynamic> map) {
    return PasswordEntryModel(
      id: map['id'] as String,
      title: map['title'] as String,
      websiteUrl: map['website_url'] as String?,
      usernameEnc: map['username_enc'] as String?,
      emailEnc: map['email_enc'] as String?,
      passwordEnc: map['password_enc'] as String,
      notesEnc: map['notes_enc'] as String?,
      categoryId: map['category_id'] as String,
      isFavorite: (map['is_favorite'] as int? ?? 0) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      lastAccessedAt: map['last_accessed_at'] != null
          ? DateTime.tryParse(map['last_accessed_at'] as String)
          : null,
    );
  }

  /// Creates an encrypted instance from plaintext credentials using AES-256-GCM
  /// with Associated Authenticated Data (AAD) bound to the record ID and field name.
  static Future<PasswordEntryModel> createEncrypted({
    required String id,
    required String title,
    String? websiteUrl,
    String? username,
    String? email,
    required String password,
    String? notes,
    required String categoryId,
    bool isFavorite = false,
    required SecretKey masterKey,
    required EncryptionService encryptionService,
  }) async {
    final now = DateTime.now();

    final usernameEnc = username != null && username.isNotEmpty
        ? await encryptionService.encryptString(
            username,
            masterKey,
            aad: utf8.encode('$id:username'),
          )
        : null;

    final emailEnc = email != null && email.isNotEmpty
        ? await encryptionService.encryptString(
            email,
            masterKey,
            aad: utf8.encode('$id:email'),
          )
        : null;

    final passwordEnc = await encryptionService.encryptString(
      password,
      masterKey,
      aad: utf8.encode('$id:password'),
    );

    final notesEnc = notes != null && notes.isNotEmpty
        ? await encryptionService.encryptString(
            notes,
            masterKey,
            aad: utf8.encode('$id:notes'),
          )
        : null;

    return PasswordEntryModel(
      id: id,
      title: title,
      websiteUrl: websiteUrl,
      usernameEnc: usernameEnc,
      emailEnc: emailEnc,
      passwordEnc: passwordEnc,
      notesEnc: notesEnc,
      categoryId: categoryId,
      isFavorite: isFavorite,
      createdAt: now,
      updatedAt: now,
      decryptedUsername: username,
      decryptedEmail: email,
      decryptedPassword: password,
      decryptedNotes: notes,
    );
  }

  /// Decrypts all sensitive fields using the Vault Master Key and verifies AAD.
  Future<PasswordEntryModel> decrypt({
    required SecretKey masterKey,
    required EncryptionService encryptionService,
  }) async {
    String? username;
    String? email;
    String? password;
    String? notes;

    try {
      if (usernameEnc != null && usernameEnc!.isNotEmpty) {
        username = await encryptionService.decryptString(
          usernameEnc!,
          masterKey,
          aad: utf8.encode('$id:username'),
        );
      }
    } catch (_) {
      username = null;
    }

    try {
      if (emailEnc != null && emailEnc!.isNotEmpty) {
        email = await encryptionService.decryptString(
          emailEnc!,
          masterKey,
          aad: utf8.encode('$id:email'),
        );
      }
    } catch (_) {
      email = null;
    }

    try {
      password = await encryptionService.decryptString(
        passwordEnc,
        masterKey,
        aad: utf8.encode('$id:password'),
      );
    } catch (_) {
      password = null;
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

    return PasswordEntryModel(
      id: id,
      title: title,
      websiteUrl: websiteUrl,
      usernameEnc: usernameEnc,
      emailEnc: emailEnc,
      passwordEnc: passwordEnc,
      notesEnc: notesEnc,
      categoryId: categoryId,
      isFavorite: isFavorite,
      createdAt: createdAt,
      updatedAt: updatedAt,
      lastAccessedAt: lastAccessedAt,
      decryptedUsername: username,
      decryptedEmail: email,
      decryptedPassword: password,
      decryptedNotes: notes,
    );
  }

  PasswordEntryModel copyWith({
    String? id,
    String? title,
    String? websiteUrl,
    String? usernameEnc,
    String? emailEnc,
    String? passwordEnc,
    String? notesEnc,
    String? categoryId,
    bool? isFavorite,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastAccessedAt,
    String? decryptedUsername,
    String? decryptedEmail,
    String? decryptedPassword,
    String? decryptedNotes,
  }) {
    return PasswordEntryModel(
      id: id ?? this.id,
      title: title ?? this.title,
      websiteUrl: websiteUrl ?? this.websiteUrl,
      usernameEnc: usernameEnc ?? this.usernameEnc,
      emailEnc: emailEnc ?? this.emailEnc,
      passwordEnc: passwordEnc ?? this.passwordEnc,
      notesEnc: notesEnc ?? this.notesEnc,
      categoryId: categoryId ?? this.categoryId,
      isFavorite: isFavorite ?? this.isFavorite,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
      decryptedUsername: decryptedUsername ?? this.decryptedUsername,
      decryptedEmail: decryptedEmail ?? this.decryptedEmail,
      decryptedPassword: decryptedPassword ?? this.decryptedPassword,
      decryptedNotes: decryptedNotes ?? this.decryptedNotes,
    );
  }
}
