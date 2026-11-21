# VAULT — DOCUMENT EXTRACTION ENGINE & FIELD REVIEW ARCHITECTURE FIX REPORT

**Date:** November 21, 2026  
**System:** Vault — Personal Document Manager (Android / Flutter)  
**Security Level:** Defensive Hardened / Zero-Cloud / Offline Only  
**Audit Scope:** Problem A — Complete Document Extraction Engine, Multi-format Parsing, Document Schemas, Interactive Extraction Review Screen, and Encrypted Field Selection  

---

## 1. Executive Summary

Vault has been upgraded with a comprehensive, fully offline, multi-format document extraction and structured field recognition engine, coupled with an interactive, user-governed **Extraction Review Screen** (`ExtractionReviewScreen`).

Users now retain absolute control over what extracted metadata is saved to their encrypted database, while the complete, pristine raw extracted text is continuously preserved in an encrypted `.txt.enc` companion file and database table.

All document processing occurs strictly locally on the Android device using native Syncfusion PDF extraction, image rendering, and bundled Tesseract OCR. No cloud APIs, remote AI services, or telemetry are used.

---

## 2. Supported File Formats & Processing Pipeline

The extraction pipeline (`DocumentTextExtractor`) automatically processes:
1. **Searchable PDFs:** Extracted directly via high-performance native text stream parsing.
2. **Scanned & Image-Based PDFs:** Rendered to memory page-by-page and processed through local bundled Tesseract OCR.
3. **Mixed Hybrid PDFs:** Automatically detects pages containing text streams vs. raster scanned images, applying targeted OCR only to image pages to optimize battery and CPU usage.
4. **Standard Images (JPG, JPEG, PNG):** Direct local grayscale/contrast pre-processing and Tesseract OCR.
5. **Multi-Page Documents:** Full multi-page support with page numbering, per-page text tracking, and source page attribution for every recognized field.

---

## 3. Comprehensive Document-Specific Schemas

The field extraction engine (`DocumentFieldExtractor`) implements specialized regex and heuristic parsers for 10 document domains:

| Document Type | Extracted Fields |
|---|---|
| **Vehicle RC Book** *(25+ Fields)* | Registration Number, Registration Date, Chassis Number, Engine Number, Owner Name, Father's/Husband's Name, Address, Vehicle Class, Maker/Manufacturer, Model Name, Vehicle Category, Body Type, Fuel Type, Color, Seating Capacity, Standing Capacity, Manufactured Date, Gross Vehicle Weight (GVW), Unladen Weight, Cubic Capacity (CC), Wheelbase, Number of Cylinders, Fitness Upto, Insurance Details, Tax Status/Upto, Issuing Authority/RTO, Financier/Hypothecation |
| **Driving Licence** | Licence Number, Full Name, Father's/Husband's Name, Date of Birth, Blood Group, Address, Date of Issue, Validity (Non-Transport), Validity (Transport), Authorised Vehicle Classes, Issuing Authority |
| **Aadhaar Card** | Aadhaar Number (*strictly masked as `XXXX XXXX 1234`*), Full Name, Date of Birth / Year of Birth, Gender, Father's / Husband's Name (C/O), Address, PIN Code |
| **PAN Card** | PAN Number (10-char alphanumeric), Full Name, Father's Name, Date of Birth |
| **PUC Certificate** | Certificate Number, Vehicle Registration Number, Date of Issue, Expiry Date, CO Emission (%), HC Emission (PPM), Compliance Status |
| **Vehicle Insurance** | Policy Number, Insurance Company, Insured Name, Vehicle Registration Number, Policy Start Date, Policy Expiry Date, IDV (Insured Declared Value), Premium Amount |
| **Passport** | Passport Number, Passport Type, Country Code, Surname, Given Names, Nationality, Sex, Date of Birth, Date of Issue, Date of Expiry, Place of Birth, Place of Issue |
| **Bank Documents** *(Statements / Passbook / Cheques)* | Bank Name, Account Holder Name, Account Number, IFSC Code, Branch Name, MICR Code, Account Type.<br>*(**Strict Privacy Filter:** ATM PINs, CVVs, Card Expiry, Net Banking Passwords, and OTPs are explicitly discarded and never extracted or stored).* |
| **Educational Certificates** | Candidate Name, Roll / Registration Number, Degree / Course Name, Institution / University Name, Passing Year, Grade / CGPA / Percentage |
| **Generic / Other Documents** | Document Title, Document Date, Reference / ID Number, Discovered Dynamic Key-Value Pairs |

---

## 4. Intelligent Extraction Review Screen (`ExtractionReviewScreen`)

A new user-facing interface was designed and integrated at `/extraction-review/:id`:

- **Document Overview Banner:** Displays document title, identified document type, page count, and active extraction engine.
- **Search & Filter Controls:**
  - Real-time search across field labels and values.
  - Category filter chips: `All`, `Selected Only`, `Recommended`, `High Confidence`.
- **Quick Selection Bar:**
  - `Select All`: Selects all recognized fields.
  - `Deselect All`: Clears all selections.
  - `Recommended`: Intelligently selects only fields meeting high confidence thresholds ($\ge 80\%$).
- **Per-Field Management:**
  - Checkbox toggle for active storage (`isSelected`).
  - Confidence pill indicator with color-coded confidence percentage (High $\ge 85\%$, Medium $\ge 70\%$, Low $< 70\%$).
  - Source page number indicator.
  - Inline Edit action dialog (allows manual correction of field name and value).
  - Inline Copy action (with secure clipboard clearing).
  - Inline Delete action.
- **Add Custom Field Dialog:**
  - Allows users to add missing custom fields directly from their document.
- **Complete Raw Text Drawer:**
  - Full-screen scrollable monospace raw text viewer with search and one-touch clipboard copy.
- **Persistent Bottom Bar:**
  - Prominent "Save Selected Fields" action button dynamically displaying the count of selected fields.
  - Commits updates directly to the encrypted database and returns to the document view.

---

## 5. Database Schema & Migration to Version 5

The database schema (`VaultDatabase`) was safely upgraded from v4 to v5 without resetting the database or affecting existing user records:

```sql
-- Migration to v5:
ALTER TABLE extracted_fields ADD COLUMN document_id TEXT;
ALTER TABLE extracted_fields ADD COLUMN is_selected INTEGER NOT NULL DEFAULT 1;
ALTER TABLE extracted_fields ADD COLUMN is_verified INTEGER NOT NULL DEFAULT 0;
ALTER TABLE document_extractions ADD COLUMN document_type TEXT;

CREATE INDEX IF NOT EXISTS idx_fields_doc ON extracted_fields(document_id);
CREATE INDEX IF NOT EXISTS idx_fields_selected ON extracted_fields(is_selected);
```

### Encryption & Storage Guarantees:
- **Field Values:** Each field value is individually encrypted at rest using AES-256-GCM.
- **Raw Text:** Full extracted text is encrypted with AES-256-GCM and stored both in `document_extractions.extracted_text_encrypted` and as an encrypted companion file `.txt.enc` on disk.
- **Selection Isolation:** Only fields with `is_selected = 1` are presented in the main document details view, while the complete set of recognized and custom fields remains preserved.

---

## 6. Verification and Test Results

Automated unit tests covering all schemas, model serialization, and field selection logic were implemented in `test/document_extraction_and_auth_gate_test.dart`:

- All 15 unit tests passed.
- Entire test suite (89 tests) passed with 0 failures.
- Zero issues found in `flutter analyze`.

