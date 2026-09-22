# Controlled transport verification — build 214

**LOCAL-VERIFICATION-ONLY — NEVER MERGE, NEVER DISTRIBUTE.** This branch
(`build/214-transport-verification`, cut from `develop` at merge
`533770df` — PR #83, the debug-image installation fix) and every
temporary verification file on it exist to prove the corrected
crash-reporting pipeline with **exactly one permitted synthetic event**.
Build 214 must never reach a store, a tester channel or any device
beyond the local `wellapath_lowend` emulator. **Build 215 or higher is
the earliest potentially distributable candidate**, and only after the
store privacy declarations are updated with the five-field debug-image
disclosure.

## Why 214 exists — what 213 left open

The 213 run (2026-09-22, one event, audited fields-only) proved
transport delivery, the §2 privacy inventory and the release/tag
identity — and failed three criteria:

1. `user.geo` arrived POPULATED: the then-saved scrub rule (source
   `$user.geo`) did not operate at ingest;
2. `debug_meta` was entirely absent;
3. 0/25 frames symbolicated (`unknown_image`), downstream of (2).

Both failure causes are since addressed: the debug-image root cause
(the SDK's default-values phase reads `enableDartSymbolication` before
the app's callback can restore it, so `LoadDartDebugImagesIntegration`
was never installed) is fixed and merged in PR #83 (`6a61cd6`,
develop merge `533770d`), demonstrated locally end to end; and the
founder re-saved the scrub rule with a corrected source (below). 214
is the one controlled event that proves both live.

## Hard precondition — server-side geo scrub (founder, completed)

The Advanced Data Scrubbing rule on project `wellapath-mobile` is saved
as: Method **Remove** · Data type **Anything** · Source
**`$user.geo.**`** (corrected from the 213 run's `$user.geo`, which
demonstrably did not act on the stored event). Saved 2026-09-22.
**It remains OPERATIONALLY UNVERIFIED until this run's stored Event
JSON shows `user.geo` completely absent.** If the rule is not in place
at execution time, execution is blocked at step 0.

## What this run must prove (audit criteria)

1. **`user.geo` completely absent** from the stored Event JSON — the
   first operational verification of the corrected `$user.geo.**` rule.
2. **`debug_meta.images` limited to exactly the approved five-field
   allowlist** (`type`, `image_addr`, `debug_id`, `code_id`, constant
   `code_file`), with the arm64 `debug_id` equal to the freshly
   uploaded symbols' — the first live verification of the merged
   PR #83 fix.
3. **Symbolication passes**: Dart frames/functions meaningfully
   resolved against the uploaded arm64 symbols. Source files, source
   contents and source lines must remain unavailable — resolution
   means function-level symbol names, not source exposure.
4. **Privacy inventory still clean** — the full §2 sweep
   (docs/store/CRASH_PRIVACY_DECLARATIONS.md). `contexts.trace` and
   the envelope `_dsc` are permitted ONLY as the documented Sentry
   transport metadata (CRASH_MONITORING.md §15.4); no other context
   may survive. No identity, health, location, request, breadcrumb,
   device, session, replay or attachment data. **The expected stored
   exception message is exactly:**

   `Bad state: synthetic [redacted] verification 214`

   — `Bad state: ` is `StateError.toString()`'s standard prefix
   (observed and accepted in the 213 audit), and `[redacted]` is the
   documented 'rash'-stem over-redaction of the word "crash"
   (CRASH_MONITORING.md §15.5). Any other message shape is an audit
   finding.
5. **Release identity exact** — release `wellapath-mobile@0.3.0+214`,
   environment `internal-testing`, dist `214`, and only the two
   approved client tags (`crash_source`, `severity`; server-derived
   promotions excluded). Transport delivery is proven by the received
   event itself; the rate-limit backoff window cannot be provoked live
   without prohibited extra events, so it is verified by re-running
   the full unit suite at this branch head and stated as
   test-verified, not live-verified.

## Credentials (never in the repo, not yet created)

Stable Jay stays disabled. Credentials are created ONLY after these
preparation commits pass independent review: the founder then creates
a **fresh build-214-only client key** (its DSN enters the build as a
`--dart-define` from the shell only) and a **new temporary symbols
token** used through gitignored `sentry.properties` (`org=`,
`project=`, `auth_token=`), revoked after the audit. No DSN, token or
key is ever committed, printed or logged.

## Procedure

0. Verify the geo-scrub precondition above (rule present, source
   exactly `$user.geo.**`). Blocked if unmet.
1. Release APK from this branch: `--obfuscate --split-debug-info`, the
   four gate defines + `SENTRY_DSN`, `APP_VERSION=0.3.0
   APP_BUILD=214`. Verify versionCode 214, release signature, SHA-256,
   that the bundled `.env` equals tracked production, and the absence
   of secrets/staging markers (the `kStagingHosts` allowlist constant
   is a known benign string in every build).
2. **Fresh symbols first:** `SENTRY_RELEASE=wellapath-mobile@0.3.0+214`,
   plugin exit 0, and the new arm64 debug ID confirmed present on the
   project BEFORE any event.
3. Install only the hash-verified APK on `wellapath_lowend` (pull
   `base.apk` back and re-hash).
4. Navigate the visible gated UI (Home card → status screen → button →
   confirmation dialog) and send exactly ONE confirmed synthetic
   event. Record the UTC second. Never repeat, regardless of latency
   or an initially empty UI.
5. Founder downloads the stored Event JSON; the audit runs fields-only
   against the five criteria above.
6. Cleanup: founder deletes the test event and revokes the token and
   disables the 214 client key; `sentry.properties` and the Event JSON
   are deleted and confirmed untracked; the audit is recorded in
   PROGRESS.md (fields only); this branch is abandoned unmerged,
   taking the trigger with it.

## The temporary verification UI

A fresh minimal implementation against the merged production code —
nothing cherry-picked or copied wholesale from the abandoned 213
branch, so no stale assumption can return:

* `CrashVerificationGate` — passes only when ALL of
  `CRASH_VERIFICATION_TRIGGER_ENABLED=true`,
  `CRASH_REPORTING_ENABLED=true`,
  `CRASH_REPORTING_PRODUCTION_APPROVED=true` and
  `CRASH_REPORTING_CONTEXT=internal-testing` hold; absent, partial,
  malformed or production-context combinations fail closed and render
  nothing.
* A visible, labelled amber Home card (`Internal verification — System
  status` / `Local build 214 only`) opening the existing status screen.
* A visible status-screen button (`Send synthetic Sentry test error`)
  whose confirmation dialog states one synthetic engineering error and
  no real personal or health information; only the confirmed action
  throws `StateError('synthetic crash verification 214')`,
  synchronously, in the button's gesture callback (so the report
  arrives through `FlutterError.onError` with
  `crash_source=flutter_framework`, as in 213).
* Gate-matrix and widget tests covering the fail-closed matrix, the
  hidden/visible states, the dialog wording and both dialog outcomes.
* Explicitly absent, forever: diagnostic transports, recording panels,
  probes, hidden gestures, extra diagnostic defines, SDK
  instrumentation, temporary dependencies, and every other form of
  local instrumentation from the 212/213 investigations (that harness
  lives only on `diag/213-debug-image-local`, never merged).

## Exit

All five criteria green ⇒ 214's job is done and production Sentry has
its first fully-passing controlled verification. Build 215+ then
requires: updated store privacy declarations (including the five-field
debug-image disclosure), the founder's production context/key model
decision, and the legacy-key disablement assessment. Any criterion red
⇒ remediate on a fresh branch; the one-event budget of 214 is spent
either way.
