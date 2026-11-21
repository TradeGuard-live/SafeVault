import 'dart:io';
import 'dart:typed_data';

import '../constants/app_constants.dart';
import '../errors/exceptions.dart';

enum ValidatedFileType { pdf, jpeg, png }

class FileValidationResult {
  final ValidatedFileType fileType;
  final String mimeType;
  final String extension;
  final int byteLength;

  const FileValidationResult({
    required this.fileType,
    required this.mimeType,
    required this.extension,
    required this.byteLength,
  });
}

class FileValidator {
  // Magic bytes
  static const List<int> _pdfMagic = [0x25, 0x50, 0x44, 0x46]; // %PDF
  static const List<int> _jpegMagic = [0xFF, 0xD8, 0xFF]; // SOI
  static const List<int> _pngMagic = [
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
  ]; // \x89PNG\r\n\x1a\n

  /// Validates a file on disk by reading its magic bytes and checking size.
  static Future<FileValidationResult> validateFile(File file) async {
    if (!await file.exists()) {
      throw const StorageException('Source file does not exist.');
    }

    final length = await file.length();
    if (length == 0) {
      throw const FileCorruptedException('File is empty.');
    }
    if (length > AppConstants.maxFileSizeBytes) {
      throw const StorageException(
        'File exceeds maximum allowed size of 50 MB.',
      );
    }

    // Read initial 32 bytes for header inspection
    final headerBytes = await file.openRead(0, 32).first;
    return validateBytes(Uint8List.fromList(headerBytes), totalLength: length);
  }

  /// Validates magic bytes directly from an in-memory buffer.
  static FileValidationResult validateBytes(
    Uint8List bytes, {
    int? totalLength,
  }) {
    final length = totalLength ?? bytes.length;
    if (bytes.length < 8) {
      throw const UnsupportedFormatException(
        'File header too short to verify format.',
      );
    }

    // Check PDF
    if (_matches(bytes, _pdfMagic)) {
      return FileValidationResult(
        fileType: ValidatedFileType.pdf,
        mimeType: 'application/pdf',
        extension: 'pdf',
        byteLength: length,
      );
    }

    // Check PNG
    if (_matches(bytes, _pngMagic)) {
      return FileValidationResult(
        fileType: ValidatedFileType.png,
        mimeType: 'image/png',
        extension: 'png',
        byteLength: length,
      );
    }

    // Check JPEG
    if (_matches(bytes, _jpegMagic)) {
      return FileValidationResult(
        fileType: ValidatedFileType.jpeg,
        mimeType: 'image/jpeg',
        extension: 'jpg',
        byteLength: length,
      );
    }

    throw const UnsupportedFormatException(
      'Unsupported or invalid file format. Only PDF, JPG, and PNG files are permitted in the Vault.',
    );
  }

  static bool _matches(Uint8List data, List<int> magic) {
    if (data.length < magic.length) return false;
    for (int i = 0; i < magic.length; i++) {
      if (data[i] != magic[i]) return false;
    }
    return true;
  }
}
