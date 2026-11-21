/// Core exceptions for the Vault application.
class VaultException implements Exception {
  final String message;
  final Object? cause;

  const VaultException(this.message, [this.cause]);

  @override
  String toString() => message;
}

class VaultSecurityException extends VaultException {
  const VaultSecurityException(super.message, [super.cause]);
}

class DecryptionFailedException extends VaultSecurityException {
  const DecryptionFailedException([
    super.message =
        'Failed to decrypt data. Key may be invalid or data was tampered with.',
    super.cause,
  ]);
}

class InvalidPinException extends VaultSecurityException {
  final int remainingAttempts;
  const InvalidPinException({
    String message = 'Invalid PIN entered.',
    this.remainingAttempts = 3,
    Object? cause,
  }) : super(message, cause);
}

class PinLockedOutException extends VaultSecurityException {
  final int lockDurationSeconds;
  const PinLockedOutException({
    required this.lockDurationSeconds,
    String message = 'Too many failed attempts. Temporary lockout active.',
    Object? cause,
  }) : super(message, cause);
}

class BiometricException extends VaultSecurityException {
  const BiometricException(super.message, [super.cause]);
}

class BiometricEnrollmentChangedException extends BiometricException {
  const BiometricEnrollmentChangedException([
    super.message =
        'Android Keystore invalidated the biometric key because device biometrics were modified in system settings. In a zero-knowledge 2-factor vault, access cannot be restored without the invalidated biometric key.',
    super.cause,
  ]);
}

class VaultLockedException extends VaultSecurityException {
  const VaultLockedException([
    super.message = 'The vault is locked. Master key is not accessible.',
    super.cause,
  ]);
}

class FileCorruptedException extends VaultException {
  const FileCorruptedException([
    super.message = 'The requested file is corrupt or has been tampered with.',
    super.cause,
  ]);
}

class UnsupportedFormatException extends VaultException {
  const UnsupportedFormatException([
    super.message = 'Unsupported file format.',
    super.cause,
  ]);
}

class StorageException extends VaultException {
  const StorageException(super.message, [super.cause]);
}

class DatabaseOperationException extends VaultException {
  const DatabaseOperationException(super.message, [super.cause]);
}
