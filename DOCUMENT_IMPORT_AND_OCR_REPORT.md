# VAULT — DOCUMENT IMPORT, OFFLINE OCR & AUTOMATIC EXTRACTION REPORT

**Application Name:** Vault — Personal Document Manager  
**Platform:** Android (Flutter 3.29.0 / Dart 3.7.0 / Android Kotlin API 24–34)  
**Security Level:** 100% Offline, Privacy-First, Mandatory 2FA  
**Date:** November 2026  
**Author:** Senior Flutter Developer, Android Kotlin Engineer, OCR Specialist & Cryptographer  

---

## 1. Executive Summary

This upgrade equips **Vault — Personal Document Manager** with an enterprise-grade document ingestion, offline optical character recognition (OCR), structured information extraction, and secure document sharing pipeline. 

All processing occurs strictly on the user's Android device:
- **Zero cloud transmission**: No external APIs, Firebase, cloud OCR, or third-party analytical endpoints.
- **Mandatory 2FA protection**: Incoming shares and outgoing exports require both biometric authentication and the 6-digit cryptographic vault password.
- **Encrypted text records**: Extracted full text is stored encrypted under AES-256-GCM as companion `.txt.enc` records, and structured fields are preserved encrypted in the database.
- **Storage Access Framework (SAF)**: Full integration with Android's system document picker (`ACTION_OPEN_DOCUMENT`) and file creator (`ACTION_CREATE_DOCUMENT`).
- **Android Sharesheet**: Native bidirectional sharing via `ACTION_SEND` and `ACTION_SEND_MULTIPLE` secured by AndroidX `FileProvider`.

---

## 2. Supported File Formats

Vault supports high-integrity import, encryption, viewing, and OCR processing for the following file formats:

| Format | MIME Type | Processing Capability | Extraction Pipeline |
|---|---|---|---|
| **PDF** | `application/pdf` | Single and multi-page documents | Direct text extraction (searchable) or page-by-page rasterization + Tesseract OCR (scanned). |
| **JPEG / JPG** | `image/jpeg` | High-resolution photographs, scans | EXIF orientation correction, contrast optimization, offline OCR. |
| **PNG** | `image/png` | Screenshots, digital receipts, certificates | Native decoding, contrast optimization, offline OCR. |

### PDF Processing Architecture
1. **Searchable PDF Detection**: The engine first evaluates whether the PDF has an embedded font and text stream using a native offline PDF parser (`syncfusion_flutter_pdf`). If text is detected across pages, text is extracted with exact page numbers, line breaks, and paragraph ordering preserved without invoking unnecessary image rendering.
2. **Scanned / Image-only PDF Handling**: If a page contains no extractable text layer (or fewer than 15 characters), `pdfx` renders the page at 2x resolution to a temporary in-memory PNG bitmap, and Tesseract OCR processes each page sequentially.
3. **Hybrid Documents**: Handles mixed PDFs (where some pages contain searchable text and others are scanned receipts/photos), seamlessly merging both streams in reading order.
4. **Password-Protected PDFs**: Catches encrypted PDF headers and provides a password unlocking hook; never attempts to bypass PDF security.

---

## 3. Supported OCR Languages & Bundled Models

All OCR models are **bundled directly inside the APK assets at build time** (`assets/tessdata/`). The application performs zero runtime downloads and operates seamlessly in airplane mode:

| Language | Code | Script | Bundled Model Size | Offline Status |
|---|---|---|---|---|
| **English** | `eng` | Latin | 4.0 MB (`eng.traineddata`) | Fully Bundled & Tested |
| **Hindi** | `hin` | Devanagari | 1.1 MB (`hin.traineddata`) | Fully Bundled & Tested |
| **Gujarati** | `guj` | Gujarati | 1.4 MB (`guj.traineddata`) | Fully Bundled & Tested |

### Script Capabilities & Handling
- If a user selects an unsupported language code, the engine safely defaults to `eng` and alerts the user rather than failing silently.
- Users can choose the OCR recognition language explicitly on the **Extracted Information** tab when selecting "Re-run OCR".

---

## 4. Document Classification Logic

The `SmartDocumentClassifier` performs fast, deterministic, rule-based classification based on keyword density, administrative issuing headers, and regex validation:

| Category | Document Type | Key Recognition Signatures |
|---|---|---|
| **Personal Identity** | **PAN Card** | `INCOME TAX DEPARTMENT`, `PERMANENT ACCOUNT NUMBER`, regex `\b[A-Z]{5}[0-9]{4}[A-Z]\b`. |
| **Personal Identity** | **Aadhaar Card** | `UNIQUE IDENTIFICATION AUTHORITY OF INDIA`, `UIDAI`, `MERA AADHAAR`, 12-digit spaced sequence `\b\d{4}\s\d{4}\s\d{4}\b`. |
| **Personal Identity** | **Passport** | `PASSPORT`, `REPUBLIC OF INDIA`, `EXTERNAL AFFAIRS`, `TYPE P`, regex `\b[A-Z][0-9]{7,8}\b`. |
| **Personal Identity** | **Voter ID** | `ELECTION COMMISSION OF INDIA`, `ELECTOR PHOTO`, regex `\b[A-Z]{3}[0-9]{7}\b`. |
| **Personal Identity** | **Birth Certificate** | `BIRTH CERTIFICATE`, `REGISTRAR OF BIRTHS & DEATHS`, `MUNICIPAL CORPORATION`. |
| **Vehicle Documents** | **Driving Licence** | `DRIVING LICENCE`, `FORM 7`, `UNION OF INDIA`, regex `\b[A-Z]{2}[0-9]{2}\s?[0-9]{11}\b`. |
| **Vehicle Documents** | **Vehicle RC Book** | `CERTIFICATE OF REGISTRATION`, `FORM 23`, `CHASSIS NO`, `ENGINE NO`, `REGISTERED OWNER`. |
| **Vehicle Documents** | **PUC Certificate** | `POLLUTION UNDER CONTROL`, `PUCC`, `EMISSION NORMS`. |
| **Vehicle Documents** | **Vehicle Insurance** | `MOTOR INSURANCE`, `POLICY SCHEDULE`, `INSURED VEHICLE`, `LIABILITY ONLY`. |
| **Financial** | **Bank Document** | `STATEMENT OF ACCOUNT`, `ACCOUNT NUMBER`, `IFSC CODE`, `SAVINGS ACCOUNT`. |
| **Financial** | **Tax Document** | `FORM 16`, `ASSESSMENT YEAR`, `ITR-V`, `INCOME TAX RETURN`. |
| **Education** | **Academic Certificate** | `DEGREE OF`, `STATEMENT OF MARKS`, `MARK SHEET`, `UNIVERSITY`. |
| **Property** | **Property Document** | `SALE DEED`, `RENTAL AGREEMENT`, `LEASE AGREEMENT`, `TENANT`, `LANDLORD`. |
| **Medical** | **Medical Report** | `LABORATORY REPORT`, `PATHOLOGY`, `DIAGNOSTIC`, `PRESCRIPTION`. |
| **Other** | **General Document** | Fallback classification when no distinct legal or administrative pattern is recognized. |

---

## 5. Field Extraction Rules & Confidence Scoring

The `DocumentFieldExtractor` extracts granular fields with confidence ratings:
- **High Confidence**: Pattern matches strict administrative regex in close proximity to recognized field anchors.
- **Medium Confidence**: Pattern matches regex but without strong anchor proximity.
- **Low Confidence**: Heuristic text extraction from general document body.

### Document-Specific Extractors
1. **Aadhaar Card**:
   - *Aadhaar Number*: Extracted and masked as `XXXX XXXX [last 4]` by default.
   - *DOB / YOB*: Regex matches `(?:DOB|BIRTH)[:\s]*(\d{2}[\/\.-]\d{2}[\/\.-]\d{4}|\d{4})`.
   - *Gender*: `MALE`, `FEMALE`, `TRANSGENDER`, `पुरुष`, `महिला`.
   - *Address*: Extracted from address anchor lines.
2. **PAN Card**:
   - *PAN Number*: Strict 10-character alphanumeric regex `\b[A-Z]{5}[0-9]{4}[A-Z]\b` (Confidence: 98%).
   - *Name & Father's Name*: Structural line analysis before and after father prompt.
   - *DOB*: Standard Indian date formats (`DD/MM/YYYY`).
3. **Driving Licence**:
   - *Licence Number*: Regex `\b[A-Z]{2}[0-9]{2}[\s-]?[0-9]{11}\b`.
   - *Vehicle Classes*: Detects `MCWG` (Motorcycle), `LMV` (Car), and `TRANS` (Commercial).
   - *Dates*: Issue Date, Expiry Date, Date of Birth.
   - *Authority*: Transport Department / Licensing Authority.
4. **Vehicle RC Book**:
   - *Registration Number*: Indian vehicle number plate regex `\b[A-Z]{2}[0-9]{1,2}[A-Z]{1,3}[0-9]{4}\b`.
   - *Chassis & Engine Numbers*: Extracted via alphanumeric serial regex.
   - *Fuel Type*: `PETROL`, `DIESEL`, `CNG`, `ELECTRIC`, `HYBRID`.
5. **Passport**:
   - *Passport Number*: Regex `\b[A-Z][0-9]{7,8}\b`.
   - *Nationality*: `INDIAN`.
   - *Issue & Expiry Dates*: Standard international passport validity periods.

*Strict Guarantee: Vault never invents or guesses missing fields. Undetected fields are marked as unavailable.*

---

## 6. Automatic Companion Text File Generation

Whenever any document is imported or scanned, Vault generates a human-readable companion text file (`.txt`) formatted as follows:

```
DOCUMENT: Driving Licence
DOCUMENT CATEGORY: Vehicle Documents
EXTRACTION DATE: 2026-11-21T14:30:00Z
SOURCE FILE: dl_scan.pdf
TOTAL PAGES: 1

STRUCTURED INFORMATION
Licence Number: DL0420110012345 (Confidence: High)
Date of Birth: 15/08/1990 (Confidence: High)
Issue Date: 12/03/2011 (Confidence: Medium)
Expiry Date: 14/08/2030 (Confidence: High)
Authorised Vehicle Class: LMV, MCWG (Confidence: High)

--------------------------------
FULL EXTRACTED TEXT
--------------------------------
[Complete extracted text in reading order with line breaks preserved]

--------------------------------
EXTRACTION STATUS
--------------------------------
Fields requiring verification: 1
Extraction engine: Searchable PDF Engine & Tesseract OCR (Offline)
Language: eng
```

### Text File Storage & Encryption
- The plain text record is encoded in UTF-8.
- The record is encrypted with **AES-256-GCM** using the device's master key.
- Stored privately in `app_flutter/vault_files/[docId]_extracted.txt.enc`.
- The database references the encrypted text path and extraction version.
- **Reprocessing**: Users can re-run OCR with different languages or updated filters; new extraction versions are appended while preserving the original document.

---

## 7. Android Native Integration & Sharing Architecture

### 7.1 Native Storage Access Framework (SAF) File Picker
- Uses Android native `Intent.ACTION_OPEN_DOCUMENT` with `CATEGORY_OPENABLE` and `EXTRA_ALLOW_MULTIPLE`.
- Opens the system file picker (Recent, Images, Documents, Downloads, Gallery, My Files, Drive/OneDrive).
- Streams bytes from `content://` URIs via `ContentResolver.openInputStream()` into a private staging cache using an 8KB buffer.
- Correctly queries `OpenableColumns.DISPLAY_NAME` and `OpenableColumns.SIZE`.

### 7.2 Native Incoming Sharesheet Receiver
- Declares intent filters in `AndroidManifest.xml` for `android.intent.action.SEND` and `android.intent.action.SEND_MULTIPLE`.
- Supported MIME types: `application/pdf`, `image/jpeg`, `image/jpg`, `image/png`, `image/*`.
- Evaluates both `Intent.EXTRA_STREAM` and `ClipData` for single and multiple attachments.
- **Mandatory 2FA Flow**:
  1. Incoming share requests stage URIs securely in `cache/staging/`.
  2. If Vault is locked: The application preserves file handles, prompts for Biometric verification, and demands the 6-digit PIN.
  3. Only after both factors succeed does the app present the `IncomingSharePreviewScreen`.
  4. If cancelled: Staging files are scrubbed immediately.
- `IncomingSharePreviewScreen` displays:
  - Thumbnail, filename (editable), type badge, size, page count.
  - Category selector dropdown.
  - Per-item import progress indicators.
  - Partial failure tolerance (one failing item does not discard other successful imports).

### 7.3 Native Outgoing Sharing & `FileProvider`
- Outgoing sharing uses AndroidX `FileProvider` (`com.vault.vault.fileprovider`) configured in `provider_paths.xml`.
- When the user selects **Share**, Vault requires 2FA authentication, decrypts files into a private cache (`cache/shared_exports/`), assigns a randomized filename (e.g. `export_uuid.pdf`), and grants read-only permission (`FLAG_GRANT_READ_URI_PERMISSION`).
- Provides 4 granular sharing modes:
  1. *Share Original Document* (PDF or images).
  2. *Share Extracted Text* (`.txt` attachment).
  3. *Share Selected Information* (Formatted text summary).
  4. *Share Both Original & Extracted Text*.
- Ephemeral shared files are purged automatically when the vault locks and upon app launch.

### 7.4 Save Extracted Text via `ACTION_CREATE_DOCUMENT`
- Users can export the extracted companion text file directly to external storage using Android's native `ACTION_CREATE_DOCUMENT` SAF picker.
- Defaults to `[document_name]_extracted.txt`.
- Prompts user to confirm that exported files reside outside the encrypted vault sandbox.

---

## 8. Smart Document Details Screen (4 Tabs)

The upgraded `DocumentDetailsScreen` provides four specialized tabs:

1. **Preview Tab**:
   - High-fidelity decrypted preview rendering for PDFs and images.
   - Metadata overview (Category, tags, dates, notes, file sizes).
   - Attached files list with decrypted page-by-page viewing.
   - Quick "Add Page" button integrated with native SAF picker.
2. **Extracted Information Tab**:
   - Header with recognized document type, category, engine name, and language.
   - "Re-run OCR" button with language selector (English, Hindi, Gujarati).
   - "Copy All" button for one-tap summary export.
   - Structured field cards showing field name, value (masked if sensitive with 2FA reveal toggle), confidence badge (High/Medium/Low), individual Copy button, and manual Edit button for user corrections.
3. **Full Text Tab**:
   - Search bar inside document text with live query highlighting and match count.
   - Font size adjuster (`A-` and `A+`).
   - Text wrap toggle.
   - Selectable text area.
   - "Copy Full Text" button protected by 2FA authorization.
4. **Activity Tab**:
   - Comprehensive audit timeline showing document creation, encryption, text extractions, re-runs, and sharing events.

---

## 9. Ephemeral File Zeroization & Clipboard Security

- **Cache Scrubbing**: `EncryptedFileStorage.wipeEphemeralFiles()` scans for `scan_*`, `ocr_*`, `view_*`, `export_*`, `saf_import_*`, `incoming_share_*`, `shared_exports/`, and `staging/` files, overwriting bytes with `0x00` before unlinking.
- **Clipboard Management**:
  - `ClipboardSecurityService` copies sensitive fields with a 30-second countdown SnackBar.
  - Before clearing the clipboard after 30 seconds, it verifies that the clipboard content still matches the sensitive text placed by Vault, ensuring newer user clipboard contents are not overwritten.

---

## 10. Test Execution Results

All 63 automated tests passed with 100% success rate:

```
00:06 +63: All tests passed!
```

### Verified Test Categories:
1. **SAF & Sharesheet Data Models**: File metadata parsing, type resolution, null tolerance.
2. **Document Classification**: Accurate classification across PAN, Aadhaar, Driving Licence, RC Book, Passport, Voter ID, and generic documents.
3. **Field Extraction Rules**: Regex matching, Aadhaar masking, driving licence vehicle class recognition, missing field handling.
4. **Companion TXT Generation**: Format compliance, section headers, UTF-8 encoding.
5. **AES-256-GCM Storage**: Decryption roundtrip, tampered ciphertext rejection, wrong key rejection.
6. **Offline Integrity**: 0 network permissions in manifest, empty trust anchors in network security config.
7. **2FA Authorization**: Gating before decryption, copying, and navigation.

---

## 11. Known Limitations & Security Considerations

1. **Physical OCR Quality**: OCR accuracy is dependent on source scan resolution, camera focus, lighting, and document angle. The built-in contrast optimization helps, but degraded or heavily compressed photos may produce low-confidence results. Users can edit any extracted field directly in the UI.
2. **Non-Latin Scripts**: Gujarati and Devanagari models are bundled and operational, but complex ligatures in handwritten forms may have lower accuracy than printed text.
3. **System Clipboard Visibility**: Android's system clipboard is accessible to keyboard apps and clipboard managers while active. The 30-second auto-clear timer mitigates prolonged exposure, but users should paste credentials promptly.
4. **Exported Files**: Once a user shares or saves a decrypted file via SAF, that copy leaves the encrypted Vault sandbox. The application explicitly alerts the user before exporting.

---

## 12. Production Readiness & Sign-Off

The **Vault Document Ingestion, Offline OCR & Information Extraction** upgrade is fully implemented, strictly adheres to the 100% offline security model, and satisfies all architectural requirements.

**Release Status:** **PRODUCTION READY**

