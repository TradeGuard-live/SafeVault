# SAFEVAULT — USER GUIDE & PRODUCT MANUAL

**Welcome to SafeVault** — your private, offline-first personal document, banking, and password safe. SafeVault is built with zero-knowledge architecture, meaning your sensitive data never leaves your device, is never uploaded to the cloud, and is protected with military-grade AES-256-GCM encryption.

---

## 1. GETTING STARTED

### Initial Setup & Security Enrollment
When you launch SafeVault for the first time, you will set up your **Mandatory Two-Factor Authentication (2FA)**:
1. **Enroll Biometrics**: Scan your fingerprint or face using your phone's built-in biometric sensor. SafeVault links this directly with your phone's hardware security chip (Android Keystore / Knox / StrongBox).
2. **Choose a 6-Digit Vault PIN**: Enter a memorable 6-digit numeric PIN. This PIN is combined with your biometric key using an advanced cryptographic splitting algorithm ($K = S_{bio} \oplus S_{pin}$) to generate your vault's Master Encryption Key.
3. **Confirmation**: Re-enter your 6-digit PIN to confirm. Your vault is now initialized and ready to protect your documents.

> [!IMPORTANT]
> **Keep your 6-Digit PIN Safe**: Because SafeVault is 100% offline with zero cloud backdoors, no one (not even SafeVault developers) can reset your PIN if you forget it.

---

## 2. HOW MANDATORY TWO-FACTOR AUTHENTICATION (2FA) WORKS

Whenever you open SafeVault or return after locking, SafeVault requires **both factors**:
1. First, prompt for your **Fingerprint or Face**.
2. Second, prompt for your **6-Digit Vault PIN**.

This prevents unauthorized access even if:
- Someone knows your phone lock password or watches you enter your 6-digit PIN (they cannot access without your physical biometric).
- Someone forces a biometric scan while you are asleep (they cannot access without your 6-digit secret PIN).

---

## 3. MANAGING PERSONAL DOCUMENTS

### Adding Documents
SafeVault supports all standard personal document formats: **PDF files**, **JPEG images**, and **PNG images**.

You can add documents in two ways:
1. **Browse Files (Native Android Storage Access Framework)**:
   - Tap the **+** (Add Document) button on the Dashboard.
   - Tap **Browse Files**.
   - The native Android system picker opens, letting you browse your Downloads, Google Drive, OneDrive, Gallery, or SD Card.
   - Select your document. You return seamlessly to SafeVault with all your form details preserved.
2. **Scan with Camera**:
   - Tap **Scan Document**.
   - Point your camera at your document, frame it, and capture.

### Document Details & Expiry Tracking
When saving a document, you can specify:
- **Title & Category** (e.g., Personal Identity, Vehicle, Financial, Education, Property, Medical).
- **Document Number & Holder Name** (automatically encrypted).
- **Issue Date & Expiry Date**: SafeVault calculates the remaining days and alerts you before important documents expire (e.g., Driving Licence, Vehicle Insurance, PUC, Passport).
- **Tags & Encrypted Notes**.

---

## 4. SMART OCR & AUTOMATIC INFORMATION EXTRACTION

SafeVault features an advanced, **100% on-device Optical Character Recognition (OCR) engine** powered by Google ML Kit. It reads your document locally without sending a single byte over the internet.

### Supported Document Schemas
When you add or view a document, SafeVault can automatically detect and extract fields across **12 specialized categories**:
1. **Vehicle RC Book (28 Fields)**: Registration Number, Chassis Number, Engine Number, Owner Name, Vehicle Class, Maker/Model, Fuel Type, Seating Capacity, Fitness Date, Tax Status, RTO Authority, and PUC Validity.
2. **Driving Licence**: DL Number, Expiry Dates, Authorized Vehicle Classes (e.g. LMV, MCWG), Date of Birth, Holder Name, and Issuing Authority.
3. **Aadhaar Card**: Automatically detects the 12-digit number and formats it with privacy masking (`XXXX XXXX 1234`), Name, DOB, and Gender.
4. **PAN Card**: 10-digit Permanent Account Number, Name, Father's Name, and Date of Birth.
5. **PUC Certificate**: Emission test dates, validity, CO%, and Hydrocarbon levels.
6. **Vehicle Insurance**: Policy Number, Insurer Company, Policy Period, IDV, and Premium.
7. **Passport**: Passport Number, Nationality, Issue/Expiry Dates, Place of Birth.
8. **Bank Documents**: Account Number, IFSC Code, Account Holder Name, Bank Name, and Branch. *(Strict security automatically discards any detected card PINs or CVVs)*.
9. **Academic / Degree Certificates**: Student Name, Degree, University / Board, Roll Number, and CGPA.
10. **Property / Rent Agreements**: Lessor / Owner Name, Lessee / Tenant Name, Property Address, Term, Monthly Rent, and Security Deposit.
11. **Medical Reports**: Patient Name, Age / Gender, Doctor, Hospital / Clinic, Test Name, and Patient UHID.
12. **Generic Documents**: Automatically discovers dynamic `Key : Value` pairs.

### Using the Extraction Review Screen
After OCR analysis, SafeVault presents the **Extraction Review Screen**:
- **Selection Toggles**: Check or uncheck individual fields so you only save what you want.
- **Bulk Selection**: Use the *Select All* or *Recommended Only* buttons.
- **Search & Filter**: Quickly find specific fields using the search bar.
- **Edit on the Fly**: Tap the pencil icon on any field to correct OCR typos before saving.
- **Add Custom Fields**: Tap *Add Custom Field* to add any extra note or detail not automatically detected.
- **Inspect Raw Text**: Swipe open the right-side drawer to view the complete raw extracted text.
- **Save Selection**: Tap *Save Selection* to encrypt and store all selected fields.

---

## 5. REVEALING SENSITIVE SECRETS & 60-SECOND AUTO-HIDE

To protect against shoulder surfing and casual eavesdropping:
- Document numbers, passwords, and bank account numbers are displayed by default with masking bullets (`••••••••`).
- Tap the **Reveal (Eye)** icon to view the unmasked text.
- SafeVault will ask you to quickly authenticate with 2FA.
- Once authenticated, the secret is displayed **directly on the same screen** without interrupting your flow.
- **60-Second Auto-Hide**: After 60 seconds of inactivity, the secret will automatically revert to its masked state for your safety.

---

## 6. BANK VAULT

SafeVault provides a dedicated **Bank Vault** to store reference financial information:
- Store Bank Name, Account Holder Name, Account Number, IFSC Code, Branch, and Account Type (Savings, Current, Fixed Deposit).
- **Strict Privacy Rule**: SafeVault deliberately **does not** store or allow saving ATM PINs, CVVs, or Transaction Passwords. This ensures your funds remain secure even if someone manages to view your phone.
- Single-tap copy for Account Number and IFSC Code with automatic 30-second clipboard clearing.

---

## 7. PASSWORD MANAGER

Keep your web, app, and email credentials organized:
- **Encrypted Credentials**: Stores Website/App name, Username/Email, Password, and secure Notes.
- **Built-in Password Generator**: Create strong, cryptographically random passwords with customizable lengths, numbers, symbols, uppercase, and lowercase characters.
- **Password Strength Analyzer**: Evaluates password security and alerts you if a password is weak, short, or reused.

---

## 8. TRASH, RESTORE & PERMANENT SHREDDING

When you delete a document:
- It is moved to the **Trash** tab as a safeguard against accidental deletion.
- **Restore**: Open Trash, tap *Restore*, pass 2FA verification, and your document is restored back to your active vault.
- **Permanent Shred**: Tap *Delete Permanently* on an item in Trash to overwrite its database record and securely purge its encrypted file from device storage.
- **Empty Trash**: Shreds all deleted items in a single action.

---

## 9. PRIVACY & SECURITY SETTINGS

Open the **Settings** tab to customize your protection:
- **Inactivity Timeout**: Choose how quickly SafeVault locks after inactivity (Immediate, 1 Minute, 5 Minutes).
- **Change Vault PIN**: Authenticate with your existing credentials to set a new 6-digit PIN. SafeVault re-encrypts your key shares safely without data loss.
- **Screen Protection**: SafeVault automatically blocks screenshots and task switcher previews (`FLAG_SECURE`).
- **Complete Air-Gap**: SafeVault has zero network permissions (`android.permission.INTERNET` is not included in the app). Your data never touches the cloud.

