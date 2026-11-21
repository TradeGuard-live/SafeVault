class DocumentDraftModel {
  final String id;
  final String title;
  final String categoryId;
  final String? documentType;
  final String? documentNumber;
  final String? ownerName;
  final String? issuingAuthority;
  final DateTime? issueDate;
  final DateTime? expiryDate;
  final String? notes;
  final List<String> tags;
  final List<Map<String, dynamic>> attachedFiles;
  final DateTime updatedAt;

  const DocumentDraftModel({
    this.id = 'active_draft',
    this.title = '',
    this.categoryId = 'personal_identity',
    this.documentType,
    this.documentNumber,
    this.ownerName,
    this.issuingAuthority,
    this.issueDate,
    this.expiryDate,
    this.notes,
    this.tags = const [],
    this.attachedFiles = const [],
    required this.updatedAt,
  });

  bool get isEmpty =>
      title.trim().isEmpty &&
      (documentNumber == null || documentNumber!.trim().isEmpty) &&
      (ownerName == null || ownerName!.trim().isEmpty) &&
      (issuingAuthority == null || issuingAuthority!.trim().isEmpty) &&
      (notes == null || notes!.trim().isEmpty) &&
      tags.isEmpty &&
      attachedFiles.isEmpty;

  bool get isNotEmpty => !isEmpty;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'categoryId': categoryId,
      'documentType': documentType,
      'documentNumber': documentNumber,
      'ownerName': ownerName,
      'issuingAuthority': issuingAuthority,
      'issueDate': issueDate?.toIso8601String(),
      'expiryDate': expiryDate?.toIso8601String(),
      'notes': notes,
      'tags': tags,
      'attachedFiles': attachedFiles,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory DocumentDraftModel.fromMap(Map<String, dynamic> map) {
    return DocumentDraftModel(
      id: map['id'] as String? ?? 'active_draft',
      title: map['title'] as String? ?? '',
      categoryId: map['categoryId'] as String? ?? 'personal_identity',
      documentType: map['documentType'] as String?,
      documentNumber: map['documentNumber'] as String?,
      ownerName: map['ownerName'] as String?,
      issuingAuthority: map['issuingAuthority'] as String?,
      issueDate: map['issueDate'] != null
          ? DateTime.tryParse(map['issueDate'] as String)
          : null,
      expiryDate: map['expiryDate'] != null
          ? DateTime.tryParse(map['expiryDate'] as String)
          : null,
      notes: map['notes'] as String?,
      tags:
          (map['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
          [],
      attachedFiles:
          (map['attachedFiles'] as List<dynamic>?)
              ?.whereType<Map<dynamic, dynamic>>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [],
      updatedAt: map['updatedAt'] != null
          ? DateTime.tryParse(map['updatedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  DocumentDraftModel copyWith({
    String? id,
    String? title,
    String? categoryId,
    String? documentType,
    String? documentNumber,
    String? ownerName,
    String? issuingAuthority,
    DateTime? issueDate,
    DateTime? expiryDate,
    String? notes,
    List<String>? tags,
    List<Map<String, dynamic>>? attachedFiles,
    DateTime? updatedAt,
  }) {
    return DocumentDraftModel(
      id: id ?? this.id,
      title: title ?? this.title,
      categoryId: categoryId ?? this.categoryId,
      documentType: documentType ?? this.documentType,
      documentNumber: documentNumber ?? this.documentNumber,
      ownerName: ownerName ?? this.ownerName,
      issuingAuthority: issuingAuthority ?? this.issuingAuthority,
      issueDate: issueDate ?? this.issueDate,
      expiryDate: expiryDate ?? this.expiryDate,
      notes: notes ?? this.notes,
      tags: tags ?? this.tags,
      attachedFiles: attachedFiles ?? this.attachedFiles,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
