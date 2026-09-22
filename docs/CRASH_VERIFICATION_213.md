# Controlled transport verification — build 213

**LOCAL-VERIFICATION-ONLY — NEVER MERGE, NEVER DISTRIBUTE.** This branch
(`build/213-transport-verification`, cut from `develop` at merge
`f4196193`) and every temporary verification file on it exist to prove
the merged crash-reporting remediation (PR #82) with exactly one
controlled event. Build 213 must never reach a store, a tester channel
or any device beyond the local `wellapath_lowend` emulator. The first
potentially distributable Sentry-enabled candidate is **build 214 or
higher**, and only after the store privacy declarations are updated.

## Hard precondition — server-side geo scrub

The founder's Advanced Data Scrubbing rule on project `wellapath-mobile`
— Method **Remove** · Data type **Anything** · Source **`$user.geo`** —
**must already be saved before any event is sent.** It was configured on
2026-09-22 and remains OPERATIONALLY UNVERIFIED until this test's stored
Event JSON shows no `user.geo`. If the rule is not in place, execution
is blocked at step 0.

## What this run must prove (audit criteria, corrected 2026-09-22)

1. **`user.geo` completely absent** from the stored Event JSON — the
   first operational verification of the scrub rule.
2. **`debug_meta.images` limited to exactly the approved five-field
   allowlist** (`type`, `image_addr`, `debug_id`, `code_id`, constant
   `code_file`), with the arm64 `debug_id` equal to the freshly
   uploaded symbols'.
3. **Symbolication passes** when Dart frames/functions are meaningfully
   resolved against the uploaded arm64 symbols. Source files, source
   contents and source lines must remain unavailable — resolution means
   function-level symbol names, not source exposure.
4. **Privacy inventory still clean** — the full §2 sweep. `contexts.trace`
   and the envelope `_dsc` are permitted ONLY as the documented Sentry
   transport metadata (CRASH_MONITORING.md §15.4); **no other context
   may survive**. No identity, health, location, request, breadcrumb,
   device, session, replay or attachment data. The synthetic message
   reads `synthetic [redacted] verification 213` by design ('rash' stem).
5. **Transport delivery and rate-limit behaviour intact** — delivery is
   proven by the received event itself; the rate-limit backoff window
   cannot be provoked live without prohibited extra events, so it is
   verified by re-running the merged unit suite at this branch head and
   stated as test-verified, not live-verified.

## Credentials (never in the repo)

Stable Jay stays disabled. After commits 1–2 are reviewed, the founder
creates a **fresh build-213-only client key**; its DSN enters the build
as a `--dart-define` from the shell only. A **new temporary symbols
token** is used through gitignored `sentry.properties` with the
plugin's verified key names (`org=`, `project=`, `auth_token=`) and is
revoked after the audit. No DSN, token or key is ever committed,
printed or logged.

## Procedure

0. Verify the geo-scrub precondition above. Blocked if unmet.
1. Release APK from this branch: `--obfuscate --split-debug-info`, the
   four gate defines + `SENTRY_DSN`, `APP_VERSION=0.3.0 APP_BUILD=213`.
   Verify versionCode 213, release signature, SHA-256 and that the
   bundled `.env` equals tracked production.
2. **Fresh symbols first:** `SENTRY_RELEASE=wellapath-mobile@0.3.0+213`,
   plugin exit 0, and the new arm64 debug ID confirmed present on the
   project BEFORE any event.
3. Install the hash-verified APK on `wellapath_lowend` only (pull
   `base.apk` back and re-hash).
4. Navigate the visible gated UI (Home card → status screen → button →
   confirmation dialog) and send exactly ONE confirmed synthetic event.
   Record the UTC second. Never repeat, regardless of latency or an
   initially empty UI.
5. Founder downloads the stored Event JSON; the audit runs fields-only
   against the five criteria above plus release
   `wellapath-mobile@0.3.0+213`, environment `internal-testing`, and
   the two client tags.
6. Cleanup: founder deletes the test event and revokes the token;
   `sentry.properties` and the Event JSON are deleted and confirmed
   untracked; the audit is recorded in PROGRESS.md (fields only); this
   branch is abandoned unmerged, taking the trigger with it.

## The temporary verification UI (commit 2)

A fresh minimal implementation against the merged code — nothing is
cherry-picked from the 212 branch, so no stale assumption can return:

* `CrashVerificationGate` — passes only when ALL of
  `CRASH_VERIFICATION_TRIGGER_ENABLED=true`,
  `CRASH_REPORTING_ENABLED=true`,
  `CRASH_REPORTING_PRODUCTION_APPROVED=true` and
  `CRASH_REPORTING_CONTEXT=internal-testing` hold; absent, partial,
  malformed or production-context combinations fail closed and render
  nothing.
* A visible, labelled amber Home card (`Internal verification — System
  status` / `Local build 213 only`) opening the existing status screen.
* A visible status-screen button (`Send synthetic Sentry test error`)
  whose confirmation dialog states one synthetic engineering error and
  no real personal or health information; only the confirmed action
  throws `StateError('synthetic crash verification 213')`,
  synchronously, in the button's gesture callback.
* Explicitly absent, forever: hidden gestures, diagnostic transports,
  probes, stage panels, extra transport dependencies and every other
  form of local instrumentation from the 212 investigation.

## Exit

All five criteria green ⇒ 213's job is done. Build 214+ requires:
updated store privacy declarations (including the five-field
debug-image disclosure), the founder's production context/key model
decision, and the legacy-key disablement assessment.
