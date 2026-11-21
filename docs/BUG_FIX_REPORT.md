# SafeVault Bug Fix Report

## Summary
Repaired router stability, initial 2FA setup gating, PIN-change biometric timing, OCR async safety, import/save integrity, document viewer PDF handling, and native share hardening. Added regression tests. Debug and release APKs build successfully. Merged manifests contain no `INTERNET` or `ACCESS_NETWORK_STATE`.

## Changed Files
- `android/app/src/main/kotlin/com/vault/vault/MainActivity.kt`
- `lib/core/routes/app_router.dart`
- `lib/core/security/key_management_service.dart`
- `lib/features/authentication/presentation/two_factor_verification_dialog.dart` (deleted)
- `lib/features/documents/presentation/add_document_screen.dart`
- `lib/features/documents/presentation/document_viewer_screen.dart`
- `lib/features/documents/presentation/incoming_share_preview_screen.dart`
- `lib/features/ocr/presentation/ocr_review_screen.dart`
- `lib/features/onboarding/presentation/initial_security_setup_screen.dart`
- `lib/features/settings/presentation/security_settings_screen.dart`
- `test/route_and_category_audit_test.dart`

## Key Fixes
1. Router no longer recreates on every `VaultSession` notification; uses `refreshListenable` and disposes on provider disposal.
2. Initial setup requires biometric hardware/enrollment and prompts biometrics immediately before Keystore key generation/wrapping.
3. PIN change prompts biometrics immediately before unwrapping the biometric share; preserves S_bio to avoid Keystore orphaning.
4. OCR review uses request IDs, mounted checks, recoverable error UI, and stale-result protection.
5. Add Document validates category before encryption, keeps raw inputs until DB success, deletes orphan encrypted files on failure, marks extraction failed honestly, and handles vault lock via `getMasterKeyOrThrow`.
6. Incoming share import mirrors the same integrity and cleanup behavior.
7. Document viewer opens one PDF document/controller, closes resources if disposed during load, and wipes buffers.
8. MainActivity deduplicates incoming share intents, enforces MIME/signature consistency, zeroes sensitive byte buffers, and already validates outgoing share paths with canonical separators.

## Commands Run
- `flutter pub get`
- `flutter analyze`
- `flutter test`
- `flutter build apk --debug`
- `flutter build apk --release`
- `adb devices -l`

## Test Results
- `flutter analyze`: No issues found.
- `flutter test`: All tests passed (111 tests).

## Remaining Warnings
- `pdfx` applies the legacy Kotlin Gradle Plugin; Flutter warns this may break in future Flutter versions. No compatible migration was applied in this pass.

## Unreproducible / Blocked
- Physical device smoke test blocked: `adb devices -l` returned no connected devices.
- Real Android Keystore auth-token timing behavior cannot be verified without hardware.