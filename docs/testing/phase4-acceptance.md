# Phase 4 acceptance — Task 37

Date: 2026-10-21. Branch: `feat/macos-v1`. Baseline: `539c9ff` (Task 36).
Scope: synthetic local acceptance only; no personal logs, account credentials, merchant requests, deployment, packaging or application launch.

Status vocabulary: 已验证 / Verified; 未运行 / Not run; 未验证 / Unverified; 受阻 / Blocked.

## Evidence and limits

The Python replay injects dates and synthetic homes. It chooses no sources first, then Claude Code explicitly; copy/start does not verify old evidence; a new structured event verifies practice; a usage-only event on a new date does not verify reuse; another capability event does. Repeated snapshots preserve attempts, observations, reuse dates, achievements and history. Local diagnostic trial starts deduplicate and imported activation never becomes a purchase. Weekly review refuses incomplete and differently versioned windows. Empty, unsupported, permission-denied and corrupted-progress paths are separate tests. Corrupted progress returns a sanitized error and remains untouched; it is not claimed to be recovered.

The Swift store replay injects a clock, local trial persistence, synthetic signed keys, fake engine commands and fake transports. It runs explicit trial, expiry, paid-key import, verified cancel-at-period-end, same-license renewal, outage and offline signed expiry. Local practice and the snapshot remain available after expiry. The worker uses installed dependencies, local D1 and a fake verified provider to replay annual payment, cancellation, renewal, duplicate callbacks and outage without manufacturing periods or new licenses. These are contract proofs across separate test harnesses, not a live merchant-to-app transaction.

TDD evidence: the first run of `test_phase4_flow.py` ended `1 failed, 3 passed`: the release-gate test failed with `FileNotFoundError` for this required report. The local flow tests already passed on Task 36. This task implements missing acceptance coverage and documentation, not a claimed production bug fix.

## Commands and actual results

| Check | Status | Actual command / summary |
|---|---|---|
| Targeted Python acceptance | 已验证 / Verified | `.venv/bin/python -m pytest tests/engine/test_phase4_flow.py tests/engine/test_snapshot.py tests/engine/test_privacy.py tests/engine/test_build_engine.py tests/engine/test_package_app.py tests/harvest/test_harvest.py -q --basetemp=.pytest_cache/tmp` — `52 passed, 2 skipped in 1.06s` |
| Full Python | 已验证 / Verified with baseline exceptions | `.venv/bin/python -m pytest -q --basetemp=.pytest_cache/tmp` — `2 failed, 619 passed, 2 skipped, 162 warnings in 3.51s`; only `tests/test_analytics_api.py::test_get_30day_analytics` and `::test_export_analytics_csv` fail |
| Swift build | 已验证 / Verified | `cd macos && swift build --disable-sandbox --cache-path "$PWD/../.pytest_cache/swift-cache"` — `Build complete! (0.17秒)` |
| Full Swift | 已验证 / Verified | Same cache flags with `swift test` — `Executed 119 tests, with 12 tests skipped and 0 failures (0 unexpected) in 0.604 (0.609) seconds`; opt-in renders run separately below |
| Worker / local D1 | 已验证 / Verified | `cd server/ranking-worker && npm test` — `Test Files 3 passed (3)`; `Tests 48 passed (48)`; `Duration 561ms` |
| Rebuilt standalone engine | 已验证 / Verified | `RUN_BUILD_TESTS=1 .venv/bin/python -m pytest tests/engine/test_build_engine.py -q --basetemp=.pytest_cache/bundle-tmp` — `2 passed in 8.41s`; invokes `scripts/build_engine.sh`, executes `dist/365engine` with synthetic `--home`/`--state-dir`, no developer Python on PATH, both locales, copy/self/trial-start replay |
| Offscreen previews | 已验证 / Verified | `cd macos && swift test --disable-sandbox --cache-path "$PWD/../.pytest_cache/swift-cache" --filter RenderPreviewTests` with environment below — `Executed 11 tests, with 0 failures (0 unexpected) in 7.959 (7.961) seconds` |
| Real app package | 未运行 / Not run | `RUN_PACKAGE_TESTS` not set; explicit no-package instruction overrides plan's packaging step |

All Python commands use `.venv/bin/python`. Logs are local untracked `.pytest_cache/task37-{python,swift-build,swift,worker,bundle,render}.log`. Swift uses `CLANG_MODULE_CACHE_PATH`, `SWIFTPM_MODULECACHE_OVERRIDE` and `TMPDIR` under `.pytest_cache/swift-cache/`; default compiler caches were unwritable. `--disable-sandbox` avoids nested build sandboxing. Worker initially failed to listen on localhost (`EPERM`); its rerun was granted a sandbox exception for local D1. The standalone engine initially failed on `semctl: Operation not permitted`; its granted rerun passed. No installs or service logins occurred.

An additional combined full-suite/render-environment experiment failed only `V2Tests.testContentArgumentOnlyWhenFileExists`: the pre-existing test assumes `--content` comes after the default argument list, whereas setting `AIMASTER_STATE_DIR` puts `--state-dir` after content. This is a test-order assertion incompatibility under the optional state override, not a changed engine contract. The requested normal full suite and separately filtered isolated renderer are the acceptance runs; the unrelated V2 test and production argument builder were not changed. The experimental output is `.pytest_cache/task37-swift-render-full.log`.

## Synthetic artifacts

Use `RENDER_OUT=$PWD/../.pytest_cache/p4` from `macos` with `RenderPreviewTests` and `AIMASTER_PREVIEW_HOME` pointing only at a synthetic home. All PNG/JSON output stays under `.pytest_cache/` and is intentionally untracked. The new matrix renders all three tab bodies inside a 440×720 scroll viewport in zh/en and light/dark environments. Reduced motion is a read-only SwiftUI system environment on this SDK; changing the user's global accessibility setting was not authorized, so that manual check remains unrun. A render is not proof of keyboard navigation, real popover interaction or VoiceOver behavior.

Renderer environment: `RENDER_OUT=$PWD/../.pytest_cache/p4`, `AIMASTER_ENGINE=$PWD/../dist/365engine`, `AIMASTER_PREVIEW_HOME=$PWD/../.pytest_cache/p4-preview-home`, `AIMASTER_STATE_DIR=$PWD/../.pytest_cache/p4-engine-events` from `macos`. The preview home is copied only from repository synthetic fixtures. No default personal state directory is used for renderer mutation commands. Request-capture assertions use fakes; they do not write signed proofs to exported artifacts.

Artifacts include `p4-matrix-{checkup,today,training}-{zh,en}-{light,dark}.png` (12 files, each 880×1440 pixels for a 440×720 point viewport), `p4-share-{zh,en}-{false,true}.png`, `p4-subscription-{paywall,pending,offline,cancel-at-period-end}-{zh,en}.png`, practice/calendar/history/trial/source previews and synthetic JSON. `p4-artifacts.json` indexes the local PNGs. Visual inspection covered all four exported share cards, the zh check-up/training viewports, en dark Today viewport, zh full paywall and en offline paywall. Inspected cards show all 24 reviewed capability titles and the certification disclaimer, with score/period only when selected; no private fields or unintended text clipping were seen. A viewport intentionally clips the scrollable content below its bounds; actual scrolling is not verified.

## Product request inventory

| Request/action | Consent and destination | Exact application data | Verification boundary |
|---|---|---|---|
| Public GET | Public-download opt-in; `https://raw.githubusercontent.com/KenichiXXX/365-ai-master/content/daily.json` | No body, account credentials or custom telemetry headers | Fake downloader/store gate and fixed-URL privacy test; live public-source compatibility remains unverified |
| Versioned score POST | Anonymous ranking opt-in; `https://365aimaster-ranking.viberankworkersdev.workers.dev/v1/score/1` | Only `device_token`, `score`, `dims` (routing/timing/context/leverage), `app_version` | Fake request capture, local worker version/cohort tests; random installation UUID is not a person identifier |
| License refresh POST | Automatic-refresh opt-in, or explicit refresh consent; same origin `/v1/license/refresh` | Only `lic,key`; signed proof is intentionally required here | Fake bounded transport; no score UUID, history, course source or admin token |
| Public repository/release open | Explicit user action; validated public content URL | Public URL only | Public-content/link tests; no install or terminal execution |
| Checkout / manage open | Explicit action after terms; only verified configured HTTPS destinations | Optional separately selected reviewed source code on checkout | Production configuration unavailable; no live open attempted |
| Share / feedback | Explicit preview then copy or user-chosen save | Typed share whitelist / sanitized feedback enums and counts | Local-only; copy/save is not publication or a purchase |

`SnapshotStoreTests.testPhase4TrialPaymentRenewalAndAllNetworkOffPreserveLocalPractice` keeps public downloads, rank and automatic license refresh off, including after importing an authentic proof, while practice works. Injected transports see zero product requests until explicit license-refresh consent. Other transport tests capture exact enabled payloads; worker tests reject cross-purpose fields. Prompt/path/argument/token sentinels are rejected from CLI exports, progress, weekly exports, request bodies and worker responses; existing share tests check metadata and whitelist exports. Scan cursors necessarily retain source paths internally and are excluded from exports. License proofs are deliberately present only in license refresh, not in ranking or sharing. Infrastructure may process IP metadata; application payload tests make no stronger claim.

No controlled running-app network trace was captured: launching the app is expressly prohibited in this task. Fake transport coverage must not be relabeled as that trace.

## Release gates

| Item | Status | Evidence still required |
|---|---|---|
| Waffo real signature verification | 受阻 / Blocked | Verified provider protocol, test access, authentic signed webhook fixtures |
| Merchant sandbox annual renewal | 受阻 / Blocked | Real sandbox purchase/renewal and signed period correspondence |
| Refund and cancellation | 受阻 / Blocked | Verified provider status, management portal, paid-through behavior |
| Merchant receipt recovery | 受阻 / Blocked | Actual receipt/support recovery with no account assumptions |
| Real public-source compatibility | 未验证 / Unverified | Authorized live download and supported real source formats; synthetic sources alone are insufficient |
| Production public key, signing and notarization | 未运行 / Not run | Real key configuration, signed/notarized app and clean-machine verification |
| Package / reviewable local trial app | 未运行 / Not run | Explicit user instruction forbids packaging and launching; engine and Swift builds do not establish an app bundle |
| Controlled running-app network capture | 未运行 / Not run | Synthetic state, all three request gates off/on and explicit URL opens in an authorized app run |
| Keyboard, VoiceOver, reduced motion, click-outside/Esc and actual scrolling | 未运行 / Not run | Manual 440×720 popover checks with assistive technology; offscreen rendering does not prove interaction |
| Observer review video | 未运行 / Not run | Authorized synthetic application session; no video fabricated from static renders |
| External usability / adoption / retention / paid demand | 未验证 / Unverified | Consent-based target-user observation and actual commercial evidence |
| Performance regression budget | 未验证 / Unverified | An agreed fixture/budget and interleaved baseline/head cold/incremental/UI-open measurements; no agreed budget and no app launch, so no performance pass |

Keep `支付接入待验证，暂不可购买 / Payment integration is not verified. Checkout is unavailable`. Fake-backed success must never enable live checkout. No application production behavior or spec promises are changed by this acceptance task.

## Money, ranking and exclusion audit

Check founding USD $12/year and yearly automatic renewal disclosure, no-card/non-converting 14-day local trial, separate signed expiry/paid-through wording, API-equivalent costs rather than savings, and worldwide wording only at `total >= 20`. The actual string scan is `.pytest_cache/p4-copy-audit.json` (30 matches across engine content, Swift sources and both localizations). Sources reviewed include `License.swift` purchase terms, `SettingsView.swift` trial controls, `ScoreReporter.swift` early/worldwide captions, `CheckupTab.swift` consent CTA, `Snapshot.swift` API-equivalent labels and engine content. Existing license, price, ranking, trial and both-language rendering tests are the executable coverage. The pre-consent Check-up CTA uses worldwide wording but makes no numeric percentile claim; the returned numeric caption preserves the 19/20 boundary. This does not establish population representativeness. Real payment/cancellation wording remains conditional on the release gates above.

The standalone research document is not present in this worktree; this exclusion audit uses the explicit §11 list recorded in the implementation plan. Research §11 exclusions preserved: no auto-edit, installation, automatic terminal commands, telemetry/growth accounts, hardware fingerprint, referral rewards, annual animation, complex efficiency experiment or new competition system. Reviewed exceptions remain yearly automatic renewal and worldwide ranking at 20 installations. This task adds tests/docs only. No job or invitation is installed; no external send, public release, transaction or production modification occurs.

## One-user observer checklist (prepared, not sent)

1. With all optional networking off, identify the three tabs and choose allowed sources or decline them.
2. Find one relevant practice; preview/copy or start it. Check that old usage is not called a newly verified practice.
3. Produce a supported synthetic event, return to check the evidence label, then reuse it on another date. Distinguish self-report, observation and reuse.
4. Inspect gap/version-aware weekly review; start a trial explicitly; verify Free history and practice remain after synthetic expiry.
5. Inspect full yearly terms and disabled checkout; exercise fake cancellation, renewal and offline expiry without charging or opening merchant pages.
6. Preview/save/copy a sanitized share card and feedback; confirm score is optional and nothing is published automatically.
7. Once app launch is separately authorized, check cancel/retry, exact notification destination, keyboard/VoiceOver, all appearance modes, scrolling and popover dismissal; record confusion and time to first practice/return. No retention or causal claims from one observer.

## Deviations from the plan

- No app packaging, launch, running-app trace or observer video: the task-specific user instruction prohibits packaging/launching. Prepared build outputs, screenshots, limitations and checklist are reviewable locally; a trial app bundle is not claimed.
- No live public download or merchant sandbox exercise: network/test access is unavailable. Fake-backed passes leave those release gates open.
- No performance regression pass: the plan requires baseline/head interleaving and an agreed budget before claiming a pass. Neither a UI-open measurement nor a budget is available; no benchmark numbers were invented.
- Swift cache/sandbox flags and local-runtime sandbox exceptions were necessary for the requested offline test commands in this restricted environment. Reduced-motion mode could not be injected through the SDK's read-only environment.
- Task 37 contains no explicit commit message. Use `test: prove phase 4 integrated loop and document release blockers` with the required Codex trailer.
