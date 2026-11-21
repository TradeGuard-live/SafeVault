class DocumentFileModel {
  final String id;
  final String documentId;
  final String encryptedFilePath;
  final String originalFileName;
  final String mimeType;
  final int fileSize;
  final int pageNumber;
  final int encryptionVersion;
  final String? encryptedTxtPath;
  final int extractionVersion;
  final DateTime createdAt;

  const DocumentFileModel({
    required this.id,
    required this.documentId,
    required this.encryptedFilePath,
    required this.originalFileName,
    required this.mimeType,
    required this.fileSize,
    this.pageNumber = 1,
    this.encryptionVersion = 1,
    this.encryptedTxtPath,
    this.extractionVersion = 1,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'document_id': documentId,
      'encrypted_file_path': encryptedFilePath,
      'original_file_name': originalFileName,
      'mime_type': mimeType,
      'file_size': fileSize,
      'page_number': pageNumber,
      'encryption_version': encryptionVersion,
      'encrypted_txt_path': encryptedTxtPath,
      'extraction_version': extractionVersion,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory DocumentFileModel.fromMap(Map<String, dynamic> map) {
    return DocumentFileModel(
      id: map['id'] as String,
      documentId: map['document_id'] as String,
      encryptedFilePath: map['encrypted_file_path'] as String,
      originalFileName: map['original_file_name'] as String,
      mimeType: map['mime_type'] as String,
      fileSize: map['file_size'] as int,
      pageNumber: map['page_number'] as int? ?? 1,
      encryptionVersion: map['encryption_version'] as int? ?? 1,
      encryptedTxtPath: map['encrypted_txt_path'] as String?,
      extractionVersion: map['extraction_version'] as int? ?? 1,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
