# Activation keys

Task 23 uses manual issuance. Waffo integration is reserved for later. There are no user accounts or device bindings.

## Key contract

`AIM1.<base64url(payload JSON)>.<base64url(signature)>` uses unpadded base64url. The Ed25519 signature covers the exact UTF-8 payload bytes, not the encoded segment.

```json
{"v":1,"lic":"abcdefghijklmnop","plan":"pro","iat":"2026-10-21","exp":"2027-10-21"}
```

`lic` is a random 16-character base64url ID generated from 12 random bytes. Dates use `YYYY-MM-DD`. Issuance uses UTC dates and adds 365 days. The app uses the local calendar date and accepts the expiry day inclusively. No email, name, order reference, or device ID appears in a key.

The app verifies the signature, version, plan, ID, dates, and expiry locally. It stores the original key in UserDefaults `licenseKey` and verifies again on launch and snapshot refresh. It never trusts a saved Pro boolean. Invalid replacement input preserves an existing valid key.

## Worker interface

`POST /v1/license/issue` requires `Authorization: Bearer <ADMIN_TOKEN>` and this body.

```json
{"order_ref":"founder-order-1","days":365}
```

`order_ref` must be nonblank and at most 64 characters. Founding licenses accept exactly 365 days. Bodies are limited to 1024 bytes and reject additional fields. The response is `{"key":"AIM1...."}`. Missing or incorrect authorization returns 401. Invalid input returns 422.

D1 migration `0002_licenses.sql` stores `lic`, `plan`, `iat`, `exp`, `order_ref`, and `created_at`. There is no listing endpoint. `POST /v1/waffo/webhook` returns 404. Issuance creates a fresh license each time, so manual retries can create multiple licenses for the same order. There is no online revocation.

## Reviewer setup and manual issuance

These steps require the reviewer's deployment authorization. They are not run by Task 23.

1. Run `node server/ranking-worker/scripts/gen_keypair.mjs` in a private terminal. It prints JSON with `privateKey` as PKCS8 base64 and `publicKey` as raw 32-byte base64. Protect the private key and keep it out of source control and shared logs.
2. Set Worker secrets `LICENSE_PRIVATE_KEY` and `ADMIN_TOKEN` through the reviewer's secret-management process. Apply the D1 migration and deploy the Worker.
3. Replace `License.publicKeyBase64` in `macos/Sources/AIMaster/License.swift` with the public key. The placeholder deliberately rejects activation.
4. Set `ADMIN_TOKEN` and `LICENSE_ISSUE_URL` in the issuing shell. The URL must be the deployed HTTPS `/v1/license/issue` endpoint. Run `scripts/issue_key.sh <order_ref>` from this checkout, with `.venv/bin/python` available. The script prints the response and reports HTTP failures.
5. Enter the key in Settings or open `aimaster365://activate?key=<key>`. The app performs no activation network request.

`License.checkoutURL` remains `REPLACE_WAFFO_CHECKOUT`. Settings hides Buy and shows "Checkout opening soon" until the reviewer supplies the checkout URL. The four Pro descriptions use the approved sketch copy. Their implementations remain in Tasks 24 and 25 and are not acceptance evidence for Task 23.

## Local fourteen-day Pro trial

The trial starts only when the user presses **Start trial** in Settings or a contextual advanced-feature entry. Installing, launching, viewing an advanced feature or opening checkout never starts it. No card, account, checkout, automatic charge or network request is involved. Buying a subscription is a separate action; the trial never converts automatically.

Entitlement is Free, Trial(until), or Licensed(payload). A valid signed license takes precedence. Trial access uses the same ProFeatures gates as a license, including growth, weekly review, any-card practice and expanded rankings. Dimension comparison still requires separate score-sharing consent. Trial start does not enable public downloads, score sharing or notification permission.

App-owned UserDefaults stores a single `proTrial` JSON data record with `consumed`, UTC epoch `start`, `end`, `maximumObserved`, `expired` and an optional terminal `reason`. `end = start + 14 × 86400` seconds and is exclusive. Repeated starts do not reset dates. Launch, snapshot refresh, foreground/wake and a dedicated expiry timer re-evaluate access. Timezone changes only affect displayed dates. A clock reading below the persisted maximum ends the trial permanently. Reaching the deadline also persists terminal expiry before returning Free. Corrupt existing state becomes a consumed, expired record and cannot start again.

Expiry hides existing advanced views and removes Pro-only reminders without requesting permission. Daily Free practice and all local history remain available and unchanged. No engine score, practice event or achievement depends on entitlement. Deliberately deleting app state or reinstalling to reset it is an accepted limitation of this local trial. No Keychain, hardware fingerprint or AI-tool credentials are used to prevent that abuse.
