class AppConstants {
  static const String appName = 'Vault';
  static const String appTagline = 'Personal Document Vault';
  static const String appVersion = '1.0.0';

  // Security & Crypto
  static const String dbName = 'vault_secure.db';
  static const List<int> fileHeaderMagic = [0x56, 0x41, 0x55, 0x4C, 0x54]; // 'VAULT'
  static const int currentEncryptionVersion = 1;
  static const int masterKeyLengthBytes = 32; // 256 bits
  static const int gcmNonceLengthBytes = 12; // 96 bits
  static const int gcmTagLengthBytes = 16; // 128 bits
  static const int pbkdf2Iterations = 100000;
  static const int pbkdf2SaltLength = 32;

  // File Constraints
  static const int maxFileSizeBytes = 50 * 1024 * 1024; // 50 MB
  static const List<String> supportedExtensions = ['pdf', 'jpg', 'jpeg', 'png'];

  // Lockout & Auto-lock (Mandatory 6-digit PIN)
  static const int minPinLength = 6;
  static const int maxPinLength = 6;
  static const int pinLength = 6;
  static const int maxFailedAttemptsBeforeDelay = 3;
  static const int defaultTrashRetentionDays = 30;
  static const int clipboardAutoClearSeconds = 30;

  // Notification Channel
  static const String notificationChannelId = 'vault_document_expiry';
  static const String notificationChannelName = 'Document Expiry Reminders';
  static const String notificationChannelDesc = 'Alerts for upcoming and expired document validity dates.';
}

