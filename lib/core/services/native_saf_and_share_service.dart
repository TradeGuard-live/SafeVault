import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../security/vault_session.dart';

/// Representation of a file staged through Android Storage Access Framework (SAF)
/// or Android Sharesheet.
class SafFileItem {
  final String path;
  final String name;
  final int size;
  final String mimeType;

  const SafFileItem({
    required this.path,
    required this.name,
    required this.size,
    required this.mimeType,
  });

  factory SafFileItem.fromMap(Map<dynamic, dynamic> map) {
    return SafFileItem(
      path: map['path'] as String? ?? '',
      name: map['name'] as String? ?? 'document',
      size: (map['size'] as num?)?.toInt() ?? 0,
      mimeType: map['mimeType'] as String? ?? 'application/octet-stream',
    );
  }

  Map<String, dynamic> toMap() {
    return {'path': path, 'name': name, 'size': size, 'mimeType': mimeType};
  }

  bool get isPdf =>
      mimeType.contains('pdf') || name.toLowerCase().endsWith('.pdf');
  bool get isImage =>
      mimeType.startsWith('image/') ||
      name.toLowerCase().endsWith('.jpg') ||
      name.toLowerCase().endsWith('.jpeg') ||
      name.toLowerCase().endsWith('.png');
}

/// Service interfacing with native Android Kotlin Storage Access Framework (SAF)
/// and Android Sharesheet for 100% offline document import and outgoing sharing.
class NativeSafAndShareService {
  static const MethodChannel _channel = MethodChannel(
    'com.vault.native/saf_and_sharing',
  );

  static final NativeSafAndShareService instance = NativeSafAndShareService._();
  NativeSafAndShareService._() {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  VaultSession? _session;

  /// Attaches the active VaultSession so system activities (SAF, Sharesheet)
  /// can coordinate lifecycle states and avoid false auto-locks.
  void attachSession(VaultSession session) {
    _session = session;
  }

  final _incomingShareStreamController =
      StreamController<List<SafFileItem>>.broadcast();
  Stream<List<SafFileItem>> get incomingShareStream =>
      _incomingShareStreamController.stream;

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onIncomingShareReceived') {
      final rawList = call.arguments as List<dynamic>? ?? [];
      final items = rawList
          .whereType<Map<dynamic, dynamic>>()
          .map((m) => SafFileItem.fromMap(m))
          .toList();
      if (items.isNotEmpty) {
        _incomingShareStreamController.add(items);
      }
    }
  }

  /// Launches the native Android Storage Access Framework picker (`ACTION_OPEN_DOCUMENT`).
  /// Displays the full Android system picker: Recent, Images, Documents, Downloads,
  /// Gallery, My Files, Drive, etc.
  Future<List<SafFileItem>> pickDocuments({
    bool allowMultiple = true,
    List<String>? mimeTypes,
  }) async {
    if (!Platform.isAndroid) {
      return [];
    }

    _session?.beginSystemActivity('SAF_OPEN_DOCUMENT');
    try {
      final effectiveMimeTypes =
          mimeTypes ??
          const ['application/pdf', 'image/jpeg', 'image/jpg', 'image/png'];

      final result = await _channel.invokeMethod<List<dynamic>>(
        'openDocument',
        {'allowMultiple': allowMultiple, 'mimeTypes': effectiveMimeTypes},
      );

      if (result == null) return [];

      return result
          .whereType<Map<dynamic, dynamic>>()
          .map((m) => SafFileItem.fromMap(m))
          .where((item) => item.path.isNotEmpty && File(item.path).existsSync())
          .toList();
    } catch (e) {
      debugPrint('NativeSafAndShareService: pickDocuments failed: $e');
      return [];
    } finally {
      Future.microtask(() {
        _session?.endSystemActivity();
      });
    }
  }

  /// Launches Android's native `ACTION_CREATE_DOCUMENT` picker, allowing the user
  /// to choose where to save an exported file (e.g. extracted `.txt`).
  Future<bool> createAndSaveDocument({
    required String defaultFileName,
    required String content,
    String mimeType = 'text/plain',
  }) async {
    if (!Platform.isAndroid) return false;

    _session?.beginSystemActivity('SAF_CREATE_DOCUMENT');
    try {
      final bytes = utf8.encode(content);
      final result = await _channel.invokeMethod<bool>('createDocument', {
        'defaultFileName': defaultFileName,
        'mimeType': mimeType,
        'contentBytes': Uint8List.fromList(bytes),
      });
      return result ?? false;
    } catch (e) {
      debugPrint('NativeSafAndShareService: createAndSaveDocument failed: $e');
      return false;
    } finally {
      Future.microtask(() {
        _session?.endSystemActivity();
      });
    }
  }

  /// Shares decrypted files via Android native Sharesheet using `FileProvider`
  /// and `FLAG_GRANT_READ_URI_PERMISSION`.
  Future<bool> shareFiles({
    required List<String> filePaths,
    required List<String> mimeTypes,
    String title = 'Share via Vault',
  }) async {
    if (!Platform.isAndroid) return false;

    _session?.beginSystemActivity('SHARESHEET_FILES');
    try {
      final result = await _channel.invokeMethod<bool>('shareFiles', {
        'filePaths': filePaths,
        'mimeTypes': mimeTypes,
        'title': title,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('NativeSafAndShareService: shareFiles failed: $e');
      return false;
    } finally {
      Future.microtask(() {
        _session?.endSystemActivity();
      });
    }
  }

  /// Shares plain text via Android Sharesheet (`ACTION_SEND`).
  Future<bool> shareText({
    required String text,
    String title = 'Share Text',
  }) async {
    if (!Platform.isAndroid) return false;

    _session?.beginSystemActivity('SHARESHEET_TEXT');
    try {
      final result = await _channel.invokeMethod<bool>('shareText', {
        'text': text,
        'title': title,
      });
      return result ?? false;
    } catch (e) {
      debugPrint('NativeSafAndShareService: shareText failed: $e');
      return false;
    } finally {
      Future.microtask(() {
        _session?.endSystemActivity();
      });
    }
  }

  /// Checks for any incoming shared files that launched or entered the app.
  Future<List<SafFileItem>> getPendingIncomingShares() async {
    if (!Platform.isAndroid) return [];

    try {
      final result = await _channel.invokeMethod<List<dynamic>>(
        'getPendingIncomingShare',
      );
      if (result == null) return [];
      return result
          .whereType<Map<dynamic, dynamic>>()
          .map((m) => SafFileItem.fromMap(m))
          .where((item) => item.path.isNotEmpty && File(item.path).existsSync())
          .toList();
    } catch (e) {
      debugPrint(
        'NativeSafAndShareService: getPendingIncomingShares failed: $e',
      );
      return [];
    }
  }

  /// Cleans up the native staging directory and clears pending shared file list.
  Future<void> clearPendingIncomingShares() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('clearPendingIncomingShare');
    } catch (e) {
      debugPrint(
        'NativeSafAndShareService: clearPendingIncomingShares failed: $e',
      );
    }
  }
}
