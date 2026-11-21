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
    this.files = const [],
    this.extraction,
  });

  bool get isDeleted => deletedAt != null;

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
      files: files ?? this.files,
      extraction: extraction ?? this.extraction,
    );
  }
}
