# Synthetic-crash verification procedure — internal build 212

**Status: PREPARED, NOT EXECUTED.** No Sentry account work, DSN, build or
event exists yet. This procedure runs only after every item in
[§ Preconditions](#preconditions) is confirmed, and it produces an
**internal** build only. Build 211 stays untouched; 211 artifacts are never
rebuilt or replaced.

## Preconditions

Every box needs a name and a date before step 1 runs.

- [ ] Sentry organisation created, **EU data region** chosen at creation
      (region is immutable per org; see the founder-decision sheet).
- [ ] Data Processing Agreement accepted on the Sentry account.
- [ ] A dedicated project `wellapath-mobile-internal` (do **not** reuse it
      for production later; a separate project keeps retention and access
      decisions independent).
- [ ] The DSN for that project stored ONLY in the local shell / CI secret
      store. It never enters a tracked file, a commit message, PROGRESS.md
      or a chat log.
- [ ] Founder sign-off on the retention / access / region sheet in
      `docs/store/CRASH_PRIVACY_DECLARATIONS.md` §4.
- [ ] `develop` contains this branch's gates (merged via its PR).

## Step 1 — build the internal 212 candidate

From a clean detached worktree at the approved commit:

```bash
flutter build ipa --release \
  --build-name=0.3.0 --build-number=212 \
  --obfuscate --split-debug-info=build/symbols \
  --dart-define=CRASH_REPORTING_ENABLED=true \
  --dart-define=SENTRY_DSN="$SENTRY_DSN" \
  --dart-define=APP_VERSION=0.3.0 --dart-define=APP_BUILD=212
```

Notes:
* The bundled `.env` stays production, so `CrashConfig` engages the
  production block — **an internal crash-test build must therefore locally
  (uncommitted) set `APP_ENV=staging` in `.env`** and point at the staging
  API, which is also the correct place for a synthetic crash to originate.
  Verify `flutter test test/release/` fails on the dirty tree (expected) and
  never commit that state.
* Same shape for Android: `flutter build appbundle --release` with the same
  defines and obfuscation flags.
* 212 must first be recorded in `test/release/build_identity_test.dart`
  (210-style entry for 211, `kCurrentBuildNumber = 212`) in a reviewed
  commit.

## Step 2 — upload symbols (no credentials in the repo)

```bash
export SENTRY_ORG=… SENTRY_PROJECT=wellapath-mobile-internal SENTRY_AUTH_TOKEN=…
dart run sentry_dart_plugin        # reads pubspec `sentry:` — uploads
                                   # dSYMs + split-debug-info, nothing else
```

## Step 3 — the synthetic crash

Add a debug-only trigger on the system-status screen (long-press the build
row 5×) that throws `StateError('synthetic crash verification 212')` — a
message that survives the sanitiser untouched, by design, as proof the
pipeline preserves what it is allowed to preserve. The trigger lands in the
212 branch and is removed before any public build.

## Step 4 — verify, then stop

1. The event arrives in `wellapath-mobile-internal` tagged
   `environment=internal-beta`, `release=wellapath-mobile@0.3.0+212`.
2. Stack symbolicates through the uploaded symbols.
3. **Envelope audit (the point of the exercise):** open the raw JSON of the
   received event and check it against the field inventory in
   `docs/store/CRASH_PRIVACY_DECLARATIONS.md` §2 — nothing outside that
   table may appear. Any surprise field = stop, fix the sanitiser, repeat.
4. Confirm the Sentry project shows NO session, replay, profile or
   transaction data of any kind.
5. Delete the test event, record the audit in PROGRESS.md (fields seen,
   never values), and file the follow-up for the production-approval
   decision.

## Explicitly out of scope

Enabling `CRASH_REPORTING_PRODUCTION_APPROVED`, distributing 212 beyond the
internal group, native crash handling, session tracking, tracing.
