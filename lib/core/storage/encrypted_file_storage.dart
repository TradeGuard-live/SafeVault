import 'dart:io';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../errors/exceptions.dart';
import '../security/encryption_service.dart';

class EncryptedFileStorage {
  final EncryptionService _encryptionService;
  final Uuid _uuid = const Uuid();

  EncryptedFileStorage({EncryptionService? encryptionService})
      : _encryptionService = encryptionService ?? EncryptionService();

  Future<Directory> get _filesDirectory async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(join(appDir.path, 'vault_files'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> get _thumbnailsDirectory async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(join(appDir.path, 'vault_thumbnails'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<Directory> get _tempDirectory async {
    final cacheDir = await getTemporaryDirectory();
    final dir = Directory(join(cacheDir.path, 'vault_ephemeral'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Encrypts and writes raw bytes to a non-identifying file in private internal storage.
  /// Uses atomic write (write to temp file then rename) to prevent incomplete files.
  Future<String> saveEncryptedFile({
    required Uint8List plainBytes,
    required SecretKey masterKey,
  }) async {
    try {
      final encryptedBytes = await _encryptionService.encryptBytes(plainBytes, masterKey);
      final filesDir = await _filesDirectory;
      final uniqueFileName = '${_uuid.v4()}.enc';
      final finalPath = join(filesDir.path, uniqueFileName);
      final tempPath = join(filesDir.path, '$uniqueFileName.tmp');

      final tempFile = File(tempPath);
      await tempFile.writeAsBytes(encryptedBytes, flush: true);
      await tempFile.rename(finalPath);

      return finalPath;
    } catch (e) {
      throw StorageException('Failed to securely store document file.', e);
    }
  }

  /// Encrypts and saves a generated thumbnail image.
  Future<String> saveEncryptedThumbnail({
    required Uint8List thumbnailBytes,
    required SecretKey masterKey,
  }) async {
    try {
      final encryptedBytes = await _encryptionService.encryptBytes(thumbnailBytes, masterKey);
      final thumbsDir = await _thumbnailsDirectory;
      final uniqueFileName = 'thumb_${_uuid.v4()}.enc';
      final finalPath = join(thumbsDir.path, uniqueFileName);
      final tempPath = join(thumbsDir.path, '$uniqueFileName.tmp');

      final tempFile = File(tempPath);
      await tempFile.writeAsBytes(encryptedBytes, flush: true);
      await tempFile.rename(finalPath);

      return finalPath;
    } catch (e) {
      throw StorageException('Failed to securely store document thumbnail.', e);
    }
  }

  /// Reads and decrypts an encrypted file directly into in-memory bytes.
  /// Authentication tag is verified. Throws if file is corrupted or tampered.
  Future<Uint8List> readDecryptedFile({
    required String filePath,
    required SecretKey masterKey,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw const StorageException('Encrypted file not found on device.');
    }

    try {
      final encryptedBytes = await file.readAsBytes();
      return await _encryptionService.decryptBytes(encryptedBytes, masterKey);
    } catch (e) {
      if (e is VaultException) rethrow;
      throw FileCorruptedException('Failed to decrypt document file.', e);
    }
  }

  /// Creates an ephemeral temporary decrypted file for native viewers (e.g. PDF view).
  /// Must be wiped and deleted when viewing terminates.
  Future<File> createEphemeralDecryptedCopy({
    required String encryptedFilePath,
    required String fileExtension,
    required SecretKey masterKey,
  }) async {
    final plainBytes = await readDecryptedFile(filePath: encryptedFilePath, masterKey: masterKey);
    final tempDir = await _tempDirectory;
    final tempFile = File(join(tempDir.path, 'view_${_uuid.v4()}.$fileExtension'));
    await tempFile.writeAsBytes(plainBytes, flush: true);
    return tempFile;
  }

  /// Securely deletes a file from disk by overwriting with zeros before unlinking.
  Future<void> securelyDeleteFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        final length = await file.length();
        // Overwrite with zeros to prevent flash memory remnants
        if (length > 0) {
          final zeros = Uint8List(length > 4096 ? 4096 : length);
          final raf = await file.open(mode: FileMode.write);
          int written = 0;
          while (written < length) {
            final toWrite = (length - written) > zeros.length ? zeros.length : (length - written);
            await raf.writeFrom(zeros, 0, toWrite);
            written += toWrite;
          }
          await raf.flush();
          await raf.close();
        }
        await file.delete();
      }
    } catch (e) {
      // Best effort deletion
      try {
        final f = File(filePath);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  /// Wipes all ephemeral decrypted files in the temporary directory.
  Future<void> wipeEphemeralFiles() async {
    try {
      final tempDir = await _tempDirectory;
      if (await tempDir.exists()) {
        final entities = await tempDir.list().toList();
        for (final entity in entities) {
          if (entity is File) {
            await securelyDeleteFile(entity.path);
          }
        }
      }
    } catch (_) {}
  }

  /// Computes storage consumption breakdown in bytes.
  Future<StorageBreakdown> getStorageBreakdown() async {
    int documentsSize = 0;
    int thumbnailsSize = 0;
    int documentsCount = 0;

    final filesDir = await _filesDirectory;
    if (await filesDir.exists()) {
      await for (final file in filesDir.list()) {
        if (file is File) {
          documentsSize += await file.length();
          documentsCount++;
        }
      }
    }

    final thumbsDir = await _thumbnailsDirectory;
    if (await thumbsDir.exists()) {
      await for (final file in thumbsDir.list()) {
        if (file is File) {
          thumbnailsSize += await file.length();
        }
      }
    }

    final appDir = await getApplicationDocumentsDirectory();
    final dbFile = File(join(appDir.path, 'vault_secure.db'));
    int databaseSize = 0;
    if (await dbFile.exists()) {
      databaseSize = await dbFile.length();
    }

    return StorageBreakdown(
      documentsBytes: documentsSize,
      thumbnailsBytes: thumbnailsSize,
      databaseBytes: databaseSize,
      totalBytes: documentsSize + thumbnailsSize + databaseSize,
      encryptedFilesCount: documentsCount,
    );
  }
}

class StorageBreakdown {
  final int documentsBytes;
  final int thumbnailsBytes;
  final int databaseBytes;
  final int totalBytes;
  final int encryptedFilesCount;

  const StorageBreakdown({
    required this.documentsBytes,
    required this.thumbnailsBytes,
    required this.databaseBytes,
    required this.totalBytes,
    required this.encryptedFilesCount,
  });

  String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String get formattedTotal => formatBytes(totalBytes);
  String get formattedDocuments => formatBytes(documentsBytes);
  String get formattedThumbnails => formatBytes(thumbnailsBytes);
  String get formattedDatabase => formatBytes(databaseBytes);
}

