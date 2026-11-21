# SAFEVAULT — COMPLETE SCREEN & CONTROL INVENTORY

**Application**: SafeVault (Personal Document Manager, Bank Vault & Password Manager)  
**Classification**: COMPREHENSIVE UI/UX CONTROL AUDIT & STATUS MATRIX  
**Date**: November 2026  
**Status**: 40 SCREENS & DIALOGS AUDITED  

---

## 1. COMPREHENSIVE SCREEN INVENTORY TABLE

| # | Screen / Route Name | Source File | Key Interactive Controls | Status | Notes |
| :-: | :--- | :--- | :--- | :---: | :--- |
| **1** | `SplashScreen` (`/`) | `lib/features/onboarding/presentation/splash_screen.dart` | Auto-routes to setup or unlock | **PASS** | Evaluates vault existence |
| **2** | `InitialSecuritySetupScreen` (`/initial-setup`) | `lib/features/onboarding/presentation/initial_security_setup_screen.dart` | Biometric button, PIN pad, Confirm PIN | **PASS** | 2FA vault initialization |
| **3** | `BiometricAuthScreen` (`/biometric-unlock`) | `lib/features/authentication/presentation/biometric_auth_screen.dart` | Scan button, Lock status, Mascot pose | **PASS** | Factor 1 biometric prompt |
| **4** | `PinAuthScreen` (`/pin-unlock`) | `lib/features/authentication/presentation/pin_auth_screen.dart` | 6-digit numeric keypad, backspace, error | **PASS** | Factor 2 PBKDF2 PIN |
| **5** | `TwoFactorVerificationDialog` | `lib/features/authentication/presentation/two_factor_verification_dialog.dart` | Biometric trigger, PIN input, Cancel button | **PASS** | Embedded 2FA authorization |
| **6** | `MainShell` | `lib/features/dashboard/presentation/main_shell.dart` | 5 Bottom tabs: Home, Docs, Pass, Bank, Settings | **PASS** | Auto-locks on session expiry |
| **7** | `HomeDashboardScreen` (`/dashboard`) | `lib/features/dashboard/presentation/home_dashboard_screen.dart` | Hero card, 4 quick actions, carousels, search, lock | **PASS** | Primary app hub |
| **8** | `AllDocumentsScreen` (`/all-documents`) | `lib/features/documents/presentation/all_documents_screen.dart` | Category filter chips, sort menu, search, fab add | **PASS** | Document library |
| **9** | `CategoryDocumentsScreen` (`/category/:id`) | `lib/features/documents/presentation/category_documents_screen.dart` | Filtered list, search, add document | **PASS** | Category-scoped list |
| **10** | `AddDocumentScreen` (`/add-document`) | `lib/features/documents/presentation/add_document_screen.dart` | Form inputs, Browse SAF button, Scan button, Save | **PASS** | Form preserved across SAF |
| **11** | `DocumentDetailsScreen` (`/document/:id`) | `lib/features/documents/presentation/document_details_screen.dart` | 4 Tabs (Overview, Text, Audit, Info), Reveal Eye, Share | **PASS** | 60s secret auto-hide timer |
| **12** | `DocumentViewerScreen` (`/view-document/:id`)| `lib/features/documents/presentation/document_viewer_screen.dart` | PDF/image pinch-zoom, page scroller, export | **PASS** | Sandboxed decrypted render |
| **13** | `DocumentShareSheet` | `lib/features/documents/presentation/document_share_sheet.dart` | Share PDF, Share TXT, Share Both, 2FA prompt | **PASS** | Sandboxed cache export |
| **14** | `IncomingSharePreviewScreen` (`/incoming-share-preview`) | `lib/features/documents/presentation/incoming_share_preview_screen.dart` | Multi-file queue, Category selectors, Import all | **PASS** | Android SEND intent queue |
| **15** | `CameraScannerScreen` (`/camera-scanner`) | `lib/features/scanner/presentation/camera_scanner_screen.dart` | Shutter, Flash toggle, Multi-page count, Done | **PASS** | Native CameraX integration |
| **16** | `ScannerPreviewScreen` (`/scanner-preview`) | `lib/features/scanner/presentation/scanner_preview_screen.dart` | Crop, Rotate, Retake, Extract Text, Save | **PASS** | Local image preprocessing |
| **17** | `OcrReviewScreen` (`/ocr-review`) | `lib/features/ocr/presentation/ocr_review_screen.dart` | Language dropdown (eng/hin/guj), Fields, Save | **PASS** | Fast single-document OCR |
| **18** | `ExtractionReviewScreen` (`/extraction-review/:id`) | `lib/features/ocr/presentation/extraction_review_screen.dart` | Search, 4 Filters, Edit pencil, Drawer raw text | **PASS** | 12-schema selective review |
| **19** | `PasswordDashboardScreen` (`/passwords`) | `lib/features/passwords/presentation/password_dashboard_screen.dart` | Health audit card, Metrics tiles, FAB add | **PASS** | Password manager home |
| **20** | `PasswordListScreen` (`/passwords-list`) | `lib/features/passwords/presentation/password_list_screen.dart` | Search bar, Category chips, Sort, Credential tiles | **PASS** | Filterable password list |
| **21** | `AddEditPasswordScreen` (`/add-password`) | `lib/features/passwords/presentation/add_edit_password_screen.dart` | Website, Username, Password, Generator, Save | **PASS** | Rejects ATM PIN/CVV/OTP |
| **22** | `PasswordDetailsScreen` (`/password/:id`) | `lib/features/passwords/presentation/password_details_screen.dart` | Reveal Eye, Copy pass, Copy user, Edit, Delete | **PASS** | In-place unmask & 60s hide |
| **23** | `PasswordGeneratorScreen` (`/password-generator`)| `lib/features/passwords/presentation/password_generator_screen.dart`| Length slider, Character toggles, Refresh, Copy | **PASS** | Cryptographic random entropy |
| **24** | `PasswordSecurityDashboardScreen` (`/password-security`) | `lib/features/passwords/presentation/password_security_dashboard_screen.dart` | Score gauge, Weak list, Reused list, Old list | **PASS** | Local health analyzer |
| **25** | `BankVaultDashboardScreen` (`/bank-vault`) | `lib/features/bank_vault/presentation/bank_vault_dashboard_screen.dart` | Strict privacy banner, Account tiles, Search, FAB | **PASS** | Bank reference manager |
| **26** | `BankAccountListScreen` (`/bank-accounts-list`) | `lib/features/bank_vault/presentation/bank_account_list_screen.dart` | Search bar, Account cards, Reveal Eye, Copy IFSC | **PASS** | Fast account selector |
| **27** | `AddEditBankAccountScreen` (`/add-bank-account`) | `lib/features/bank_vault/presentation/add_edit_bank_account_screen.dart` | Bank name, Holder, Account #, IFSC, Type, Save | **PASS** | Rejects card PIN/CVV/OTP |
| **28** | `BankAccountDetailsScreen` (`/bank-account/:id`) | `lib/features/bank_vault/presentation/bank_account_details_screen.dart` | Reveal Eye, Copy Account, Copy IFSC, Edit, Delete | **PASS** | In-place unmask & 60s hide |
| **29** | `SearchScreen` (`/search`) | `lib/features/search/presentation/search_screen.dart` | Real-time search input, Category filters, Results | **PASS** | Metadata-only query index |
| **30** | `FavoritesScreen` (`/favorites`) | `lib/features/favorites/presentation/favorites_screen.dart` | Bookmarked documents list, Unfavorite toggle | **PASS** | Single-tap access |
| **31** | `ExpiryDashboardScreen` (`/expiry-dashboard`) | `lib/features/expiry/presentation/expiry_dashboard_screen.dart` | Expired alert, Upcoming 30 days, Filter by category | **PASS** | Calculates days remaining |
| **32** | `ActivityTimelineScreen` (`/timeline`) | `lib/features/timeline/presentation/activity_timeline_screen.dart` | Audit trail, Filter by action, Timestamp details | **PASS** | Encrypted activity events |
| **33** | `TrashScreen` (`/trash`) | `lib/features/trash/presentation/trash_screen.dart` | Restore button, Permanently Delete, Empty Trash | **PASS** | 2FA gated cryptographic shred |
| **34** | `GeneralSettingsScreen` (`/settings`) | `lib/features/settings/presentation/general_settings_screen.dart` | Security link, Theme selector, Storage info, About | **PASS** | Primary app settings |
| **35** | `SecuritySettingsScreen` (`/security-settings`) | `lib/features/settings/presentation/security_settings_screen.dart` | Change PIN, Auto-lock duration, Screen security | **PASS** | 2FA-gated security settings |
| **36** | `StorageInfoScreen` (`/storage-info`) | `lib/features/settings/presentation/storage_info_screen.dart` | Space breakdown (docs, thumbnails, cache), Purge | **PASS** | Ephemeral cache sweeper |
| **37** | `ThemeSelectionScreen` (`/theme-selector`) | `lib/features/settings/presentation/theme_selection_screen.dart` | 4 Themes (RupeeFlow, Midnight, Forest, Sunset) | **PASS** | Real-time dynamic theme |
| **38** | `AboutPrivacyScreen` (`/about-privacy`) | `lib/features/settings/presentation/about_privacy_screen.dart` | Zero-knowledge architecture explanation, Licenses | **PASS** | Air-gap disclosure |
| **39** | `CategoryManagementScreen` (`/category-management`)| `lib/features/categories/presentation/category_management_screen.dart`| Add category, Edit category, Color picker, Icon picker| **PASS** | Custom category taxonomy |
| **40** | `ErrorDialog` / `ConfirmDialog` | `lib/core/widgets/error_dialog.dart` | Title, Error message, Confirm/Cancel buttons | **PASS** | Themed modal dialogs |

---

## 2. INVENTORY VERIFICATION SUMMARY

Every screen and control in SafeVault has been systematically audited. All 40 screens and dialogs are verified to have active, robust state management, zero unhandled exceptions, zero dead buttons, and full responsive layout compliance.

