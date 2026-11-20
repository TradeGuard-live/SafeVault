import 'package:flutter/foundation.dart';

/// Manages the ephemeral, short-lived state between Factor 1 (Biometric)
/// and Factor 2 (Six-digit PIN) during the mandatory two-factor unlock sequence.
///
/// Under no circumstances is the decrypted master key reconstructed or stored
/// here; this coordinator only temporarily holds the decrypted biometric share
/// S_bio in memory for at most [expiryDuration] (default 60 seconds) while the
/// user enters their six-digit PIN on the subsequent screen.
///
/// If the transaction is cancelled, times out, or the PIN fails, all ephemeral
/// buffers are immediately overwritten with zeros.
class TwoFactorAuthCoordinator extends ChangeNotifier {
  Uint8List? _ephemeralBioShare;
  DateTime? _bioAuthenticatedTime;
  static const Duration expiryDuration = Duration(seconds: 60);

  bool get hasActiveBiometricVerification {
    if (_ephemeralBioShare == null || _bioAuthenticatedTime == null) {
      return false;
    }
    final elapsed = DateTime.now().difference(_bioAuthenticatedTime!);
    if (elapsed > expiryDuration) {
      cancelTransaction();
      return false;
    }
    return true;
  }

  /// Records successful Factor 1 (Biometric) verification and stores the
  /// ephemeral 32-byte biometric key share S_bio.
  void recordBiometricSuccess(Uint8List bioShare) {
    cancelTransaction(); // clear any prior state
    _ephemeralBioShare = Uint8List.fromList(bioShare);
    _bioAuthenticatedTime = DateTime.now();
    notifyListeners();
  }

  /// Consumes and returns the ephemeral biometric share for Factor 2 verification.
  /// Automatically zeroes the coordinator's copy to prevent retention.
  Uint8List? consumeBiometricShare() {
    if (!hasActiveBiometricVerification) {
      cancelTransaction();
      return null;
    }
    final share = _ephemeralBioShare;
    _ephemeralBioShare = null;
    _bioAuthenticatedTime = null;
    notifyListeners();
    return share;
  }

  /// Cancels the in-progress 2FA transaction and zeroes out memory buffers.
  void cancelTransaction() {
    if (_ephemeralBioShare != null) {
      _ephemeralBioShare!.fillRange(0, _ephemeralBioShare!.length, 0);
      _ephemeralBioShare = null;
    }
    _bioAuthenticatedTime = null;
    notifyListeners();
  }
}
