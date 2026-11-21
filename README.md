# Vault — Personal Document Vault & Secure Document Manager

[![Platform](https://img.shields.io/badge/Platform-Android-green.svg)](https://flutter.dev)
[![Offline](https://img.shields.io/badge/Network-100%25%20Offline-blue.svg)](#)
[![Security](https://img.shields.io/badge/Encryption-AES--256--GCM-teal.svg)](#)
[![2FA](https://img.shields.io/badge/Auth-Mandatory%202FA-success.svg)](#)
[![License](https://img.shields.io/badge/License-Apache%202.0-orange.svg)](#)

**Vault** is a privacy-first, high-assurance personal document safe built using **Flutter** and native **Android Kotlin**. It enables users to securely store, organize, scan, search, and manage sensitive personal documents, passwords, and banking references entirely on their Android devices with mathematical privacy guarantees.

---

## 🛡️ Core Security Architecture

Vault does not rely on cloud services, remote backends, or third-party tracking APIs. Every byte of sensitive data is encrypted before permanent storage.

### 1. Mandatory Two-Factor Authentication (2FA)
- **Factor 1: Biometric Verification**: AndroidX `BiometricPrompt` with hardware-backed StrongBox / TEE validation.
- **Factor 2: Six-Digit Cryptographic Vault Password**: Derived using PBKDF2-HMAC-SHA256 with 100,000 iterations and a unique 32-byte salt.
- Both factors must succeed in the same unlock sequence. No single-factor fallback is permitted.

### 2. Cryptographic Architecture
- **Document & File Encryption**: AES-256 in Galois/Counter Mode (**AES-256-GCM**).
- **Authentication Tags**: 128-bit MAC tags verify ciphertext authenticity and prevent tampering.
- **Initialization Vectors**: Cryptographically secure 96-bit (12-byte) nonces generated per encryption operation.
- **Master Key**: Random 256-bit Vault Master Key stored inside `FlutterSecureStorage` (backed by Android Keystore encrypted shared preferences with `resetOnError: false`).
- **Encrypted Companion Text**: Extracted plain text is encrypted under AES-256-GCM and stored as a companion `.txt.enc` file linked to the original document.

### 3. Device & OS Privacy
- **Android `FLAG_SECURE`**: Enabled by default to block screenshots, prevent screen recordings, and mask app previews in the Android Recent Tasks switcher.
- **Android Backup Disabled**: `android:allowBackup="false"` and `data_extraction_rules.xml` exclude all storage domains from cloud backup and device transfer.
- **Zero Network Permissions**: The `INTERNET` and `ACCESS_NETWORK_STATE` permissions are explicitly stripped from the release binary via `tools:node="remove"`.
- **Zero Audio/External Storage Permissions**: `RECORD_AUDIO`, `READ_EXTERNAL_STORAGE`, and `WRITE_EXTERNAL_STORAGE` stripped from manifest merger.
- **Zero-Trust Network Config**: `network_security_config.xml` blocks cleartext and trusts zero CAs.

---

## 📱 Key Features

### 1. Native Android Storage Access Framework (SAF)
- Full integration with Android's native system file picker via `ACTION_OPEN_DOCUMENT`.
- Access Recent files, Downloads, Images, Documents, Gallery, My Files, and OneDrive.
- Multi-file selection (`EXTRA_ALLOW_MULTIPLE`).
- Streaming `content://` URIs with 8KB buffer for large files.
- Export companion `.txt` files directly to user-chosen storage locations via `ACTION_CREATE_DOCUMENT`.

### 2. Android Sharesheet Integration (Incoming & Outgoing)
- **Incoming Shares (`ACTION_SEND` & `ACTION_SEND_MULTIPLE`)**:
  - Share PDFs or images from WhatsApp, Gmail, Chrome, or Gallery directly into Vault.
  - Held securely in staging cache until mandatory 2FA unlock succeeds.
  - Premium `IncomingSharePreviewScreen` displays thumbnails, file types, editable names, and category assignment.
- **Outgoing Sharing (`FileProvider`)**:
  - Granular sharing modal: Share Original Document, Share Extracted Text, Share Selected Fields, or Share Both.
  - Ephemeral decrypted copies created in private cache with randomized names and read-only permissions (`FLAG_GRANT_READ_URI_PERMISSION`).
  - Automatically zeroed and wiped on vault lock and next app launch.

### 3. 100% Offline OCR & Text Extraction
- Bundled Tesseract models inside APK assets:
  - English (`eng.traineddata`)
  - Hindi / Devanagari (`hin.traineddata`)
  - Gujarati (`guj.traineddata`)
- **Searchable PDF Detection**: Extracts embedded text layers page-by-page.
- **Scanned PDF Rasterization**: Renders image-only pages and executes offline OCR.
- **Image Optimization**: EXIF rotation correction and contrast optimization.
- Fully operational in airplane mode.

### 4. Smart Document Classification & Structured Extraction
- Automatic category recognition:
  - Personal Identity: Aadhaar Card, PAN Card, Voter ID, Passport, Birth Certificate.
  - Vehicle Documents: Driving Licence, Vehicle RC Book, PUC Certificate, Vehicle Insurance.
  - Financial, Education, Property, Medical, and General Documents.
- Field extractors with confidence badges (High, Medium, Low):
  - Aadhaar (Masked: `XXXX XXXX 1234`), PAN (`ABCDE1234F`), DL (`DL0420110012345`), RC (`MH12AB1234`), Passport.
  - Never invents missing fields.

### 5. Smart Document Details Screen (4 Tabs)
- **Preview Tab**: High-resolution decrypted document rendering and page navigation.
- **Extracted Information Tab**: Structured field cards with confidence ratings, individual copy buttons, "Copy All", manual edit capabilities, and OCR language re-run.
- **Full Text Tab**: Full extracted text with in-document search, live match highlighting, font-size adjustment (`A-`/`A+`), text wrapping toggle, and 2FA-protected "Copy Full Text".
- **Activity Tab**: Local chronological audit log of all document operations.

### 6. Clipboard Management
- 30-second auto-clear timer with floating countdown feedback.
- Content verification before clearing (avoids wiping newer user clipboard content).

---

## 🏗️ Architecture & Project Structure

```
lib/
  main.dart                               # Entry point, root lifecycle & touch tracking
  core/
    constants/                            # App constants & default categories
    theme/                                # RupeeFlow 4-Theme system
    security/                             # AES-256-GCM, 2FA Coordinator, PIN, Biometrics, VaultSession
    database/                             # SQLite schema (v3) with extractions & structured fields
    storage/                              # Encrypted file storage & ephemeral cache scrubber
    services/                             # Native SAF and Share MethodChannel bridge
    notifications/                        # Local notifications & reminder scheduler
    routes/                               # GoRouter navigation & auth route guards
    utils/                                # Date formatting, masking, file signatures
  features/
    onboarding/                           # Welcome, Setup, Splash
    authentication/                       # PIN Unlock, Biometric Unlock, 2FA Dialogs
    dashboard/                            # Home Dashboard, Main Shell
    documents/                            # Details (4 tabs), Add, Viewer, Share Sheet, Incoming Preview
    scanner/                              # Camera Scanner, Image Processing, PDF Compilation
    ocr/                                  # Offline OCR, Smart Classifier, Field Extractor
    passwords/                            # Password Manager & Security Analyzer
    bank_vault/                           # Bank Account Vault
    categories/                           # Category Management
    favorites/                            # Favorite Documents
    expiry/                               # Expiry Reminders Dashboard
    timeline/                             # Audit Activity History
    trash/                                # Soft-Deletion & Recovery
    search/                               # Full-text Offline Search
```

---

## 🚀 Environment, Building & Testing

### SDK & Build Requirements
- **Flutter SDK**: 3.47.6 (channel stable)
- **Dart SDK**: 3.13.5 (environment: `^3.13.5`)
- **Android Target**: Compile SDK 34, Target SDK 34, Min SDK 26 (Android 8.0+)
- **Gradle**: 8.4 / AGP 8.3.2

### Run Tests
```bash
flutter test
```
All automated tests pass (100% success rate across cryptography, key derivation, 2FA, SAF, OCR schemas, and security gates).

### Static Analysis
```bash
flutter analyze
```
0 issues found (clean static analysis with sound null safety).

### Build Hardened Release APK
```bash
flutter build apk --release
```
Output: `build/app/outputs/flutter-apk/app-release.apk`
- R8 minification & resource shrinking enabled.
- All network and recording permissions stripped.

---

## 📜 Official Audit & Security Deliverables
- [SAFEVAULT_AUDIT.md](SAFEVAULT_AUDIT.md) — Comprehensive defensive audit across 16 structured dimensions (P0-P3 classifications).
- [SAFEVAULT_FIX_REPORT.md](SAFEVAULT_FIX_REPORT.md) — Exhaustive technical implementation details of all architectural remediations.
- [SAFEVAULT_SECURITY_REPORT.md](SAFEVAULT_SECURITY_REPORT.md) — Cryptographic architecture, Android Keystore StrongBox integration, and penetration audit.
- [SAFEVAULT_TEST_REPORT.md](SAFEVAULT_TEST_REPORT.md) — Full automated test suite and physical hardware verification matrix.
- [SAFEVAULT_USER_GUIDE.md](SAFEVAULT_USER_GUIDE.md) — User onboarding, feature walkthrough, and privacy manual.
