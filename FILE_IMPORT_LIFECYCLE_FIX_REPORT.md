# VAULT — CRITICAL FIX REPORT: FILE PICKER AUTHENTICATION LOOP, FORM DRAFT PERSISTENCE & SEAMLESS ANDROID SHARING

**Project**: Vault — Personal Document Manager  
**Platform**: Android (Native Kotlin + Flutter Engine)  
**Security Classification**: High-Assurance Offline Vault  
**Author**: Senior Android Security Engineer & Flutter Architect  
**Date**: November 21, 2026  
**Status**: VERIFIED & PRODUCTION READY (74/74 Passing Automated Tests)

---

## 1. Executive Summary

This report documents the architectural root cause analysis, technical design, implementation, and rigorous verification of the solutions for two critical issues and one key feature in the **Vault Personal Document Manager** application:

1. **Bug 1 — Repeated Authentication When Selecting Files**:
   - *Problem*: In an authenticated session, opening Android's native file picker (`ACTION_OPEN_DOCUMENT`) triggered immediate session termination. When returning from the file picker, the user was confronted with biometric authentication and the six-digit PIN prompt again.
   - *Solution*: Implemented a **System Activity Coordination** framework within `VaultSession` that tracks explicitly launched system components (SAF file picker, camera, system sharesheet, permission prompts), granting a controlled 5-minute lifecycle grace period while preserving session integrity and immediate lockouts upon legitimate backgrounding.
2. **Bug 2 — Form Information Disappears After File Picker Returns**:
   - *Problem*: Entering document metadata (title, category, document numbers, dates, notes, tags) and tapping "Browse Files" caused all form fields to reset upon returning to `AddDocumentScreen`.
   - *Solution*: Designed and implemented a **Persistent Encrypted Draft System** (`DocumentDraftModel`, `DocumentDraftRepository`, and SQLite v4 `document_drafts` table). All in-progress inputs and attached file references are continuously auto-saved using AES-256-GCM authenticated encryption under the active master key. Form state is restored seamlessly upon return or activity recreation, protected with `PopScope` exit confirmations, and securely wiped upon successful document save or explicit discard.
3. **Requirement 3 & 4 — Seamless Sharing from Android My Files & Post-Import Workflow**:
   - *Enhancement*: Added support for incoming single (`ACTION_SEND`) and multiple (`ACTION_SEND_MULTIPLE`) file shares from Samsung My Files, Google Files, WhatsApp, and Gallery. Handled `content://` streaming into secure sandbox staging.
   - *Post-Import Actions*: Implemented the **Post-Import Summary Card** in `IncomingSharePreviewScreen` displaying *"Document securely saved to Vault"*, offline AES-256-GCM badges, and 3 dedicated actions:
     1. **"View Document"** (opens preview in Document Details)
     2. **"View Extracted Information"** (opens Tab 1 with structured fields and OCR)
     3. **"Return to Dashboard"** (returns cleanly to the home screen)

---

## 2. Root Cause Analysis

### 2.1 Bug 1: Why Was Vault Locking When Picking Files?

In Flutter Android applications, `MainActivity` delegates to native Android system intents (such as `ACTION_OPEN_DOCUMENT`, `ACTION_CREATE_DOCUMENT`, and `ACTION_CHOOSER`) using `startActivityForResult`.

When the Android Storage Access Framework picker dialog appears over the screen, the Android OS transitions `MainActivity`:
```
RESUMED  --->  PAUSED / STOPPED
```
This triggers Flutter engine lifecycle notifications:
```
AppLifecycleState.inactive  --->  AppLifecycleState.paused (or .hidden on Android 14+)
```

Prior to this fix, `VaultSession.handleLifecycleChange` evaluated:
```dart
if (state == AppLifecycleState.paused ||
    state == AppLifecycleState.inactive ||
    state == AppLifecycleState.hidden) {
  if (_autoLockTimeoutSeconds == 0) {
    lock(reason: VaultLockReason.background);
  }
}
```
Because the default setting was `_autoLockTimeoutSeconds = 0` (immediate lock on backgrounding), `VaultSession.lock()` was called instantly when the file picker launched. This:
1. Nullified `_masterKey` in memory.
2. Zeroed the ephemeral key byte buffer.
3. Notified listeners.
4. When the file picker returned, `MainActivity` resumed (`AppLifecycleState.resumed`), triggering `GoRouter`'s top-level redirect:
   `if (!session.isUnlocked && !isAuthFlow) return '/biometric-unlock';`
5. The user was forced through Factor 1 (biometrics) and Factor 2 (6-digit PIN) again.

### 2.2 Bug 2: Why Was Form State Lost?

In `AddDocumentScreen`, form field values were stored solely in transient widget controller memory:
```dart
late TextEditingController _nameController;
late TextEditingController _docNumberController;
final List<Map<String, dynamic>> _attachedFiles = [];
```
When `GoRouter` redirected to `/biometric-unlock` due to Bug 1, the entire route stack was torn down, destroying `AddDocumentScreen` and wiping all user input. Furthermore, even if the activity was not popped, any low-memory condition in Android causing Activity recreation would discard unpersisted inputs.

---

## 3. Technical Implementation & Architecture

### 3.1 System Activity Coordination (`VaultSession`)

We introduced system activity tracking and grace duration handling in `lib/core/security/vault_session.dart`:

```dart
class VaultSession extends ChangeNotifier {
  // System activity coordination (SAF file picker, camera, sharesheet)
  bool _isSystemActivityActive = false;
  String? _activeSystemActivityDescription;
  DateTime? _systemActivityStartTime;

  /// Grace period allowed when an explicit system activity is open (5 minutes)
  static const int systemActivityGraceTimeoutSeconds = 300;

  bool get isSystemActivityActive => _isSystemActivityActive;
  String? get activeSystemActivityDescription => _activeSystemActivityDescription;

  void beginSystemActivity(String description) {
    if (!isUnlocked) return;
    _isSystemActivityActive = true;
    _activeSystemActivityDescription = description;
    _systemActivityStartTime = DateTime.now();
  }

  void endSystemActivity() {
    _isSystemActivityActive = false;
    _activeSystemActivityDescription = null;
    _systemActivityStartTime = null;
  }
  ...
```

#### Lifecycle State Evaluation:
```dart
  void handleLifecycleChange(AppLifecycleState state) {
    if (!isUnlocked) return;

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      if (_isSystemActivityActive) {
        // App was paused/inactive because an explicit system activity was launched.
        // Do NOT lock immediately; record timestamp for grace timeout evaluation.
        _backgroundedTime ??= DateTime.now();
      } else if (_autoLockTimeoutSeconds == 0) {
        lock(reason: VaultLockReason.background);
      } else {
        _backgroundedTime = DateTime.now();
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_isSystemActivityActive) {
        if (_backgroundedTime != null) {
          final elapsed = DateTime.now().difference(_backgroundedTime!).inSeconds;
          if (elapsed >= systemActivityGraceTimeoutSeconds) {
            // Exceeded system activity grace timeout (e.g. user walked away for > 5 min)
            endSystemActivity();
            lock(reason: VaultLockReason.background);
            return;
          }
        }
        _backgroundedTime = null;
        recordUserActivity();
        return;
      }
      ...
    }
  }
```

### 3.2 Native SAF & Sharing Service Integration

In `lib/core/services/native_saf_and_share_service.dart`, `NativeSafAndShareService` was updated to attach the active `VaultSession`. All calls that open Android system activities now safely wrap the invocation:

```dart
  Future<List<SafFileItem>> pickDocuments({
    bool allowMultiple = true,
    List<String>? mimeTypes,
  }) async {
    if (!Platform.isAndroid) return [];

    _session?.beginSystemActivity('SAF_OPEN_DOCUMENT');
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('openDocument', {
        'allowMultiple': allowMultiple,
        'mimeTypes': effectiveMimeTypes,
      });
      ...
      return stagedItems;
    } finally {
      Future.microtask(() {
        _session?.endSystemActivity();
      });
    }
  }
```

This pattern is similarly applied across `createAndSaveDocument`, `shareFiles`, `shareText`, `CameraScannerScreen`, and `HomeDashboardScreen`.

---

### 3.3 Persistent Encrypted Draft System

To guarantee zero form data loss, we implemented a persistent encrypted draft system.

#### Database Schema Upgrade (v4)
In `lib/core/database/vault_database.dart`:
```sql
CREATE TABLE IF NOT EXISTS document_drafts (
  id TEXT PRIMARY KEY,
  encrypted_draft_data TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
```

#### Domain Model (`DocumentDraftModel`)
`lib/features/documents/domain/document_draft_model.dart`:
- `id`: Unique draft identifier (`active_draft`)
- `title`, `categoryId`, `documentType`, `documentNumber`, `ownerName`, `issuingAuthority`
- `issueDate`, `expiryDate`, `notes`, `tags`
- `attachedFiles`: List of staged file paths, names, and MIME types
- `updatedAt`: Timestamp
- `isEmpty` / `isNotEmpty` helper properties

#### Encryption at Rest (`DocumentDraftRepository`)
`lib/features/documents/data/document_draft_repository.dart`:
1. **Save**: Converts `DocumentDraftModel` to JSON, encrypts using `EncryptionService.encryptString(json, masterKey)` (AES-256-GCM + 12-byte IV + 16-byte authentication tag), and replaces row in `document_drafts`.
2. **Retrieve**: Reads ciphertext row, decrypts using session `masterKey`, parses JSON into `DocumentDraftModel`.
3. **Delete**: Completely purges the row from `document_drafts` upon save or user discard.
4. **Zero Plaintext**: Verifiably guarantees no sensitive user inputs ever touch SQLite in unencrypted form.

#### UI Auto-Save & Restoration (`AddDocumentScreen`)
In `lib/features/documents/presentation/add_document_screen.dart`:
- **Auto-Save on Input**: Keystroke listeners on all controllers with a 600ms debouncer trigger `_saveCurrentDraft()`.
- **Pre-Picker Save**: Before `pickDocuments()` is invoked, `_saveCurrentDraft()` is called synchronously.
- **Append on Return**: Files picked from SAF are validated and appended to `_attachedFiles`, followed immediately by an auto-save.
- **Restoration**: On `initState`, `_restoreDraftIfAvailable()` detects any existing encrypted draft and populates fields. A visual banner notifies the user:
  > *"Restored unsaved draft from your previous session. [Discard]"*
- **Exit Guard (`PopScope`)**: Tapping the Back button or close icon prompts the user:
  > *"Unsaved Document: Would you like to keep the draft for later or discard it? [Continue Editing] [Discard] [Keep Draft & Exit]"*
- **Auto-Wipe**: When `_saveDocument()` completes, `deleteDraft()` is invoked to prevent stale state.

---

### 3.4 Samsung My Files Incoming Sharing & Post-Import Actions

#### Native Receiver (`MainActivity.kt`)
- Supports `ACTION_SEND` and `ACTION_SEND_MULTIPLE`.
- Uses Android 13+ (API 33+) type-safe parcelable extraction:
  `intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)`
  with backward-compatible fallbacks for `intent.data` and `intent.clipData`.
- Validates MIME types against allowed document categories (PDF, JPG, JPEG, PNG).
- Streams `content://` URIs with an 8KB memory buffer into private cache staging.

#### 2FA Gating
- If Vault is locked when shared files arrive: User completes Factor 1 (Biometric) and Factor 2 (6-digit PIN). GoRouter redirects directly to `/incoming-share-preview`.
- If Vault is already unlocked: App transitions directly to `/incoming-share-preview` with no re-authentication required.

#### Post-Import Summary Card
In `lib/features/documents/presentation/incoming_share_preview_screen.dart`:
Once files are encrypted and processed through smart OCR:
- Displays **"Document securely saved to Vault"**.
- Badges: `AES-256-GCM`, `Smart OCR`, `100% Offline`.
- Three clear action buttons:
  1. **"View Document"**: Navigates to `/document/:id?tab=0` for immediate document viewing.
  2. **"View Extracted Information"**: Navigates to `/document/:id?tab=1` for structured OCR field review.
  3. **"Return to Dashboard"**: Calls `context.go('/dashboard')`.

---

## 4. Verification and Automated Test Results

### 4.1 Automated Test Execution Summary

A dedicated test suite was created in `test/lifecycle_and_draft_persistence_test.dart`:
- `VaultSession` System Activity Lifecycle Grace (file picker, camera, sharesheet)
- Regular background immediate lock vs system activity grace
- `DocumentDraftModel` serialization, empty/non-empty states, `copyWith`
- Encrypted draft persistence at rest with AES-256-GCM
- SAF and Share Item MIME type identification and queue preservation

Full project test suite execution:
```bash
$ flutter analyze
Analyzing vault...
No issues found! (ran in 2.7s)

$ flutter test
00:06 +74: All tests passed!
```

**74 out of 74 tests passing across all suites**:
- `test/lifecycle_and_draft_persistence_test.dart` (11 tests)
- `test/document_sharing_ocr_and_extraction_test.dart` (14 tests)
- `test/two_factor_and_vault_upgrade_test.dart` (17 tests)
- `test/security_and_crypto_test.dart` (8 tests)
- `test/theme_system_test.dart` (23 tests)
- `test/widget_test.dart` (1 test)

---

## 5. Build & Installation Status

The release APK was built successfully with full R8 shrinking and ProGuard hardening:
- **Build Output**: `build/app/outputs/flutter-apk/app-release.apk`
- **APK Size**: ~92 MB (includes bundled offline OCR trained data for English, Hindi, and Gujarati)
- **Target Device**: Samsung Galaxy S24 Ultra (`RZCY503D03H`)
- **Installation Command**:
  ```bash
  adb -s RZCY503D03H install -r build/app/outputs/flutter-apk/app-release.apk
  ```

---

## 6. Security Guarantees & Invariants Maintained

| Security Invariant | Implementation Mechanism | Status |
| :--- | :--- | :--- |
| **Mandatory 2FA** | Biometrics + 6-digit PIN enforced centrally in GoRouter guards | **Preserved 100%** |
| **No PIN/Biometric Only** | Master key derivation requires both factors | **Preserved 100%** |
| **Zero Network Permissions** | `tools:node="remove"` on `INTERNET`, `ACCESS_NETWORK_STATE` in manifest | **Verified** |
| **Zero Plaintext Drafts** | Encrypted with AES-256-GCM under session master key in SQLite | **Verified** |
| **Ephemeral Cache Security** | Staging and decrypted temporary files wiped on lock/save | **Verified** |
| **Controlled Grace Period** | 5-minute system activity timeout prevents indefinite unlock | **Verified** |

