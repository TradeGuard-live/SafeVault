class DocumentExtractionModel {
  final String id;
  final String documentId;
  final String? extractedTextEncrypted;
  final String? encryptedTxtFilePath;
  final String extractionEngine;
  final String language;
  final int pageCount;
  final String extractionStatus; // 'waiting', 'importing', 'encrypting', 'extractingText', 'recognizingFields', 'needsReview', 'completed', 'failed'
  final DateTime createdAt;
  final DateTime updatedAt;
  final int version;
  final List<ExtractedFieldModel> fields;

  const DocumentExtractionModel({
    required this.id,
    required this.documentId,
    this.extractedTextEncrypted,
    this.encryptedTxtFilePath,
    required this.extractionEngine,
    this.language = 'eng',
    this.pageCount = 1,
    this.extractionStatus = 'completed',
    required this.createdAt,
    required this.updatedAt,
    this.version = 1,
    this.fields = const [],
  });

  DocumentExtractionModel copyWith({
    String? id,
    String? documentId,
    String? extractedTextEncrypted,
    String? encryptedTxtFilePath,
    String? extractionEngine,
    String? language,
    int? pageCount,
    String? extractionStatus,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? version,
    List<ExtractedFieldModel>? fields,
  }) {
    return DocumentExtractionModel(
      id: id ?? this.id,
      documentId: documentId ?? this.documentId,
      extractedTextEncrypted: extractedTextEncrypted ?? this.extractedTextEncrypted,
      encryptedTxtFilePath: encryptedTxtFilePath ?? this.encryptedTxtFilePath,
      extractionEngine: extractionEngine ?? this.extractionEngine,
      language: language ?? this.language,
      pageCount: pageCount ?? this.pageCount,
      extractionStatus: extractionStatus ?? this.extractionStatus,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      version: version ?? this.version,
      fields: fields ?? this.fields,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'document_id': documentId,
      'extracted_text_encrypted': extractedTextEncrypted,
      'encrypted_txt_file_path': encryptedTxtFilePath,
      'extraction_engine': extractionEngine,
      'language': language,
      'page_count': pageCount,
      'extraction_status': extractionStatus,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'version': version,
    };
  }

  factory DocumentExtractionModel.fromMap(Map<String, dynamic> map, [List<ExtractedFieldModel> fields = const []]) {
    return DocumentExtractionModel(
      id: map['id'] as String,
      documentId: map['document_id'] as String,
      extractedTextEncrypted: map['extracted_text_encrypted'] as String?,
      encryptedTxtFilePath: map['encrypted_txt_file_path'] as String?,
      extractionEngine: map['extraction_engine'] as String? ?? 'Tesseract OCR',
      language: map['language'] as String? ?? 'eng',
      pageCount: (map['page_count'] as num?)?.toInt() ?? 1,
      extractionStatus: map['extraction_status'] as String? ?? 'completed',
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      version: (map['version'] as num?)?.toInt() ?? 1,
      fields: fields,
    );
  }
}

class ExtractedFieldModel {
  final String id;
  final String extractionId;
  final String fieldName;
  final String encryptedValue; // Encrypted with AES-256-GCM or in-memory decrypted
  final double confidence;
  final String confidenceCategory; // 'High', 'Medium', 'Low'
  final int sourcePage;
  final String verificationStatus; // 'verified', 'unverified', 'edited'
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? plainValue; // In-memory decrypted value

  const ExtractedFieldModel({
    required this.id,
    required this.extractionId,
    required this.fieldName,
    required this.encryptedValue,
    required this.confidence,
    required this.confidenceCategory,
    this.sourcePage = 1,
    this.verificationStatus = 'unverified',
    required this.createdAt,
    required this.updatedAt,
    this.plainValue,
  });

  ExtractedFieldModel copyWith({
    String? id,
    String? extractionId,
    String? fieldName,
    String? encryptedValue,
    double? confidence,
    String? confidenceCategory,
    int? sourcePage,
    String? verificationStatus,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? plainValue,
  }) {
    return ExtractedFieldModel(
      id: id ?? this.id,
      extractionId: extractionId ?? this.extractionId,
      fieldName: fieldName ?? this.fieldName,
      encryptedValue: encryptedValue ?? this.encryptedValue,
      confidence: confidence ?? this.confidence,
      confidenceCategory: confidenceCategory ?? this.confidenceCategory,
      sourcePage: sourcePage ?? this.sourcePage,
      verificationStatus: verificationStatus ?? this.verificationStatus,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      plainValue: plainValue ?? this.plainValue,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'extraction_id': extractionId,
      'field_name': fieldName,
      'encrypted_value': encryptedValue,
      'confidence': confidence,
      'confidence_category': confidenceCategory,
      'source_page': sourcePage,
      'verification_status': verificationStatus,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory ExtractedFieldModel.fromMap(Map<String, dynamic> map, [String? decryptedPlainValue]) {
    return ExtractedFieldModel(
      id: map['id'] as String,
      extractionId: map['extraction_id'] as String,
      fieldName: map['field_name'] as String,
      encryptedValue: map['encrypted_value'] as String,
      confidence: (map['confidence'] as num?)?.toDouble() ?? 0.8,
      confidenceCategory: map['confidence_category'] as String? ?? 'Medium',
      sourcePage: (map['source_page'] as num?)?.toInt() ?? 1,
      verificationStatus: map['verification_status'] as String? ?? 'unverified',
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
      plainValue: decryptedPlainValue,
    );
  }
}

