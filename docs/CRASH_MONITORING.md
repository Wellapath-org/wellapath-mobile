# Crash Monitoring — Operations and Runbook

**Phase:** I1 (Observability & Baseline) · final gate
**Provider:** Sentry Cloud, **EU region**
**SDK:** `sentry_flutter` **9.27.0**
**Scope:** approved **internal-beta** builds only
**Status:** implemented, **disabled by default in every build**

> **I1 is not closed by this document.** PR review and merge, provider
> dashboard verification and the internal-beta crash receipt are now **done**
> (§11). Closure still requires founder-supplied **access, retention, DPA and
> alert-recipient** facts — see §13 — plus the carried-forward items in §14.
>
> Native crash coverage and true crash-free-session metrics are **not**
> established by this receipt; see *Validated limitations* in §11.

---

## 1. Shape of the integration

Sentry sits **entirely behind the existing crash boundary**. `sentry_flutter`
is imported by exactly one file, `lib/core/crash/sentry_crash_sink.dart`. No
product code imports it, and no product code calls Sentry directly.

```
error ──▶ CrashReporter (FlutterError.onError, PlatformDispatcher.onError,
          │              Isolate error listener)
          ├─▶ previous handler  (unchanged — failures still fail locally)
          └─▶ CrashSink
                ├─ NoOpCrashSink      ← default, transmits nothing
                └─ SentryCrashSink    ← only when both gates pass
                      └─▶ beforeSend = SentryEventSanitiser.sanitise
                            └─▶ transport
```

Removing the provider means changing one file.

---

## 2. Two gates, both required

Crash transmission requires **both**, at build time, and neither is present by
default:

| Define | Requirement |
| --- | --- |
| `CRASH_REPORTING_ENABLED` | exactly `true` (trimmed, case-insensitive) |
| `SENTRY_DSN` | structurally valid, non-placeholder |

Missing, empty, malformed, placeholder or unexpanded DSN → **disabled**. A
`http://` DSN, a DSN with no public key, or one with a non-numeric project id
→ **disabled**.

Local development, tests and ordinary builds are all disabled. Verified by 41
tests in `test/crash/crash_config_test.dart`.

### Production stays off

`APP_ENV=production` (or `prod`) forces disabled **even with both gates**,
unless a third key, `CRASH_REPORTING_PRODUCTION_APPROVED=true`, is also set.
Production and public-beta collection are not approved.

### The DSN is never committed

Supplied only as a `--dart-define`, from a protected CI secret. It is not in
`.env`, not in `.env.example`, not in this document, and never printed —
`CrashConfig.toDiagnostics()` reports `dsn_configured: true/false` and nothing
more.

`.env.local` is **not** a supported path: `flutter_dotenv` reads through the
asset bundle, so a gitignored file cannot be loaded. This mirrors
`docs/TELEMETRY_MOBILE.md` §2.

### Building an approved internal-beta build

```sh
flutter build apk --release \
  --dart-define=CRASH_REPORTING_ENABLED=true \
  --dart-define=SENTRY_DSN="$SENTRY_DSN" \
  --dart-define=APP_ENV=internal-beta \
  --dart-define=APP_VERSION=0.2.0 --dart-define=APP_BUILD=208
```

`$SENTRY_DSN` comes from the CI secret store. Never paste it into a shell
history, a ticket, or this file.

---

## 3. Privacy configuration

Every option is set **explicitly** in `CrashMonitoring.applyPrivacyOptions`.
Defaults are not trusted — several of these default to `true`, and an SDK
upgrade can change one silently.

| Setting | Value |
| --- | --- |
| `sendDefaultPii` | `false` — no IP, username or device name |
| `attachThreads`, `reportPackages` | `false` |
| `maxBreadcrumbs` | `0`, plus `beforeBreadcrumb` returning `null` |
| all breadcrumb integrations (native, lifecycle, window metrics, brightness, text scale, memory pressure, user interaction) | `false` |
| `attachScreenshot`, `attachViewHierarchy`, `reportViewHierarchyIdentifiers` | `false` |
| `tracesSampleRate`, `profilesSampleRate` | `null` |
| auto performance, user-interaction tracing, TTFD, frames tracking | `false` |
| `captureFailedRequests` | `false` — no request/response bodies, headers or cookies |
| `autoInitializeNativeSdk`, `enableNativeCrashHandling`, `enableNdkScopeSync` | `false` |
| watchdog termination, app-hang tracking | `false` |
| `enableAutoSessionTracking` | `false` |
| `attachStacktrace` | `true` — sanitised per frame |
| `beforeSend` | `SentryEventSanitiser.sanitise` |

The SDK's own error-capturing and context-loading integrations are **removed**
(`FlutterErrorIntegration`, `OnErrorIntegration`, `RunZonedGuardedIntegration`,
`IsolateErrorIntegration`, `NativeSdkIntegration`, `LoadContextsIntegration`,
`LoadImageListIntegration`, `NativeAppStartIntegration`, `ScreenshotIntegration`,
`WidgetsBindingIntegration`, `DebugPrintIntegration`). The app routes every
error through its own boundary, so leaving them installed would report each
failure twice.

---

## 4. The `beforeSend` boundary

`SentryEventSanitiser.sanitise` is an **allowlist that rebuilds the event**, not
a denylist that removes fields. Anything the SDK attaches now — or attaches
after a future upgrade — is dropped unless explicitly named.

**Transmitted:** event id, timestamp, platform, level, release, environment,
dist, sanitised exceptions (type, message, stack frames), and two tags —
`crash_source` and `severity` — each validated against a closed vocabulary.

**Never transmitted:** user, request, breadcrumbs, contexts, extra, modules,
threads, debug metadata, sdk block, message, transaction, culprit, fingerprint,
logger, server name, attachments, and every category of clinical data.

**Frames keep** file name, function, line/column, package, in-app flag and the
image/symbol/instruction addresses symbolication needs. **Frames drop**
`contextLine`, `preContext`, `postContext` and `vars` — source text and local
variable values, precisely where an assessment payload would appear. Absolute
paths are reduced to a basename (a developer home directory leaks a username);
URLs lose their query strings; a function name containing a quote or whitespace
is a dynamically built label and is replaced.

**Hashing is not sanitisation.** A prohibited value is dropped, never hashed and
forwarded.

If safe transformation cannot be guaranteed the whole event is dropped, and a
sanitiser that throws drops the event rather than letting it through.

---

## 5. Deliberately disabled, and why

Two SDK capabilities are switched **off** even though they are supported. Both
need separate approval before they could be enabled.

### Native crash handling — OFF

A native fatal is captured by the platform SDK and uploaded on next launch
**without passing through Dart's `beforeSend`**. The fail-closed sanitiser could
not vet it, and relying on Sentry server-side scrubbing was explicitly ruled
out. `autoInitializeNativeSdk = false` also guarantees no manifest or plist
default can begin collecting on its own — which is why this PR changes no
Android or iOS configuration at all.

**Consequence:** native fatal crashes (JVM/ART, Objective-C/Swift) are **not
captured**. Dart-level fatals, async errors and isolate errors are.

**To enable later:** inspect a native envelope on both platforms, confirm it
carries no prohibited field, and record approval.

### Automatic session tracking — OFF

Session envelopes also bypass `beforeSend`.

**Consequence:** **crash-free session rate is unavailable.** Crash-free *users*
is unavailable by design, since no user is ever set. Health is measured by
absolute issue counts and by release comparison instead.

---

## 6. Crash classification

| Field | Values |
| --- | --- |
| `crash_source` | `flutter_framework`, `platform_dispatch`, `isolate`, `native`, `handled` |
| `severity` | `fatal`, `non_fatal` |
| exception type | the Dart type name, validated as an identifier |
| release | `wellapath-mobile@<version>+<build>` |
| environment | `internal-beta` |

No screen name, route history, selected answer, result type, urgency or
application state is attached. Anything outside these vocabularies is dropped
rather than coerced.

---

## 7. De-duplication

Overlapping handlers can observe one failure twice. `CrashReporter` suppresses
an identical report — same classification, origin and sanitised message —
within a 2-second window. Identity is computed from the **sanitised** report, so
de-duplication never requires holding a raw value.

`CrashReporter.install()` runs once, before the first frame. Attaching the
provider later uses `CrashReporter.setSink()`, never a second `install()`, which
would chain the framework handler onto the one already installed and report
everything twice.

---

## 8. Validation triggers

`CrashValidation` provides three triggers using fixed non-clinical markers
(`WP_VALIDATION_FATAL_A1`, `WP_VALIDATION_ASYNC_B2`,
`WP_VALIDATION_NONFATAL_C3`).

Available only when **all** hold: not a release build (`kReleaseMode` disables
it outright), crash monitoring enabled through its own gates, and
`CRASH_VALIDATION_ENABLED=true`.

There is **no UI affordance**. Nothing in the widget tree calls them, they are
unreachable by navigation, and no clinical screen was modified to host them.
They can be deleted once internal-beta validation is signed off — nothing in the
product depends on them.

---

## 9. Operational controls

| Control | Setting |
| --- | --- |
| Region | **EU** (Sentry Cloud EU) — *to be confirmed at project creation* |
| Project | `wellapath-mobile`, Flutter platform |
| Environment | `internal-beta` |
| Access | authorized WellaPath team members only — *to be configured* |
| Retention | *to be set at project creation; record the value here* |
| Alert recipients | *to be configured* |
| Review cadence | internal-beta triage at each build review |

### Kill switch

**Disabling crash transmission requires a new build** with
`CRASH_REPORTING_ENABLED` unset (or the DSN removed). There is no remote
disable, because adding a remote-configuration system was explicitly out of
scope — this is a real limitation, recorded rather than papered over.

A provider-side stop-gap: revoke or rotate the DSN key in the Sentry project,
which causes ingest to reject events. The client fails safe — a rejected upload
is not an application error.

### DSN rotation

1. Create a new client key in the Sentry project.
2. Update the CI secret.
3. Rebuild and redistribute internal-beta.
4. Revoke the old key once no build in circulation uses it.

### Symbol upload

Debug symbols are uploaded **through CI only**, using a protected
`SENTRY_AUTH_TOKEN`. The token is never embedded in the app and never committed.
Symbol upload is **not yet wired into `ci.yml`** — see §11.

Internal-beta builds are **not** built with `--obfuscate`, so Dart frames are
already readable without symbol upload. Symbolication becomes necessary only if
obfuscation is adopted.

### Provider outage

Non-blocking by construction. `Sentry.captureException` is fire-and-forget, its
future's errors are swallowed, and the sink catches everything. An unreachable
provider cannot delay startup, assessment, scoring, red-flag handling, results,
the locator or offline operation.

### If prohibited data is detected

1. Set `CRASH_REPORTING_ENABLED` unset and rebuild immediately.
2. Revoke the DSN key to stop ingest from circulating builds.
3. Delete the affected events and issues in the Sentry project.
4. Record what reached the provider, for how long, and who could see it.
5. Add a regression test reproducing the leak before re-enabling.

### Deletion and export

Sentry supports per-issue and per-project deletion, and data export, from the
project settings. Both are manual operations performed by a project
administrator.

---

## 10. Testing

| Suite | Tests |
| --- | --- |
| `test/crash/crash_config_test.dart` | 41 — gates, DSN validation, production block, release identity, no DSN in diagnostics |
| `test/crash/sentry_envelope_privacy_test.dart` | 31 — adversarial markers against the serialized event |
| `test/crash/crash_boundary_test.dart` | 15 — hand-off, de-duplication, previous handler preserved, provider failure isolated, validation triggers unavailable |
| `test/crash/sentry_transport_capture_test.dart` | 9 — **real SDK client, real privacy config, envelope intercepted at the transport** |

The transport tests are the strongest evidence: they run the actual SDK with
the actual configuration and inspect the bytes that would leave the device,
catching anything attached *after* `beforeSend`.

No Sentry account is needed to run any of them, and nothing is transmitted.

---

## 11. Internal-beta validation — status

### Configuration mapping

The GitHub secret name and the application define name are deliberately
different. The secret is named for *where it applies*; the define is named for
*what it controls*. They are joined only in the workflow.

| Layer | Name |
| --- | --- |
| GitHub environment | `internal-beta` |
| GitHub secret | `SENTRY_DSN_INTERNAL_BETA` |
| Workflow step env var | `SENTRY_DSN` (job-scoped, never echoed) |
| Build-time define | `--dart-define=SENTRY_DSN=...` |
| Consumed by | `CrashConfig.fromEnvironment()` → `SENTRY_DSN` |
| Enable gate | `--dart-define=CRASH_REPORTING_ENABLED=true` |
| Production gate | `CRASH_REPORTING_PRODUCTION_APPROVED` — **not set**, stays closed |
| Environment | `--dart-define=APP_ENV=internal-beta` |
| Release | `wellapath-mobile@<APP_VERSION>+<APP_BUILD>` |

The application-side names were **not** renamed to match the GitHub secret.
`CrashConfig` reads `SENTRY_DSN`; the secret's name is a deployment concern.

### Workflow

`.github/workflows/internal-beta-validation.yml`:

* **`workflow_dispatch` only** — no `pull_request`, no `pull_request_target`,
  no `push`. Secrets are never handed to code from a pull request.
* `environment: internal-beta`, so the DSN can carry protection rules.
* `permissions: contents: read`.
* Fails **before** installing Flutter if the secret is absent, rather than
  quietly producing a monitoring-disabled build that would look like a
  successful validation.
* The DSN is passed through a job-scoped env var, never interpolated into a
  rendered command line; `set -x` is never enabled; only its length is logged.
* Runs the privacy gate (`test/crash/` and the adversarial suite) **before**
  the build that could transmit.
* Verifies the DSN public key is absent from every tracked file.
* **Does not upload the APK.**

### Why the APK is not uploaded

**This repository is public.** Workflow artifacts on a public repository are
downloadable, and the APK necessarily embeds the DSN as Sentry's ingestion
routing identifier — that is true of every Sentry client, including browser
JavaScript, and no client can conceal it. Publishing the artifact would publish
the DSN.

Getting a validation build onto a device therefore requires either making the
repository private, or an engineer building locally with the DSN supplied
out-of-band:

```sh
read -rs SENTRY_DSN            # not echoed, not in shell history
export SENTRY_DSN
flutter build apk --release \
  --dart-define=CRASH_REPORTING_ENABLED=true \
  --dart-define=SENTRY_DSN="$SENTRY_DSN" \
  --dart-define=CRASH_VALIDATION_ENABLED=true \
  --dart-define=APP_ENV=internal-beta \
  --dart-define=APP_VERSION=0.2.0 --dart-define=APP_BUILD=208
unset SENTRY_DSN
```

### Pre-transmission gate — PASSED at PR head `87ba20d`

| Suite | Result |
| --- | --- |
| Real-SDK transport capture | 9 passing |
| Envelope privacy (adversarial) | 31 passing |
| Crash configuration gates | 41 passing |
| Crash boundary | 15 passing |
| Telemetry privacy / adversarial | 84 passing |
| Full suite | 673 passing, 13 skipped |

No prohibited marker reaches an envelope. Transmission was therefore permitted
to proceed as far as the environment allows.

### Symbolication assessment — no auth token required

| Question | Answer |
| --- | --- |
| Does the release build use `--obfuscate`? | **No** — the flag appears nowhere in the repository, CI, or Gradle config |
| Does it use `--split-debug-info`? | **No** |
| Is a Sentry Gradle plugin configured? | **No** — nothing uploads symbols automatically |
| Is Dart debug information needed for useful stacks? | **No.** Without obfuscation, AOT frames retain function and library names |
| Are native symbols needed? | **No.** Native crash handling is disabled, so no native frames are produced |

**Conclusion: no `SENTRY_AUTH_TOKEN` is required for the scope of this PR.**
Do not create one.

It would become necessary only if internal-beta later adopts `--obfuscate` or
`--split-debug-info`, or if native crash handling is enabled. If that happens:

* command: `flutter packages pub run sentry_dart_plugin` (or `sentry-cli debug-files upload`)
* minimum scope: **`org:ci`** — the scope Sentry documents for CI release and
  symbol workflows. Nothing broader.
* secret name: `SENTRY_AUTH_TOKEN_CI`, in the **`internal-beta`** environment
* consumed by: a dedicated symbol-upload step in
  `internal-beta-validation.yml`, after the build
* the token is **never** passed to a `--dart-define` and never enters the APK

### Dashboard receipt — PASSED

Confirmed by human inspection of the Sentry dashboard following protected
validation run [`31794343788`][run]. The runner transmits; a person reads the
dashboard back. **Runner-side success alone is not a receipt** — the runner can
only prove Sentry answered `2xx`, not what the event contains.

[run]: https://github.com/Wellapath-org/wellapath-mobile/actions/runs/31794343788

#### Sanitized dashboard matrix

| Field | Observed |
| --- | --- |
| Project | `wellapath-mobile` |
| Data region | EU |
| Environment | `internal-beta` |
| Release | `wellapath-mobile@0.2.0+208` |
| Dist | `i1val-31794343788-1` |
| Events received | 3 |
| Grouped issues | 1 |
| Users affected | **0** |
| Fatal | 2 |
| Non-fatal | 1 |
| `crash_source` = `flutter_framework` | 1 |
| `crash_source` = `platform_dispatch` | 1 |
| `crash_source` = `handled` | 1 |
| Exception type | `CrashValidationError` |
| Exception value | redacted by the sanitizer |
| Stack trace | present and useful |
| Duplicates | none |
| All Tags | only expected safe operational tags |
| Clinical / assessment / location / identity / telemetry identifiers | **none observed** |

`0 users affected` is the load-bearing number here: it is the dashboard's own
confirmation that no user identity was attached, cross-checked independently of
our `sendDefaultPii = false` setting.

The `dist` value is what makes a run findable without a marker string. The
fixed markers are deliberately redacted by the sanitizer, so search by:

```
environment:internal-beta release:wellapath-mobile@0.2.0+208 dist:i1val-31794343788-1
```

#### Validated limitations

Recorded so the receipt is not read as broader than it is:

* **Native SDK initialization remains disabled**, so **native fatal crash
  collection is unavailable.** A native crash on device is not reported.
* **Automatic sessions are disabled**, so **true crash-free-session metrics are
  unavailable.** Any crash-free figure quoted from this configuration would be
  derived from Dart-side events only and would overstate coverage.
* **Native coverage and true crash-free sessions are required before external
  beta / W9.** They are carried forward, not closed.
* **Disablement currently requires a new build or revoking the DSN key.** There
  is no runtime remote kill switch; see §9.
* **No `SENTRY_AUTH_TOKEN` is required** for the current configuration, because
  Dart stack traces are unobfuscated. A token becomes necessary only if
  obfuscation or native symbolication is introduced.

This receipt covers the **Flutter/Dart** crash path on an emulator-class
environment. It is not evidence of native crash capture, and not evidence of
physical low-end handset behaviour.

### Provider-outage behaviour — verified

Verified on the low-end emulator with crash monitoring **enabled** and the
provider unreachable:

* startup unaffected; the app reaches home normally;
* an ordinary offline assessment completes on-device with an identical result;
* the red-flag case reached the interrupt in **3.3 s**, matching the
  monitoring-disabled baseline exactly;
* zero crashes, ANRs, or provider errors surfaced to the application;
* `Crash monitoring enabled` is logged, and no failure propagates.

---

## 12. Setup discrepancies — RESOLVED

> **Resolved.** The `internal-beta` environment now exists with the secret
> scoped to it and required reviewers attached; the repository-level copy and
> the misnamed environment were deleted; and the workflow was landed on the
> default branch (PR #66) so `workflow_dispatch` registers. Run
> `31794343788` was approved by a human reviewer through that gate, with no
> admin bypass. The original findings are kept below as the audit record.

<details>
<summary>Original findings (historical)</summary>

### Original: setup discrepancies — action required

The approved design is *"DSN stored in the GitHub `internal-beta` environment
as `SENTRY_DSN_INTERNAL_BETA`"*. The repository's actual state differs:

| Expected | Actual |
| --- | --- |
| Environment named `internal-beta` | Environment named **`SENTRY_DSN_INTERNAL_BETA`** — the secret's name was used as the environment name. No `internal-beta` environment exists. |
| Secret scoped to that environment | Secret exists **twice**: once inside the misnamed environment, and once at **repository level** |
| Environment carries protection rules | `protection_rules: []`, `deployment_branch_policy: null` |

**Why this matters.** The repository-level copy is the problem. A repo-level
secret is available to *any* workflow in the repository, including a workflow
file added on any branch a contributor can push — and because repository
secrets are visible to a job even when it declares an environment, a job
targeting `internal-beta` would silently resolve the repo-level copy and
appear to work while carrying none of the intended protection. The environment
copy is correctly scoped but attached to the wrong environment name.

Using the repo-level secret would therefore have produced a green run that
quietly discarded the protection the design called for, so it was not used.

**To resolve:**

1. Create an environment named exactly `internal-beta`.
2. Add `SENTRY_DSN_INTERNAL_BETA` as a secret **inside** that environment.
3. Add protection rules: required reviewers, and restrict to the branches that
   may deploy.
4. **Delete** the repository-level `SENTRY_DSN_INTERNAL_BETA` secret so the DSN
   is not repo-wide.
5. **Delete** the misnamed `SENTRY_DSN_INTERNAL_BETA` environment.

The workflow already targets `environment: internal-beta` and fails safely
until this exists.

### A second, structural blocker: workflow_dispatch needs the default branch

GitHub only offers a `workflow_dispatch` workflow for manual triggering once the
workflow file exists on the **default branch**. This file is on the PR branch,
and PR #65 must not merge before dashboard verification — so the workflow
cannot be dispatched yet. `gh workflow list` confirms only `Mobile CI` is
currently registered.

Resolving this requires either landing the workflow file on the default branch
ahead of the rest of PR #65, or performing the validation build locally with
the DSN supplied out-of-band.

</details>

### A third issue, found by the first dispatch: test-harness network isolation

The first approved dispatch (run `31788391301`) failed closed with an all-zero
`SentryId`. Not a Sentry, DSN or privacy fault: `TestWidgetsFlutterBinding`
installs `HttpOverrides.global = _MockHttpOverrides()`, whose client answers
every request with `400` and opens no socket, and Sentry's `HttpTransport` maps
any status `>= 400` to `SentryId.empty()`.

Fixed in PR #68 (on `main`) by lifting that override **inside the isolated
receipt process only** and restoring it in a `finally`. Ordinary test processes
keep full network isolation, and a secret-free loopback guard asserts both
states before the real DSN is used. The workflow also now asserts Linux,
because on macOS/iOS/Android the SDK routes envelopes to the native SDK via
`FileSystemTransport`, which returns a non-zero id **with no network call at
all** — a false receipt.

> **Note — `develop` carries a stale copy.** PR #65 brought an earlier version
> of `internal-beta-validation.yml` into `develop`. The corrected version lives
> on `main`, which is the only branch `workflow_dispatch` registers from, so
> the stale copy is inert. It should be reconciled when `develop` next merges
> to `main`.

---

## 13. Founder-provided operational facts

| Fact | Status |
| --- | --- |
| Data region | **EU** — confirmed |
| Organization / project | `wellapath-mobile` — confirmed |
| Intended environment | `internal-beta` — confirmed |
| Authorized access count and roles | **not provided — blocks I1 closure** |
| Active error-event retention | **not provided — blocks I1 closure** |
| Alert recipients | **not provided — blocks I1 closure** |
| Terms / DPA acceptance | **not confirmed — blocks I1 closure** |

Member email addresses are deliberately not recorded here; a count and role
list is sufficient. **These four values are not inferred or assumed** — they
are governance facts only the founder can state, and the closure document
cannot be completed without them.

---

## 14. Open items before I1 can close

| # | Item | Owner | Status |
| --- | --- | --- | --- |
| 1 | Create the Sentry Cloud **EU** organization and `wellapath-mobile` project | Founder | **done** |
| 2 | Accept provider terms and DPA; record retention | Founder | **pending** |
| 3 | Restrict project access to authorized team members; set alert recipients | Founder / eng lead | **pending** |
| 4 | Provide `SENTRY_DSN` as a protected CI secret | Eng lead | **done** — environment-scoped, required reviewers |
| 5 | Provide `SENTRY_AUTH_TOKEN` and wire symbol upload into `ci.yml` | Eng lead | **not required** — Dart traces are unobfuscated (§11) |
| 6 | Verify a sanitized fatal, async fatal and non-fatal appear in the dashboard | Mobile | **done** — run `31794343788` (§11) |
| 7 | Confirm no user, breadcrumbs, screenshots, view hierarchy, replay, request data or prohibited context appears on a real event | Mobile | **done** — 0 users, tags clean (§11) |
| 8 | Confirm grouping and symbolication are useful for engineering | Mobile | **done** — 1 grouped issue, stack traces present |
| 9 | Decide whether native crash handling is worth a separate native-envelope review | Eng lead | **carried forward to W9 / external beta** |

Remaining blockers for I1 closure are items **2 and 3** — both founder-supplied
governance facts, neither obtainable from this repository.
