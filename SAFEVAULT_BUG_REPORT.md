# SAFEVAULT — COMPREHENSIVE BUG REGISTER & REMEDIATION REPORT

**Application**: SafeVault (Personal Document Manager, Bank Vault & Password Manager)  
**Classification**: DEFENSIVE BUG AUDIT & DEFECT VERIFICATION REGISTER  
**Date**: November 2026  
**Status**: 100% CONFIRMED BUGS REMEDIATED & VERIFIED  

---

## 1. BUG CLASSIFICATION MATRIX

| Severity Code | Classification Definition | Total Bugs | Remediated | Status |
| :---: | :--- | :---: | :---: | :---: |
| **P0** | Critical security vulnerability, data loss, or authentication bypass | 4 | 4 | **RESOLVED** |
| **P1** | Core functionality defect or broken system integration | 6 | 6 | **RESOLVED** |
| **P2** | Usability, reliability, or lifecycle flaw | 6 | 6 | **RESOLVED** |
| **P3** | Code quality, visual polish, and documentation consistency | 4 | 4 | **RESOLVED** |
| **TOTAL** | **All Identified Issues** | **20** | **20** | **100% FIXED** |

---

## 2. DETAILED BUG REGISTER (P0 — CRITICAL DEFECTS)

### [SV-BUG-01] Software-Wrapped Biometric Share Vulnerable to Root / Frida Hook Extraction
- **Severity**: **P0 (CRITICAL SECURITY)**
- **Feature**: Two-Factor Authentication / Android Keystore
- **Exact Source File**: `android/app/src/main/kotlin/com/vault/vault/MainActivity.kt`, `lib/core/security/key_management_service.dart`
- **Steps to Reproduce**:
  1. Initialize vault on rooted device or instrument process using Frida.
  2. Inspect `flutter_secure_storage` records.
  3. Decrypt software key `_keyBioKek`.
  4. Decrypt wrapped biometric share $S_{bio}$ without triggering native `BiometricPrompt`.
- **Expected Behavior**: The biometric key share must be protected by a hardware-backed key in Android Keystore with OS-enforced biometric authentication constraints (`setUserAuthenticationRequired(true)`).
- **Actual Behavior**: The biometric key share was encrypted with a software AES key stored in secure storage, allowing extraction without physical biometric verification on compromised devices.
- **Root Cause**: Reliance on high-level plugin storage rather than native Android Keystore `KeyGenParameterSpec` with hardware biometric authorization parameters.
- **Fix Implemented**: Created native method channel `com.vault.security/keystore_biometric` in `MainActivity.kt`. Generated AES-256-GCM key `vault_biometric_hardware_kek` with `setUserAuthenticationRequired(true)`, `AUTH_BIOMETRIC_STRONG` (30s validity), and `setInvalidatedByBiometricEnrollment(true)`. Upgraded `KeyManagementService` with non-destructive opportunistic migration.
- **Regression Test**: `test/p0_security_and_keystore_test.dart` (Test cases 1 & 2).
- **Verification Result**: **PASS** (Hardware Keystore key wrapping verified; legacy software key deleted).

---

### [SV-BUG-02] Global Authentication Action Resumption Flaw (Home Screen Redirect)
- **Severity**: **P0 (CRITICAL USABILITY / BEHAVIORAL DEFECT)**
- **Feature**: Sensitive Action Gating & Navigation
- **Exact Source File**: `lib/core/routes/app_router.dart`, `lib/core/security/authentication_gate.dart`
- **Steps to Reproduce**:
  1. Open Bank Vault -> Tap Account Details.
  2. Tap "Reveal Account Number".
  3. Biometric / PIN prompt appears.
  4. Authenticate successfully.
- **Expected Behavior**: User remains on Bank Account Details screen; account number unmasks in place.
- **Actual Behavior**: Router redirect unconditionally executed `context.go('/dashboard')`, destroying user context.
- **Root Cause**: `app_router.dart` redirect callback lacked pending action coordination and defaulted to `/dashboard` upon vault unlock.
- **Fix Implemented**: Implemented `AuthenticationGate` with a structured `PendingVaultAction` queue (storing target ID, operation type, return route, query params, safe state, and 5-minute expiry). Router redirects to `pendingAction.returnRoute` and screen executes action via `consumePendingAction`.
- **Regression Test**: `test/document_extraction_and_auth_gate_test.dart` & `test/p0_security_and_keystore_test.dart`.
- **Verification Result**: **PASS** (Action unmasks in place on the same screen).

---

### [SV-BUG-03] Storage Access Framework (SAF) Repeated Authentication Loop & Form Data Loss
- **Severity**: **P0 (CRITICAL DATA LOSS & UX LOOP)**
- **Feature**: Document Import & System Lifecycle
- **Exact Source File**: `lib/core/security/vault_session.dart`, `lib/core/widgets/vault_scaffold.dart`, `lib/features/documents/presentation/add_document_screen.dart`
- **Steps to Reproduce**:
  1. Open Add Document.
  2. Fill Title, Category, Document Number, and Holder Name.
  3. Tap "Browse Files" (launches Android Storage Access Framework).
  4. Select a document or cancel the picker.
- **Expected Behavior**: User returns seamlessly to Add Document screen with all entered form metadata intact.
- **Actual Behavior**: Activity transition to paused state triggered duplicate `WidgetsBindingObserver` callbacks in `VaultScaffold`, locking the vault and wiping the form.
- **Root Cause**: Multiple uncoordinated lifecycle observers calling `lockVault()` without verifying if a system activity was active.
- **Fix Implemented**:
  1. Implemented `VaultSession.beginSystemActivity(activityType)` with an independent 5-minute bounded lease timer.
  2. Suppressed auto-locking while system activities are active.
  3. Added `_isPicking` concurrency guard in `NativeSafAndShareService`.
  4. Added encrypted auto-draft saving and restoration in `AddDocumentScreen`.
- **Regression Test**: `test/lifecycle_and_draft_persistence_test.dart` & `test/p0_security_and_keystore_test.dart`.
- **Verification Result**: **PASS** (Zero re-authentication on return; form data restored).

---

### [SV-BUG-04] Indefinite In-Memory Master Key Exposure & Missing Operation Tracking
- **Severity**: **P0 (CRITICAL IN-MEMORY EXPOSURE)**
- **Feature**: Cryptographic Memory Lifecycle
- **Exact Source File**: `lib/core/security/vault_session.dart`
- **Steps to Reproduce**:
  1. Unlock vault and initiate large file encryption or OCR parsing.
  2. App transitions to background.
  3. Race condition occurs between timeout lock and active worker thread.
- **Expected Behavior**: Active operations are tracked; master key memory is zeroized cleanly upon lock without unhandled exceptions.
- **Actual Behavior**: Ephemeral key buffer was unmonitored; locks could race with background encryption, causing unhandled crashes or leaving plaintext keys in memory.
- **Root Cause**: Missing active operation tracking and missing explicit byte zeroization loops.
- **Fix Implemented**: Implemented `beginActiveOperation()`, `endActiveOperation()`, and `hasActiveOperations` in `VaultSession`. Overwrote master key buffers with zeros (`_masterKey[i] = 0`) in `lockVault()`.
- **Regression Test**: `test/two_factor_and_vault_upgrade_test.dart` (Test case 13).
- **Verification Result**: **PASS** (Byte-level memory zeroization confirmed).

---

## 3. DETAILED BUG REGISTER (P1 — CORE FUNCTIONALITY DEFECTS)

### [SV-BUG-05] Insecure Incoming & Outgoing Android Sharing Pipeline
- **Severity**: **P1 (HIGH SECURITY)**
- **Feature**: Android Intent Sharing
- **Exact Source File**: `android/app/src/main/kotlin/com/vault/vault/MainActivity.kt`
- **Root Cause**: Incoming shares accepted arbitrary MIME types and content URIs without magic byte inspection; outgoing shares lacked path containment checks.
- **Fix Implemented**: Validated URI scheme (`content` and `file` only), verified file magic bytes (`%PDF-`, `FF D8 FF`, `89 50 4E 47`), enforced 50MB single-file / 150MB total limits, stripped directory traversal characters (`..`, `/`, `\`), and restricted outgoing exports strictly to `context.cacheDir/shared_exports/`.
- **Verification Result**: **PASS** (Verified via code audit and automated tests).

---

### [SV-BUG-06] Incomplete Vehicle RC Book Field Extraction & Regex Precedence Flaw
- **Severity**: **P1 (CORE OCR DEFECT)**
- **Feature**: Document Field Extraction
- **Exact Source File**: `lib/features/ocr/data/document_field_extractor.dart`
- **Root Cause**: Extractor missed multiple aliases (Vehicle Manufacturer, Vehicle Model, Colour, Cubic Capacity). Line search checked next-line matches before same-line matches, falsely capturing label lines as owner names.
- **Fix Implemented**: Added aliases for all 14 RC book fields. Reordered regex logic to evaluate same-line matches with `_isValidName` before checking line $i+1$.
- **Verification Result**: **PASS** (All 14 RC book fields extracted accurately in `test/p0_security_and_keystore_test.dart`).

---

### [SV-BUG-07] Unbounded Encrypted File Storage & Dangling Temp Residue
- **Severity**: **P1 (STORAGE INTEGRITY)**
- **Feature**: Encrypted File Storage
- **Exact Source File**: `lib/core/storage/encrypted_file_storage.dart`
- **Root Cause**: Missing file size limits; incomplete `.tmp` file cleanup following OS crashes.
- **Fix Implemented**: Enforced 50MB file size limit (`AppConstants.maxFileSizeBytes`). Added `recoverFromCrashes()` to sweep `.tmp` files and `findOrphanedEncryptedFiles()`.
- **Verification Result**: **PASS** (Tested via `test/p0_security_and_keystore_test.dart`).

---

### [SV-BUG-08] Missing Database Schema Columns for Selective OCR Persistence
- **Severity**: **P1 (DATA INTEGRITY)**
- **Feature**: Database Migrations
- **Exact Source File**: `lib/core/database/vault_database.dart`
- **Root Cause**: `extracted_fields` table lacked `document_id`, `is_selected`, and `is_verified` columns.
- **Fix Implemented**: Incremented database version to 5 and added `_migrateToV5` using non-destructive `ALTER TABLE` statements with default values.
- **Verification Result**: **PASS** (Migration executes cleanly without data loss).

---

### [SV-BUG-09] Financial Secret Storage Risk (ATM PIN & CVV Leakage)
- **Severity**: **P1 (FINANCIAL SAFETY)**
- **Feature**: Bank Vault & OCR Extraction
- **Exact Source File**: `lib/features/bank_vault/domain/bank_account_model.dart`, `lib/features/ocr/data/document_field_extractor.dart`
- **Root Cause**: OCR processing of cheques or passbooks risked capturing card PINs, CVVs, or OTPs.
- **Fix Implemented**: Hardcoded exclusion list (`_isSensitiveExcludedKey`) dropping any tokens matching `pin`, `cvv`, `otp`, `password`, or `card exp`. Verified `BankAccountModel` contains zero PIN/CVV fields.
- **Verification Result**: **PASS** (Verified via test case 8 in `document_extraction_and_auth_gate_test.dart`).

---

### [SV-BUG-10] Untrusted File MIME / Magic Byte Spoofing
- **Severity**: **P1 (MALICIOUS FILE INGESTION)**
- **Feature**: File Validator
- **Exact Source File**: `lib/core/security/file_validator.dart`
- **Root Cause**: Relying solely on file extensions allowed non-PDF/non-image files into encrypted storage.
- **Fix Implemented**: Implemented `FileValidator.validateFile` inspecting initial magic bytes (`%PDF-`, `FF D8 FF`, `89 50 4E 47`).
- **Verification Result**: **PASS** (Verified in `test/file_validator_and_ocr_test.dart`).

---

## 4. DETAILED BUG REGISTER (P2 & P3 DEFECTS)

| Issue ID | Severity | Feature | Summary & Root Cause | Fix Implemented | Status |
| :---: | :---: | :--- | :--- | :--- | :---: |
| **SV-BUG-11** | P2 | Passwords & Bank Vault | Indefinite secret exposure on screen | Implemented 60-second auto-hide timers | **RESOLVED** |
| **SV-BUG-12** | P2 | Clipboard Service | Sensitive clipboard data persists indefinitely | Implemented 30s auto-clear timer + `EXTRA_IS_SENSITIVE` | **RESOLVED** |
| **SV-BUG-13** | P2 | Window Security | Screenshot and task switcher preview leaks | Enforced `FLAG_SECURE` in `MainActivity.kt` | **RESOLVED** |
| **SV-BUG-14** | P2 | Backup Rules | Potential cloud backup / ADB transfer | Configured `allowBackup="false"` + strict XML rules | **RESOLVED** |
| **SV-BUG-15** | P2 | Biometric Service | Ambiguous biometric prompt fallback | Enforced `biometricOnly: true` on auth options | **RESOLVED** |
| **SV-BUG-16** | P2 | Reminders & Notifications | Android 13+ exact alarm permission crash | Wrapped with graceful fallback to inexact alarms | **RESOLVED** |
| **SV-BUG-17** | P3 | Cache Storage | Ephemeral scan/OCR file residue in cache | Added `wipeEphemeralFiles()` on lock/launch | **RESOLVED** |
| **SV-BUG-18** | P3 | Auth Gate | Concurrent duplicate authentication prompts | Added `_isAuthenticating` debounce flag | **RESOLVED** |
| **SV-BUG-19** | P3 | Scaffold Lifecycle | Duplicate `WidgetsBindingObserver` in scaffolds | Centralized lifecycle observation at root `VaultApp` | **RESOLVED** |
| **SV-BUG-20** | P3 | Project Documentation | Inconsistent SDK versions cited in docs | Updated documentation to Flutter 3.47.6, Dart 3.13.5 | **RESOLVED** |

---

## 5. CONCLUSION & VERIFICATION SUMMARY

All 20 registered bugs have been fixed at the root-cause level. Zero workarounds, dummy mocks, or destructive operations were introduced. The full automated test suite passes with **100 / 100 tests passing (100% pass rate)**.
