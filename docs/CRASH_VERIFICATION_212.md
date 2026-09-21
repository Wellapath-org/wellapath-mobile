# Synthetic-crash verification procedure — internal build 212

**Status: PREPARED, NOT EXECUTED.** No DSN is recorded anywhere in this
repository, no build 212 exists and no event has been sent. Build 211 and
its store artifacts are untouched; 211 is never rebuilt or replaced.

## Project model (corrected 2026-09-21 after live-org inspection)

The Sentry org already contains a Flutter project with slug
**`wellapath-mobile`**, holding historical release metadata for
`0.2.0 (208)` (the PR #66–#68 CI validation line) and no recent errors.
**That project is reused — no `wellapath-mobile-internal` project is
created.** Isolation of the controlled test comes from three narrower
mechanisms instead:

1. a **new client key named `internal-212`** — its DSN is what the 212
   build carries; the legacy/default key stays active until the test
   succeeds, then is assessed for safe disablement;
2. the exact release **`wellapath-mobile@0.3.0+212`**;
3. the environment label **`internal-testing`**, set by the
   `CRASH_REPORTING_CONTEXT` define (closed vocabulary; labeling only,
   never a gate).

The historical build-208 records are preserved — nothing is deleted from
the project.

Live project protections confirmed by screenshot (2026-09-21): EU
ingestion endpoint · Data Scrubber enabled · Default Scrubbers enabled ·
IP-address storage prevented · minidump attachments disabled. An apparent unsafe
setting — `business-email` under Safe Fields — turned out on closer
inspection to be Sentry's grey placeholder text, not an entered value:
**Safe Fields is empty**, so no scrubbing bypass exists (founder
screenshot, 2026-09-21; the additional sensitive-field list is
populated). The two replay-derived issue toggles are also being disabled
for clarity even though the SDK never sends replays.

## Preconditions

- [x] Founder decisions CONFIRMED 2026-09-21 (recorded in
      `docs/store/CRASH_PRIVACY_DECLARATIONS.md` §4): EU region (live),
      30-day retention, owner-only initial access, diagnostics-only scope.
- [x] Data Processing Agreement signed, effective **2026-09-21**, customer
      entity **WELLAPATH TECHNOLOGIES LIMITED**, DPA PDF sha256
      `74abf15fc1c6646517d5b99d6564be1b2caa6a9af5011ed3431979c09ef37a5a`.
- [x] Safe Fields confirmed EMPTY (the `business-email` text is Sentry's
      placeholder, not a value — founder screenshot, 2026-09-21).
- [ ] Client key `internal-212` created on `wellapath-mobile`; its DSN
      stored ONLY in the local shell / CI secret store. It never enters a
      tracked file, a commit message, PROGRESS.md or a chat log.
- [ ] Project retention confirmed at **30 days**.
- [ ] `develop` contains PR #81's gates (merged after review).
- [ ] Build number 212 recorded in `test/release/build_identity_test.dart`
      (211 added to the distributed registry, `kCurrentBuildNumber = 212`)
      in a reviewed commit.

## Step 1 — build the internal 212 candidate

From a clean detached worktree at the approved commit — **the tracked
`.env` stays exactly as committed** (production). The earlier draft's
"edit `.env` to staging locally" instruction is withdrawn: it built from a
deliberately dirty tree, and a forgotten edit would produce a build that
everyone believes is reporting but transmits nothing. Instead the build
uses the founder-approved production-approval key (granted 2026-09-21 for
this internal test), and the `internal-testing` label separates its
events:

```bash
flutter build ipa --release \
  --build-name=0.3.0 --build-number=212 \
  --obfuscate --split-debug-info=build/symbols \
  --dart-define=CRASH_REPORTING_ENABLED=true \
  --dart-define=SENTRY_DSN="$SENTRY_DSN_INTERNAL_212" \
  --dart-define=CRASH_REPORTING_PRODUCTION_APPROVED=true \
  --dart-define=CRASH_REPORTING_CONTEXT=internal-testing \
  --dart-define=APP_VERSION=0.3.0 --dart-define=APP_BUILD=212
```

Same shape for Android (`flutter build appbundle --release`). The build
is distributed to the existing **internal** TestFlight group only.

## Step 2 — upload symbols (no credentials in the repo)

```bash
export SENTRY_ORG=… SENTRY_PROJECT=wellapath-mobile SENTRY_AUTH_TOKEN=…
export SENTRY_RELEASE=wellapath-mobile@0.3.0+212
dart run sentry_dart_plugin        # uploads dSYMs + split-debug-info only
```

`SENTRY_RELEASE` is REQUIRED: without it the plugin derives
`wellapath_mobile@…` from the pubspec **name** (underscore), which does
not match the runtime release `wellapath-mobile@…` that `CrashConfig`
stamps on events. Debug files associate by debug-id, so symbolication
would survive the mismatch — but release identifiers must match exactly.

**Upload verification is mandatory:** the plugin exits non-zero on
failure and lists each uploaded file — read the output. A build whose
symbol upload failed must not be distributed with "symbols uploaded"
status; step 4's symbolication check is the backstop that makes a silent
failure visible before anything ships.

## Step 3 — the synthetic crash

A debug-only trigger on the system-status screen (long-press the build
row 5×) throws `StateError('synthetic crash verification 212')` — a
message that survives the sanitiser untouched, by design, as proof the
pipeline preserves what it is allowed to preserve. The trigger lands in
the 212 branch and is removed before any public build.

## Step 4 — verify, then stop

1. The event arrives in **`wellapath-mobile`** with
   `environment=internal-testing`,
   `release=wellapath-mobile@0.3.0+212`, via the `internal-212` key —
   and the build-208 history is still intact.
2. The stack symbolicates through the uploaded symbols.
3. **Envelope audit (the point of the exercise):** open the raw JSON of
   the received event and check it against the field inventory in
   `docs/store/CRASH_PRIVACY_DECLARATIONS.md` §2 — nothing outside that
   table may appear. Any surprise field = stop, fix the sanitiser, repeat.
4. Confirm the project shows NO session, replay, profile or transaction
   data, and no IP address stored on the event.
5. Delete the test event, record the audit in PROGRESS.md (fields seen,
   never values), then **assess whether the legacy/default client key can
   be disabled safely** (nothing else should be using it; check its
   last-seen traffic before disabling).

## Design point — native crashes are intentionally out of Sentry's view

With `autoInitializeNativeSdk=false` and `enableNativeCrashHandling=false`,
Sentry captures **Flutter/Dart failures only**. A native iOS or Android
crash (a platform-channel plugin fault, an OS kill) produces no Sentry
event — by design for this initial internal test: native envelopes are
uploaded by the platform SDK on next launch and bypass Dart's
`beforeSend`, so the fail-closed sanitiser could not vet them. Native
crashes remain observable through **App Store Connect → Xcode Organizer
crash reports** and **Google Play Console → Android vitals**
(opt-in-gated, aggregate, Apple/Google-hosted). Revisiting native capture
requires inspecting the native envelope on both platforms and a separate
approval.

## Explicitly out of scope

Distributing 212 beyond the internal group, native crash handling,
session tracking, tracing, profiling, store-declaration changes.
