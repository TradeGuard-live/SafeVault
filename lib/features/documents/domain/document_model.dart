import 'dart:convert';
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
  final List<DocumentFileModel> files;

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
    this.files = const [],
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
    List<DocumentFileModel>? files,
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
      files: files ?? this.files,
    );
  }
}

