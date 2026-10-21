# Activation keys

Manual issuance and the Task 34 subscription contract share AIM1 signatures. Real Waffo integration remains unavailable. There are no user accounts or device bindings.

## Key contract

`AIM1.<base64url(payload JSON)>.<base64url(signature)>` uses unpadded base64url. The Ed25519 signature covers the exact UTF-8 payload bytes, not the encoded segment.

```json
{"v":1,"lic":"abcdefghijklmnop","plan":"pro","iat":"2026-10-21","exp":"2027-10-21"}
```

`lic` is a random 16-character base64url ID generated from 12 random bytes. Dates use `YYYY-MM-DD`. Manual issuance uses UTC dates and adds 365 days. Subscription issuance uses verified provider periods instead of a fixed year. The app uses the local calendar date and accepts the expiry day inclusively. No email, name, order reference, or device ID appears in a key.

The app verifies the signature, version, plan, ID, dates, and expiry locally. It stores the original key in UserDefaults `licenseKey` and verifies again on launch and snapshot refresh. It never trusts a saved Pro boolean. Invalid replacement input preserves an existing valid key.

## Worker interface

`POST /v1/license/issue` requires `Authorization: Bearer <ADMIN_TOKEN>` and this body.

```json
{"order_ref":"founder-order-1","days":365}
```

`order_ref` must be nonblank and at most 64 characters. Founding licenses accept exactly 365 days. Bodies are limited to 1024 bytes and reject additional fields. The response is `{"key":"AIM1...."}`. Missing or incorrect authorization returns 401. Invalid input returns 422.

D1 migration `0002_licenses.sql` stores `lic`, `plan`, `iat`, `exp`, `order_ref`, and `created_at`. Migration `0005_subscriptions.sql` adds an idempotent manual order mapping and a key registry. Concurrent retries for one order return the same persisted key and expiration. The migration maps an existing duplicated order to the earliest issuance, with license ID as the tie breaker. Every previously signed manual key remains valid through its expiration. Manual keys never become subscriptions automatically. There is no listing endpoint or immediate offline revocation.

## Reviewer setup and manual issuance

These steps require the reviewer's deployment authorization. They are not run by Task 23.

1. Run `node server/ranking-worker/scripts/gen_keypair.mjs` in a private terminal. It prints JSON with `privateKey` as PKCS8 base64 and `publicKey` as raw 32-byte base64. Protect the private key and keep it out of source control and shared logs.
2. Set Worker secrets `LICENSE_PRIVATE_KEY` and `ADMIN_TOKEN` through the reviewer's secret-management process. Apply the D1 migration and deploy the Worker.
3. Replace `License.publicKeyBase64` in `macos/Sources/AIMaster/License.swift` with the public key. The placeholder deliberately rejects activation.
4. Set `ADMIN_TOKEN` and `LICENSE_ISSUE_URL` in the issuing shell. The URL must be the deployed HTTPS `/v1/license/issue` endpoint. Run `scripts/issue_key.sh <order_ref>` from this checkout, with `.venv/bin/python` available. The script prints the response and reports HTTP failures.
5. Enter the key in Settings or open `aimaster365://activate?key=<key>`. Verification is local. Automatic refresh is a separate opt-in, explained beside activation.

`PurchaseConfiguration.unavailable` disables checkout and management. Adding a URL alone cannot enable checkout. See the Task 35 release gates below.

## Local fourteen-day Pro trial

The trial starts only when the user presses **Start trial** in Settings or a contextual advanced-feature entry. Installing, launching, viewing an advanced feature or opening checkout never starts it. No card, account, checkout, automatic charge or network request is involved. Buying a subscription is a separate action; the trial never converts automatically.

Entitlement is Free, Trial(until), or Licensed(payload). A valid signed license takes precedence. Trial access uses the same ProFeatures gates as a license, including growth, weekly review, any-card practice and expanded rankings. Dimension comparison still requires separate score-sharing consent. Trial start does not enable public downloads, score sharing or notification permission.

App-owned UserDefaults stores a single `proTrial` JSON data record with `consumed`, UTC epoch `start`, `end`, `maximumObserved`, `expired` and an optional terminal `reason`. `end = start + 14 × 86400` seconds and is exclusive. Repeated starts do not reset dates. Launch, snapshot refresh, foreground/wake and a dedicated expiry timer re-evaluate access. Timezone changes only affect displayed dates. A clock reading below the persisted maximum ends the trial permanently. Reaching the deadline also persists terminal expiry before returning Free. Corrupt existing state becomes a consumed, expired record and cannot start again.

Expiry hides existing advanced views and removes Pro-only reminders without requesting permission. Daily Free practice and all local history remain available and unchanged. No engine score, practice event or achievement depends on entitlement. Deliberately deleting app state or reinstalling to reset it is an accepted limitation of this local trial. No Keychain, hardware fingerprint or AI-tool credentials are used to prevent that abuse.


## Subscription provider contract

Task 34 implements the server contract with an injected test fake. `PaymentProvider.verifyWebhook(rawBytes, headers)` authenticates the original bytes before returning normalized data. `getSubscription(providerRef)` supplies an authoritative snapshot for refresh and ordering reconciliation.

Normalized data contains `eventId`, `subscriptionRef`, `orderRef`, `revision`, `periodStart`, `paidThrough`, `status`, `autoRenew`, and `managementURL`. References are bounded opaque provider IDs. Revision is a nonnegative, subscription-wide monotonic safe integer. A null revision requires reconciliation. An unavailable or still unordered snapshot fails closed. Conflicting snapshots at the same revision also fail closed. Status is one of `paid`, `pending`, `failed`, `cancelled`, `refunded`, or `revoked`. Period instants use UTC `Z`; the paid-through boundary is exclusive. A management URL must already be authenticated by the provider adapter and must use HTTPS without URL credentials or a fragment. No management URL is returned by the refresh API.

The production router constructs `WaffoPaymentProvider` directly. Its methods return unavailable. Neither request data nor environment flags can select the test fake. `POST /v1/waffo/webhook` therefore returns HTTP 503 with `{"status":"unavailable"}`. The raw body is bounded to 64 KiB. Webhook success through the injected test handler returns only `{"status":"accepted"}`, never a key.

`TODO(WAFFO_VERIFIED_INTEGRATION)` remains a release blocker. Official signature and API documentation, authenticated sandbox fixtures, ordering rules, merchant renewal, refund, cancellation management, and receipt/support recovery checks are required. No Waffo headers, signature algorithm, event names, checkout URL, or recovery URL are assumed. Fake-backed tests do not verify a real payment integration.

## Subscription persistence and key dates

One atomic D1 batch deduplicates the verified event, records the paid order/period, and updates the subscription projection. Unique event IDs, order IDs, and subscription/period-start pairs prevent retries or concurrent deliveries from adding entitlement. A stable random `lic` maps to one provider subscription. Event fingerprints reject reused event IDs with changed contents. A terminal refund/revocation revision prevents stale or later active events from reopening the subscription. Cancel-at-period-end preserves the verified paid-through boundary. Pending and failed events can change renewal status but cannot extend entitlement.

The registry persists one signed key per license and paid period using insert-if-absent. Signing and registry insertion follow the entitlement transaction. A crash or signing failure leaves no successful response; retry completes issuance with the same license and period. It never adds a year. Only the explicit no-store issuance and refresh responses contain keys. Billing rows do not reference ranking installation UUIDs. Storage contains provider references, normalized state, revision/fingerprints, periods, management URL, issued keys, and bounded per-license throttle counters. It contains no raw webhook, email, card data, usage event, or AI-tool credential. Application handlers do not log requests, authorization, keys, or provider exceptions. Infrastructure access-log configuration still requires operator review before deployment.

For an exclusive UTC paid-through instant `T`, inclusive `exp` is the UTC date of `floor(T / 86400000) * 86400000 - 86400000`. For example, both `2028-03-01T00:00:00Z` and `2028-03-01T15:00:00Z` produce `2028-02-29`. Partial final days are omitted. The contract uses UTC calendar dates; the existing app compares dates locally, so this is day-granularity offline access rather than instant-accurate enforcement across timezones. No client clock or timezone behavior changes in Task 34.

Renewed keys retain the first paid period's issuance date and the same `lic`, so a renewal signed before the next period starts works immediately. Refresh extends through adjacent verified paid periods only. A future period separated by a payment gap cannot extend the current key. A future initial period remains pending. Leap years follow provider dates. An already distributed signed key remains usable offline through its signed expiration even after cancellation or refund. Server revocation blocks future refresh, not offline signature verification.

## Accountless refresh

`POST /v1/license/refresh` accepts exactly this JSON body, with no query parameters, account, app admin token, or AI-tool credentials.

```json
{"lic":"abcdefghijklmnop","key":"AIM1.<payload>.<signature>"}
```

The body limit is 1024 actual bytes, including chunked bodies. `lic` is exactly 16 base64url characters. The key is at most 768 characters. The server checks canonical AIM1 encoding, the Ed25519 signature, exact payload fields and dates, the matching license ID, and known issuance. Expiration is not an authentication failure; an expired, authentic old key can recover after a verified renewal. A guessed ID, missing proof, a forged key, or a valid signature for an unissued payload cannot recover a license. Pre-migration manual proofs match their original stored signed metadata.

Refresh reads authoritative provider state before issuing a subscription key. An outage returns retryable unavailable without extending time. A terminal subscription does not call the provider or grant another key. Valid proofs share a limit of ten refresh attempts per license per UTC minute, persisted in D1. Counters have one row per known license; rejected unauthenticated proofs do not create rows. Concurrent requests cannot bypass the limit. HTTP 429 includes `Retry-After: 60`.

All license handler responses, including errors, use `Cache-Control: no-store`.

| HTTP | JSON status | Meaning |
|---|---|---|
| 200 | `active` | Contains `key`, `auto_renew`, and exclusive UTC `paid_through`. |
| 200 | `manual` | Authentic manual authorization; no subscription or extra key. |
| 200 | `pending` | A verified current paid period is not available yet. |
| 200 | `expired` | Verified paid access, or its last full UTC day, has ended. |
| 200 | `revoked` | Refund or revocation blocks refresh. |
| 401 | `unauthorized` | Proof is invalid, mismatched, or unknown. |
| 422 | `invalid` | Body shape, size, or field format is invalid. |
| 429 | `rate_limited` | Retry after the current attempt window. |
| 503 | `unavailable` | Provider, ordering, signing, or persistence cannot be verified. |

Recovery without the original key requires the verified merchant receipt/support flow. No license lookup or account enumeration API exists. These messages document intended client wording; Task 35 owns client transport and translation.

- 订阅仍有效，可重新获取激活码 / Your subscription is still active. You can refresh your activation key.
- 付款仍在确认中 / Payment is still being confirmed.
- 请使用购买收据联系支持恢复授权 / Use your purchase receipt to contact support for license recovery.

Task 34 does not configure secrets, apply production migrations, deploy, enable checkout, or run merchant transactions.


## Task 35 client renewal and purchase disclosure

`License.authenticate` verifies a signed proof without granting entitlement. `verify` also checks inclusive local-calendar expiry. Importing an authentic expired proof preserves it for recovery but does not activate Pro. A replacement is a single UserDefaults key write only after current signature, same license ID and nondecreasing expiry validation. Errors, malformed data, a wrong license or provider outage preserve the previous proof and local history. A signed key continues offline through expiry; an expiry timer, launch, refresh and foreground/wake revalidate access. There is no offline extension. Manual keys are compatible and show manual authorization after the worker confirms `manual`; they are not automatically polled thereafter.

Automatic refresh defaults off. The activation UI explains that enabling it sends only the app's own signed key and license ID, never usage data. Launch, wake and foreground trigger a detached-from-analysis async check within seven calendar dates of signed expiry or after expiry. Automatic attempts are limited to one per rolling 24 hours, with one explicit retry in the same window. Attempts persist across restart; clock rollback does not clear throttling. Concurrent triggers share one in-flight operation. An explicit Refresh action may request renewal even with automation off or outside the seven-day window. Free/trial state without an authentic key cannot request refresh. An explicit action is separate consent for that request.

The separate license transport lives in `ScoreReporter.swift`. It derives `/v1/license/refresh` from the fixed score-worker origin and uses ephemeral HTTPS POST with exactly `lic,key`, no authorization/admin token, URL credentials, cookie store, redirects or cache. Requests time out at 15 seconds. Response streaming is capped at 8192 bytes before parsing. Score payload fields and consent remain unchanged. The engine remains network-free. Infrastructure may process IP metadata; this is a payload privacy boundary.

Every purchase entry routes to the same complete terms view before any browser open. It discloses the founding USD $12 yearly price and yearly automatic renewal, cancellation through the verified receipt-management entry before next renewal, access through the paid period, receipt-based support/refund contact and the no-card local trial that never converts to paid. No lifetime price guarantee is made. Local signed-key expiry and provider-confirmed paid-through are separate labels; the next billing date is not inferred from either. A click or browser return means pending confirmation, never activation or successful cancellation. An authentic key is still required for Pro. Verified `auto_renew: false` can display provider-confirmed cessation of renewal while retaining signed access.

Real checkout remains blocked. Production `PurchaseConfiguration.unavailable` has no destinations or verified terms/integration flags. A future reviewed configuration must include exact allow-listed HTTPS hosts, credential/fragment/query-free checkout and management destinations and verified merchant terms and integration. A management URL or documented verified receipt cancellation instructions must exist before real checkout; this implementation requires the management URL. Management opens only on explicit user action. There is no cancellation API or background charge/cancel action. No Waffo URLs, portal semantics or support destinations were invented. Receipt-based support wording describes the required flow, not a tested merchant service.

`course_sources` is an optional public/bundled catalogue of at most 100 exact `{code, practice_id, title:{zh,en}}` entries. Codes use 1–32 ASCII letters, digits, `_` or `-`, are unique, and refer to existing stable practice IDs. Both titles are bounded to 120 characters. The shipped catalogue is empty in both byte-identical JSON files. Synthetic test codes are not creator approvals. Swift validates cached metadata and resolves the source to an existing practice; the bundled fallback is empty. A selected code stays in app defaults and offers that practice alongside the free daily learning path. Only a separate, unsaved checkout selection includes `source=<reviewed code>`; editing the code clears that selection. Blank, unknown and invalid values are omitted. The code never enters license refresh or ranking, and carries no device, proof, history or reward data.

Task 35 fake-backed tests and local renders verify our client/server contract. They do not verify real Waffo checkout, renewal, cancellation, refund, management or receipt recovery. Those remain release blockers alongside production public-key configuration. No secrets, deployment, packaging, app launch or merchant transactions are part of this task.


## Task 37 integrated acceptance and remaining release blockers

See [Phase 4 acceptance](testing/phase4-acceptance.md) for commands, actual results, synthetic artifacts, request contracts and the observer checklist. Local practice, explicit trial, expiry, signed-key import, cancel-at-period-end, same-license renewal and offline expiry are exercised with separate injected engine/client/worker harnesses. Synthetic Ed25519 signatures and local D1 prove our contract only. Imported keys and browser returns are not evidence of new purchases; no paid demand or population retention is established.

Waffo real webhook signatures, sandbox annual renewal, refund/cancellation and receipt recovery remain blocked pending a verified provider integration and test access. Production public-key configuration, real public-source compatibility, app signing/notarization, target-user usability and an agreed baseline/head performance budget remain unverified. Production checkout is still unavailable. The task's explicit no-package/no-launch constraint leaves an app bundle, controlled running-app request capture, manual keyboard/VoiceOver/reduced-motion/popover checks and observer video unrun. Offscreen synthetic PNGs are not a running-app usability result. No new production behavior, public-key format, live endpoint, permission, scheduled job or payment action was introduced.
