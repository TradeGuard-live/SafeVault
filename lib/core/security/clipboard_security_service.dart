import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// Service providing ephemeral clipboard protection for sensitive credentials
/// (passwords, usernames, bank account numbers).
///
/// NOTE ON SECURITY LIMITATIONS:
/// Android's clipboard is a shared system resource accessible to background apps
/// and clipboard managers with appropriate permissions. While this service
/// automatically clears the clipboard after a configurable timeout (default 30s)
/// and upon vault locking, it CANNOT guarantee protection if another application
/// or keylogger reads the clipboard while the secret is active. Users are advised
/// to paste credentials promptly.
class ClipboardSecurityService {
  static final ClipboardSecurityService instance = ClipboardSecurityService._();
  ClipboardSecurityService._();

  Timer? _clearTimer;
  String? _lastSensitiveCopied;

  /// Copies sensitive text to the system clipboard and schedules an automatic
  /// wipe after [duration] (default 30 seconds).
  Future<void> copySensitive(
    BuildContext context, {
    required String text,
    required String label,
    Duration duration = const Duration(seconds: 30),
  }) async {
    _clearTimer?.cancel();
    _lastSensitiveCopied = text;

    await Clipboard.setData(ClipboardData(text: text));

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(
                Icons.timer_outlined,
                color: AppColors.primaryTeal,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$label copied. Clipboard will clear in ${duration.inSeconds} seconds.',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 3),
          backgroundColor: AppColors.darkCardElevated,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    _clearTimer = Timer(duration, () async {
      await _wipeIfMatch();
    });
  }

  /// Wipes clipboard immediately if it still contains the sensitive text.
  Future<void> clearSensitiveClipboard() async {
    _clearTimer?.cancel();
    _clearTimer = null;
    await _wipeIfMatch();
  }

  Future<void> _wipeIfMatch() async {
    if (_lastSensitiveCopied == null) return;
    try {
      final currentData = await Clipboard.getData(Clipboard.kTextPlain);
      if (currentData != null && currentData.text == _lastSensitiveCopied) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
    } catch (_) {
      // In case clipboard access fails in background
    } finally {
      _lastSensitiveCopied = null;
    }
  }
}
