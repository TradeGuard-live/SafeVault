# Vault — Personal Document Vault & Secure Document Manager

[![Platform](https://img.shields.io/badge/Platform-Android-green.svg)](https://flutter.dev)
[![Offline](https://img.shields.io/badge/Network-100%25%20Offline-blue.svg)](#)
[![Security](https://img.shields.io/badge/Encryption-AES--256--GCM-teal.svg)](#)
[![License](https://img.shields.io/badge/License-Apache%202.0-orange.svg)](#)

**Vault** is a privacy-first, military-grade personal document safe built using **Flutter** and native **Android Kotlin**. It enables users to scan, store, organize, search, and manage sensitive personal and legal documents entirely on their Android devices with mathematical privacy guarantees.

---

## 🛡️ Core Security Architecture

Vault does not rely on cloud services, remote backends, or third-party tracking APIs. Every byte of sensitive data is encrypted before permanent storage.

### 1. Cryptographic Architecture
- **Document & File Encryption**: AES-256 in Galois/Counter Mode (**AES-256-GCM**).
- **Authentication Tags**: 128-bit MAC tags verify ciphertext authenticity and prevent tampering.
- **Initialization Vectors**: Cryptographically secure 96-bit (12-byte) nonces generated per encryption operation.
- **Key Derivation (PBKDF2)**: User application PIN is derived into a 256-bit Key Encryption Key (KEK) using PBKDF2 with HMAC-SHA256 and **100,000 iterations** with a unique 32-byte salt.
- **Dual-Unwrapping Key Hierarchy**:
  1. A random 256-bit **Vault Master Key** is generated on initial setup.
  2. One wrapped copy is protected via the PIN-derived KEK.
  3. An optional wrapped copy is protected via a hardware-backed **Android Keystore** biometric key.
  4. The master key is held in an ephemeral in-memory session only while the vault is unlocked.
  5. In-memory buffers are securely zeroed out (`buffer.fillRange(0, length, 0)`) upon locking or auto-lock timeout.

### 2. Device & OS Privacy
- **Android `FLAG_SECURE`**: The application window has `FLAG_SECURE` enabled by default to block screenshots, prevent screen recordings, and mask app previews in the Android Recent Tasks switcher.
- **Android Automatic Cloud Backup Disabled**: `android:allowBackup="false"` and `android:fullBackupContent="false"` in `AndroidManifest.xml` prevent unencrypted document leakage via Google Drive device backups or adb backup transfers.
- **Zero Network Permissions**: The `INTERNET` and `ACCESS_NETWORK_STATE` permissions are explicitly removed with `tools:node="remove"`.
- **Private Scoped Internal Storage**: Files are stored in application-private directories (`/data/data/com.vault.vault/app_flutter/vault_files/`) using non-identifying UUID filenames.

---

## 📱 Features

1. **First-Time Security Setup**:
   - Welcome onboarding explaining local offline encryption.
   - Dedicated application PIN creation (independent of device passcode).
   - Biometric authentication enrollment (Fingerprint & Face).
2. **Document Management**:
   - Full CRUD support with category tagging.
   - Default Categories: Personal Identity, Vehicle Documents, Financial, Education, Property, Medical, Other.
   - Extensible Custom Categories: create, rename, and safely delete custom categories (documents automatically re-assigned to "Other").
   - Multi-page and front/back support for identity cards.
   - Sensitive metadata masking (tap eye to reveal document numbers).
3. **On-Device Document Scanner**:
   - Live camera preview with framing guidelines and flash toggle.
   - Multi-page capture with bottom thumbnail filmstrip.
   - Interactive document editing: 90° rotation, cropping, and image enhancement filters (Original, Grayscale, High Contrast, Document B&W thresholding).
   - Multi-page compilation to standard A4 PDF or JPEG document.
4. **100% Offline OCR (Tesseract)**:
   - On-device text recognition with **bundled traineddata models** included directly in the APK assets:
     - `eng.traineddata` (English)
     - `hin.traineddata` (Hindi)
     - `guj.traineddata` (Gujarati)
   - Intelligent regex extraction for document numbers (Aadhaar, PAN, DL, Passport, Voter ID), dates, owner names, and issuing authorities.
   - OCR review screen allowing manual verification before saving.
5. **Expiry Reminders & Local Notifications**:
   - Scheduled local notifications: 30 days, 15 days, 7 days, 1 day, and on expiration date.
   - Reboot-safe scheduling with `ScheduledNotificationBootReceiver`.
   - Expiry Dashboard categorizing Expired, Critical (≤7d), Upcoming (30d), All Upcoming, and No Expiry.
6. **Timeline & Activity History**:
   - Local chronological audit log of all document operations (additions, scans, edits, favorites, trash moves, purges).
7. **Trash & Recovery**:
   - Two-stage soft deletion with configurable retention periods (7, 15, 30, 60 days).
   - Permanent deletion securely overwrites and purges files from storage.
8. **Instant Offline Search & Filtering**:
   - Instant search across decrypted names, numbers, owners, authorities, and tags.

---

## 🏗️ Architecture & Project Structure

```
lib/
  main.dart                               # Entry point, FLAG_SECURE & notification init
  core/
    constants/                            # App constants & default categories
    theme/                                # Material 3 Fintech theme (Dark & Light)
    security/                             # AES-256-GCM, PBKDF2, PIN, Biometrics, VaultSession
    database/                             # SQLite encrypted schema & helpers
    storage/                              # Encrypted file storage & atomic write management
    notifications/                        # Local notifications & reminder scheduler
    routes/                               # GoRouter navigation & auth route guards
    utils/                                # Date formatting, masking, file signatures
    widgets/                              # PinPad, VaultScaffold, StatusBadge, EmptyState
  features/
    onboarding/                           # Splash, Welcome, Initial Security Setup
    authentication/                       # PIN Unlock, Biometric Unlock, Session Providers
    dashboard/                            # Home Dashboard, Main Navigation Shell
    documents/                            # All Docs, Category Docs, Details, Add, Viewer
    scanner/                              # Camera Scanner, Image Processing, PDF Compilation
    ocr/                                  # Offline Tesseract OCR & Extractor Review
    categories/                           # Custom Category Management
    favorites/                            # Favorite Documents
    expiry/                               # Expiry Reminders Dashboard
    timeline/                             # Audit Activity History
    trash/                                # Soft-Deletion & Recovery
    search/                               # Full-text Offline Search
    settings/                             # Security Settings, Storage Info, About & Privacy
```

---

## 🚀 Building & Running

### Prerequisites
- Flutter SDK 3.47+
- Android SDK 34+ (API Level 24 minimum)
- Java 17+

### Run Debug
```bash
flutter pub get
flutter run
```

### Build Release APK
```bash
flutter build apk --release
```
Output path: `build/app/outputs/flutter-apk/app-release.apk`

---

## 📜 Licenses
- **Tesseract OCR Language Models**: Licensed under the **Apache License 2.0** (Copyright Google LLC and Tesseract OCR contributors).
- Application source code licensed under the MIT License.
