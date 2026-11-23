import 'dart:convert';

import '../../ocr/domain/document_extraction_model.dart';
import 'document_file_model.dart';

class DocumentModel {
  final String id;
  final String name;
  final String categoryId;
  final String? documentNumber;
  final String? ownerName;
  final String? issuingAuthority;
  final DateTime? issueDate;
  final DateTime? expiryDate;
  final String? notes;
  final List<String> tags;
  final bool isFavorite;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String? thumbnailEncPath;
  final String? documentType;
  final String? extractionStatus; // 'waiting', 'importing', 'encrypting', 'extractingText', 'recognizingFields', 'needsReview', 'completed', 'failed'
  final String? extractedTxtEncPath;
  final bool isTemporary;
  final DateTime? expiresAt;
  final String expiryStatus; // 'ACTIVE', 'EXPIRED'
  final List<String> groupIds;
  final List<DocumentFileModel> files;
  final DocumentExtractionModel? extraction;

  const DocumentModel({
    required this.id,
    required this.name,
    required this.categoryId,
    this.documentNumber,
    this.ownerName,
    this.issuingAuthority,
    this.issueDate,
    this.expiryDate,
    this.notes,
    this.tags = const [],
    this.isFavorite = false,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.thumbnailEncPath,
    this.documentType,
    this.extractionStatus = 'completed',
    this.extractedTxtEncPath,
    this.isTemporary = false,
    this.expiresAt,
    this.expiryStatus = 'ACTIVE',
    this.groupIds = const [],
    this.files = const [],
    this.extraction,
  });

  bool get isDeleted => deletedAt != null;

  bool get isExpired =>
      isTemporary && expiresAt != null && expiresAt!.isBefore(DateTime.now());

  int? get remainingDays {
    if (!isTemporary || expiresAt == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final exp = DateTime(expiresAt!.year, expiresAt!.month, expiresAt!.day);
    return exp.difference(today).inDays;
  }

  String get temporaryStatusLabel {
    if (!isTemporary) return 'Permanent';
    if (isExpired) return 'Expired';
    final days = remainingDays;
    if (days == null) return 'Temporary';
    if (days < 0) return 'Expired';
    if (days == 0) return 'Expires Today';
    if (days == 1) return 'Expires Tomorrow';
    return 'Expires in $days days';
  }

  DocumentModel copyWith({
    String? id,
    String? name,
    String? categoryId,
    String? documentNumber,
    String? ownerName,
    String? issuingAuthority,
    DateTime? issueDate,
    DateTime? expiryDate,
    String? notes,
    List<String>? tags,
    bool? isFavorite,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    String? thumbnailEncPath,
    String? documentType,
    String? extractionStatus,
    String? extractedTxtEncPath,
    bool? isTemporary,
    DateTime? expiresAt,
    bool clearExpiresAt = false,
    String? expiryStatus,
    List<String>? groupIds,
    List<DocumentFileModel>? files,
    DocumentExtractionModel? extraction,
  }) {
    return DocumentModel(
      id: id ?? this.id,
      name: name ?? this.name,
      categoryId: categoryId ?? this.categoryId,
      documentNumber: documentNumber ?? this.documentNumber,
      ownerName: ownerName ?? this.ownerName,
      issuingAuthority: issuingAuthority ?? this.issuingAuthority,
      issueDate: issueDate ?? this.issueDate,
      expiryDate: expiryDate ?? this.expiryDate,
      notes: notes ?? this.notes,
      tags: tags ?? this.tags,
      isFavorite: isFavorite ?? this.isFavorite,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      thumbnailEncPath: thumbnailEncPath ?? this.thumbnailEncPath,
      documentType: documentType ?? this.documentType,
      extractionStatus: extractionStatus ?? this.extractionStatus,
      extractedTxtEncPath: extractedTxtEncPath ?? this.extractedTxtEncPath,
      isTemporary: isTemporary ?? this.isTemporary,
      expiresAt: clearExpiresAt ? null : (expiresAt ?? this.expiresAt),
      expiryStatus: expiryStatus ?? this.expiryStatus,
      groupIds: groupIds ?? this.groupIds,
      files: files ?? this.files,
      extraction: extraction ?? this.extraction,
    );
  }
}
