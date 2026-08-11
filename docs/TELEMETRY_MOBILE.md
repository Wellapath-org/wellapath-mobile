# Mobile Telemetry — Operations and Rollback

**Phase:** I1 (Observability & Baseline) · **Workstream:** W1 (Privacy-Safe Product Analytics)
**Contract:** backend telemetry v1.0
**Backend source of truth:** `Wellapath-org/wellapath-backend` @ `5e13379f19c53ec90cee7958dc029d908c342dcd` (PR #29, merged 2026-08-11)
**Status:** implemented, **disabled by default in every build**

---

## 1. What this is

Best-effort, non-clinical product analytics. It emits 10 of the contract's 12
allowlisted events, queues them offline, and delivers them to
`POST /v1/telemetry/events` in batches.

**It cannot affect the product.** Telemetry cannot block, delay, or alter
assessment, red-flag evaluation, scoring, results, emergency or locator
behaviour. Scoring remains entirely on-device. Turning telemetry off changes
nothing a user can see.

### `os_version` is intentionally omitted

The backend contract declares `os_version` as an **optional** field of the `app`
block. **This client does not send it**, and the key is omitted entirely — not
nulled, not blanked, not filled with a placeholder.

Dart's `Platform.operatingSystemVersion` is not an authoritative product OS
release. On Android it returns a kernel/uname string
(`Linux localhost 3.18.94+ #17 SMP … aarch64`), and an earlier normaliser that
took the leading numeric fragment shipped **`"64"` from a device running Android
8.0.0**. That value matched the contract's `\d{1,3}(\.\d{1,3})?` pattern, so the
backend accepted it with a 202 — **no server-side validation could have caught
it**. A silently wrong optional value is worse than an absent one, because it
corrupts cohorting invisibly rather than failing loudly.

No proxy is substituted. Kernel version, API level, architecture, user agent and
build fingerprint are correlates of the OS release, not the OS release; deriving
from any of them reintroduces the same defect.

Restoring the field is a possible future **backward-compatible** enhancement. It
would need an authoritative platform adapter plus real-device validation on both
platforms, and requires no backend change, since the contract already permits
the field. Pinned by `test/telemetry/os_version_omission_test.dart`.

### The one-line summary of the privacy model

Two layers. The **typed event classes** (`lib/core/telemetry/contract/telemetry_event.dart`)
are `sealed` — a caller cannot construct an event carrying a prohibited field,
and the compiler enforces it. The **privacy guard**
(`lib/core/telemetry/privacy_guard.dart`) runs behind them, twice per event —
before persistence and before transmission — to catch a bug in the first layer.

Nothing is silently stripped. A rejection fails the capture, increments a
counter against a fixed reason code, and drops the event.

---

## 2. Enabling telemetry in staging

Telemetry reads four environment variables through `flutter_dotenv`, each of
which can be overridden at build time by a `--dart-define` of the same name.

| Variable                        | Default | Meaning                                                          |
| ------------------------------- | ------- | ---------------------------------------------------------------- |
| `TELEMETRY_ENABLED`             | `false` | Master gate. Only `true` enables it — case-insensitive, trimmed. `1`/`yes`/`on` do **not**. |
| `TELEMETRY_BASE_URL`            | unset   | Base URL. Falls back to `API_BASE_URL`. Path is never hard-coded. |
| `APP_ENV`                       | staging | `production`/`prod` forces telemetry **off**.                    |
| `TELEMETRY_PRODUCTION_APPROVED` | `false` | The only key that can lift the production block.                 |

All three telemetry keys can also be supplied as a `--dart-define`, which
**takes precedence over the bundled `.env`**. That is the supported way to
produce an internal-testing build:

```sh
flutter run \
  --dart-define=TELEMETRY_ENABLED=true \
  --dart-define=TELEMETRY_BASE_URL=https://wellapath-backend-staging.onrender.com \
  --dart-define=APP_VERSION=0.2.0 \
  --dart-define=APP_BUILD=204
```

Use the define rather than editing `.env`. **`.env` is a tracked file**, so an
edit there is one `git add` away from shipping `TELEMETRY_ENABLED=true` to
everyone.

> **`.env.local` does not work for this, despite the name.** `flutter_dotenv`
> reads through the Flutter asset bundle, so any file it loads must be declared
> in `pubspec.yaml` — and declaring a gitignored file that usually does not
> exist fails the build. An earlier revision of this document told you to put
> the flag in `.env.local`; that silently produced a **telemetry-off** build
> while looking like it had worked. Use `--dart-define`.

`APP_VERSION` and `APP_BUILD` populate the `app` context block. Without them the
context defaults to `1.0.0`/`1`, which is valid but useless for cohorting. No
secret is involved: the endpoint is unauthenticated, exactly like `/config`.

### How production stays disabled

Two independent gates. `APP_ENV=production` overrides `TELEMETRY_ENABLED=true`
unless `TELEMETRY_PRODUCTION_APPROVED=true` is *also* set. One flag flipped by
accident cannot turn on production collection. Both defaults ship as `false`.

Covered by `test/telemetry/session_and_config_test.dart` →
`'production stays disabled even with the flag on'`.

---

## 3. Verifying each event

With telemetry enabled and a debug build, `Telemetry.instance.diagnosticsSnapshot()`
reports counts by event name. Exercise these paths:

| Event                  | How to trigger                                                        |
| ---------------------- | --------------------------------------------------------------------- |
| `app_open` (cold)      | Launch the app.                                                       |
| `app_open` (warm)      | Background it, then foreground it.                                    |
| `assessment_start`     | Home → "Check your symptoms" → OK on the modal.                       |
| `assessment_step_view` | Every screen transition inside the assessment, and each follow-up question. |
| `assessment_complete`  | Finish an assessment, **or** cancel one, **or** hit the engine-error path. |
| `result_view`          | Reach either the results screen or the red-flag interrupt screen.     |
| `facility_search`      | Home → "Find a clinic near me" (nearby), or the manual state/area search. |
| `facility_view`        | Tap a pin on the locator map.                                         |
| `facility_call`        | Tap Call on a facility card. Rare — only 0.84% of facilities have phones (issue #50). |
| `directions_open`      | Tap Directions on a facility card.                                    |
| `emergency_action`     | Home emergency card, or Call 112 / Find care on results or red-flag screens. |

Server-side confirmation is the 202 body: `received`/`accepted`/`rejected`.

### Two verification points that are easy to get wrong

- **The red-flag path must look identical to the ordinary path.** Both emit
  `result_view` and both emit `assessment_complete{completed}`. If a red-flag
  assessment ever produces a different event shape, the completion status has
  become a red-flag detector — which is clinical data. Pinned by
  `clinical_regression_test.dart` → `'the two sequences differ only by session ID'`.
- **`emergency_action` carries no session ID.** The contract rejects one, for
  the same reason.

---

## 4. Inspecting queue health without exposing payloads

```dart
Telemetry.instance.diagnosticsSnapshot()
```

Returns counters only — never payloads, event IDs, session IDs, facility IDs or
field values:

```json
{
  "enabled": true,
  "queue_length": 7,
  "queue_capacity": 500,
  "capture_accepted": 42,
  "accepted_by_event": {"app_open": 2, "assessment_step_view": 8},
  "rejected_by_reason": {},
  "dropped_oldest": 0,
  "expired": 0,
  "flush_attempts": 3,
  "retries": 1,
  "non_retryable_drops": 0,
  "corrupted_records_discarded": 0,
  "session_disabled": false
}
```

`accepted_by_event` is keyed by contract event names — fixed vocabulary, not
user data. `rejected_by_reason` is keyed by the backend's own reason codes.

There is deliberately **no** debug affordance that prints a payload body. If you
need to see one during development, use the test fixtures in
`test/telemetry/support/fixtures.dart` rather than the live queue.

---

## 5. Retry and error behaviour

Per contract §5, implemented in `telemetry_transport.dart` and asserted in
`transport_classification_test.dart`.

| Response                              | Action                                                       |
| ------------------------------------- | ------------------------------------------------------------ |
| `2xx`                                 | Remove the batch. Per-event rejections in the body are counted, not retried. |
| `400`, `413`, `415`                   | **Never retried.** Batch dropped.                            |
| Other `4xx`                           | Treated as permanent. Batch dropped.                         |
| `429`, `5xx`, network failure, timeout | Retried, bounded.                                           |
| `503` `telemetry_disabled`            | Discard batch, disable for the session. See §7.              |
| `400` `unsupported_contract_version`  | Same as above — stop rather than downgrade the payload.      |

- **Timeout:** 10 s per request.
- **Attempts:** at most **3 per batch**. That means two backoff delays: **2 s
  then 4 s**, each multiplied by equal jitter in `[0.5, 1.0]`. The contract
  documents the sequence as `2 s, 4 s, 8 s`; the 8 s entry exists in
  `TelemetryContract.backoff` but is unreachable at three attempts, and is kept
  so raising the attempt count doesn't fall off the end of the list.
- **`retry-after`** on a 429 is honoured when it is longer than the computed
  backoff, capped at 60 s. Only the delta-seconds form is parsed.
- After the budget is spent the batch **stays queued** with its original event
  IDs and timestamps, and a later flush retries it.

### De-duplication

`event_id` is generated **once, at occurrence** — not at flush — and is reused
across every retry and across app restarts. `client_ts` likewise records when
the event happened, not when it was sent. The server remembers IDs for one hour,
best-effort. Duplicates are possible and harmless; do not depend on
exactly-once.

---

## 6. Behaviour when offline

- Events queue on device. Capacity **500**, drop-oldest on overflow.
- The queue lives in a Hive box (`telemetry_queue`) under the app's own data
  directory, so an uninstall removes it, as the contract requires.
- `client_ts` older than **30 days** is dropped at flush time rather than sent —
  it would only earn a `timestamp_out_of_range` rejection.
- A flush while offline is a no-op; nothing is lost.
- **Events are removed only after a confirmed outcome** — a 202, or a defined
  non-retryable disposition. Nothing is removed speculatively.

### App termination during an in-flight batch

Nothing is lost and nothing is corrupted. Because removal happens only after a
confirmed response, a process killed mid-request leaves the whole batch in the
queue. On the next launch it is re-sent **with the same `event_id`s and the same
`client_ts` values**, so the server de-duplicates it if the retry lands within
the one-hour window and on the same instance. If it lands outside that window,
those events are counted twice — which is the documented, accepted behaviour of
an at-least-once client.

Covered by `service_test.dart` → `'a restart re-sends queued events with their
original IDs'` and `'an interrupted flush leaves the batch queued, not
half-removed'`.

### Concurrent flushes

A flush pass is guarded by a shared in-flight future. Four concurrent callers
produce one request, not four, so two passes can never read the same records and
delete each other's keys. Covered by `'overlapping flushes share one pass'` and
`'no event is sent twice when flushes race'`.

---

## 7. Behaviour after `telemetry_disabled`

On `503` with `reason_code: telemetry_disabled` the client:

1. discards the pending batch;
2. clears the rest of the queue — nothing more will be sent this session, and
   retained records would only age towards expiry;
3. sets `session_disabled`, cancels the flush timer, and makes every later
   `capture()` a no-op;
4. **does not retry.**

The flag is **not persisted**. The contract scopes it to the application
session, so a relaunch is allowed to try again.

> **This is the live behaviour on staging today.** `POST /v1/telemetry/events`
> currently returns `503 telemetry_disabled` because `TELEMETRY_ENABLED` is not
> set on the staging service. See §12.

---

## 8. Disabling telemetry, and rollback

### Fastest — configuration only, no rebuild of app logic

Set `TELEMETRY_ENABLED=false` (or remove it) and rebuild. `capture()` returns on
its first line; nothing is validated, queued, persisted or transmitted. All
clinical behaviour is unchanged, because none of it ever depended on telemetry.

### Full rollback — revert the branch

`git revert` the merge of `feat/i1-telemetry-mobile`. The only non-telemetry
files touched are instrumentation call sites and `main.dart`/`app.dart`; no
clinical logic, no artifacts, no engine code. See the completion report for the
exact file list.

### Clearing or migrating the queue

- **Clear:** `Telemetry.instance` holds a `TelemetryQueue` with `clear()`. In the
  field, uninstalling removes the Hive box.
- **Migrate:** records carry a schema version (`{"v": 1, "e": {...}}`). A record
  written by a different version is **discarded, not migrated**, and counted in
  `corrupted_records_discarded`. This is deliberate: the queue holds at most a
  few hundred best-effort analytics events with a 30-day life, so discarding is
  cheaper and safer than maintaining migration code for data nobody can miss.
  Bump `TelemetryQueue.schemaVersion` whenever the record envelope changes.
- **Corruption:** an unparseable record is discarded without throwing. One bad
  row cannot wedge the queue. A box that will not open at all is deleted and
  recreated — telemetry must never fail app startup.

---

## 9. Consent and configuration — **unresolved**

The app has **no analytics consent flow and no privacy preference** today, and
this step did not invent one. Per the brief, the implementation is feature-gated
and the decision is listed here rather than guessed at.

> **Open decision — Product / Privacy, before external beta.**
> Does WellaPath need user-facing analytics consent, or is a privacy-policy
> disclosure sufficient given that the contract carries no PHI, no identity and
> no persistent identifier? If consent is required, `TelemetryConfig` gains a
> runtime gate and `Telemetry.init` reads it; the plumbing is ready and no
> further contract work is needed.

Until that is answered, telemetry stays off in production by two independent
gates (§2).

---

## 10. Crash-monitoring provider — **unresolved**

**No crash provider exists in this repository, and none was added.** Adding
Sentry, Firebase Crashlytics or any equivalent is a third-party data-processor
decision requiring founder and engineering lead approval.

What was built instead (`lib/core/crash/crash_reporter.dart`):

- a provider-neutral `CrashSink` boundary, shipped with `NoOpCrashSink`, which
  retains the app's existing local `debugPrint` behaviour and transmits nothing;
- a sanitiser that redacts, from any exception message: **all snake_case
  identifiers** (which covers symptom tokens, `rf_*` rule IDs, `q_*` question
  IDs, duration tokens and urgency values), SCREAMING_CASE words, a clinical and
  identity vocabulary list, quoted string literals, coordinates, emails, phone
  numbers, and anything past 240 characters;
- a report type with **no attachment surface at all** — four fields:
  classification (a Dart type name), origin, redacted message, fatal flag. There
  is nowhere to attach assessment state, answers, results, scores, red flags,
  tokens, artifacts, queued telemetry payloads, breadcrumbs or location;
- **stack traces are not forwarded.** With no approved provider, the right
  amount of stack detail to retain is none. When a provider is approved, the
  stack is the first thing to review for leakage.

**Errors are not suppressed.** `FlutterError.onError` still calls the previous
handler and `PlatformDispatcher.onError` still returns `false`, so a clinical
failure fails exactly as loudly as it did before. Crash-free rate is not a
reason to swallow a clinical error.

> **Open decision — founder + engineering lead.** Which crash provider, if any?
> Until then the boundary collects nothing and sends nothing.

---

## 11. Performance baselines

### Measured (host VM, `flutter test test/telemetry/performance_baseline_test.dart --reporter expanded`)

Against the hash-verified pinned artifacts `kb.ng.v2.4`, `rules.ng.v2.2`,
`token_dictionary.ng.v1.1` — the same fixtures the E8.1 case-bank run used.

| Operation                    | Count | Mean (ms) | p95 (ms) | Max (ms) |
| ---------------------------- | ----- | --------- | -------- | -------- |
| `scoring`                    | 200   | 0.102     | 0.234    | 2.166    |
| `artifact_load` (parse+hash) | 5     | 3.933     | 11.994   | 11.994   |
| `telemetry_queue_write`      | 1000  | 0.040     | 0.069    | 1.005    |
| `telemetry_batch_serialise`  | 500   | 0.024     | 0.033    | 0.228    |
| `telemetry_flush` (500 events, 25 batches) | 1 | 7.9 | 7.9 | 7.9 |

Read against a 16.7 ms frame budget: a queue write is ~0.4% of one frame, and
scoring is ~1.4%. A disabled build absorbs 100 000 captures in under 200 ms
because `capture()` returns on its first line.

### Not measured here — device procedure

Cold/warm app start, time-to-assessment, question-to-question responsiveness,
result rendering, locator startup/search and memory are frame-scheduling and
platform-channel bound; a host number would mislead. Measure them on the E9
low-end profile — Android emulator `wellapath_lowend`, 720x1280 @ density 320
(logical 360x640) — against a signed release build:

```sh
flutter build apk --release \
  --dart-define=APP_VERSION=<v> --dart-define=APP_BUILD=<b>
# Cold start, 5 runs, discard the first:
adb shell am start-activity -W -n org.wellapath.wellapath_mobile/.MainActivity
# Memory after a full assessment + locator:
adb shell dumpsys meminfo org.wellapath.wellapath_mobile | head -20
```

Build the two APKs with the define, never by editing `.env`:

```sh
flutter build apk --release --dart-define=TELEMETRY_ENABLED=false   # baseline
flutter build apk --release --dart-define=TELEMETRY_ENABLED=true \
  --dart-define=TELEMETRY_BASE_URL=https://wellapath-backend-staging.onrender.com
```

Run each and compare.
The host figures above predict no measurable difference; that prediction has
**not yet been confirmed on a device** — see the completion report's open items.

---

## 12. What Backend Engineering needs to do

1. **Set `TELEMETRY_ENABLED=true` on the staging service.**
   `POST https://wellapath-backend-staging.onrender.com/v1/telemetry/events`
   currently returns `503 telemetry_disabled`, which is correct default
   behaviour but blocks the two staging integration tests that need a 202:

   ```sh
   RUN_STAGING_TELEMETRY_TESTS=true flutter test \
     test/telemetry/staging_integration_test.dart
   ```

   With intake disabled: 5 pass, 2 skip with an explanatory message. The
   route, the 400/415/413 paths and the 503 classification are already
   confirmed against the deployed service.

2. **No contract changes are requested.** The mobile mirror matches
   `telemetry.v1.allowlist.json` field-for-field at commit `5e13379`, asserted
   by `contract_parity_test.dart`. No mismatch was found.

3. **For information** — three optional fields this client deliberately does not
   send, with reasons, in case they affect backend dashboards:
   - `admin_area_code` — the artifact→ISO 3166-2:NG mapping is unconfirmed
     (contract §8). The facilities artifact carries free-text `state` values
     (`Lagos`, `Kano`, `FCT`), and a wrong-but-valid code is worse than none.
     Ask the facilities owner to confirm a mapping and this becomes a
     one-line change.
   - `step_count` on `assessment_step_view` — the only value this app could
     supply is the flow total, which `QuestionEngine.generateQuestions()`
     derives from the user's selected symptom tokens. Sending it would leak an
     answer-derived quantity on every step. `step_count` **is** sent on
     `assessment_complete`, where it means steps actually reached.
   - `search_mode: name` — the locator has no name search; it offers nearby
     (GPS) and manual state/area dropdowns only. The enum value is
     implemented and will be used if a name search is ever built.

---

## 13. Where things live

```
lib/core/telemetry/
  telemetry.dart                     # static entry point, Telemetry.capture
  telemetry_service.dart             # capture, flush, retry, disablement
  telemetry_queue.dart               # Hive-backed 500-cap FIFO queue
  telemetry_transport.dart           # Dio transport + §5 classification
  telemetry_config.dart              # environment gates
  telemetry_runtime.dart             # clock, IDs, jitter, connectivity, app context, diagnostics
  privacy_guard.dart                 # second defensive layer
  assessment_telemetry_session.dart  # per-assessment correlation
  contract/
    telemetry_contract.dart          # deterministic mirror of the backend allowlist
    telemetry_event.dart             # sealed typed events
lib/core/crash/crash_reporter.dart   # provider-neutral boundary + sanitiser
lib/core/perf/perf_trace.dart        # duration-only performance tracing

test/fixtures/contracts/             # vendored backend artifacts (drift guard)
test/telemetry/                      # 268 tests
```
