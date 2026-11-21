# SafeVault Improvement Roadmap

1. Migrate from `pdfx` to a plugin using built-in Kotlin to remove the legacy KGP warning.
2. Add widget/integration tests for camera lifecycle and document viewer disposal.
3. Add Kotlin unit tests for incoming share dedup and MIME/signature mismatch.
4. Add a transactional storage bundle for atomic PIN salt/wrapped-share updates.
5. Add hardware-in-the-loop verification for Keystore auth-token timing.
6. Expand OCR confidence calibration for weak/ambiguous fields.