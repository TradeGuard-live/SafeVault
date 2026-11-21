# SafeVault Security Audit

## Authentication Policy
- Initial unlock: biometric then six-digit PIN.
- In-session protected actions: fresh biometric only.
- PIN change: may request current PIN.

## Key Management
- 2-of-2 XOR secret sharing (VMK = S_bio XOR S_pin).
- S_bio wrapped by hardware-backed Android Keystore key with biometric auth requirement.
- S_pin wrapped by PIN-derived KEK (PBKDF2 100k iterations).
- Setup prompts biometrics before Keystore generation/wrapping.
- PIN change preserves S_bio and avoids destructive key regeneration.

## Memory and Storage
- Master key is nulled on lock; clipboard cleared; ephemeral files wiped.
- Decrypted viewer buffers are wiped on disposal.
- Sensitive create-document byte buffers are zeroed.

## Native Security
- FLAG_SECURE enabled in MainActivity.
- Outgoing shares restricted to `cache/shared_exports`.
- Incoming shares validated by size limits and magic-byte signatures with MIME consistency.
- Incoming share intents deduplicated.

## Privacy
- No INTERNET or ACCESS_NETWORK_STATE permissions in merged manifests.
- Screenshot protection does not lock on transient inactive states.