# Crash Monitoring — Operations and Runbook

**Phase:** I1 (Observability & Baseline) · final gate
**Provider:** Sentry Cloud, **EU region**
**SDK:** `sentry_flutter` **9.27.0**
**Scope:** approved **internal-beta** builds only
**Status:** implemented, **disabled by default in every build**

> **I1 is not closed by this document.** Closure additionally requires PR review
> and merge, provider dashboard verification, internal-beta crash receipt, and
> access/retention confirmation — see §11.

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

## 11. Open items before I1 can close

| # | Item | Owner |
| --- | --- | --- |
| 1 | Create the Sentry Cloud **EU** organization and `wellapath-mobile` project | Founder |
| 2 | Accept provider terms and DPA; record retention | Founder |
| 3 | Restrict project access to authorized team members; set alert recipients | Founder / eng lead |
| 4 | Provide `SENTRY_DSN` as a protected CI secret | Eng lead |
| 5 | Provide `SENTRY_AUTH_TOKEN` and wire symbol upload into `ci.yml` | Eng lead |
| 6 | Verify a sanitized fatal, async fatal and non-fatal appear in the dashboard | Mobile |
| 7 | Confirm no user, breadcrumbs, screenshots, view hierarchy, replay, request data or prohibited context appears on a real event | Mobile |
| 8 | Confirm grouping and symbolication are useful for engineering | Mobile |
| 9 | Decide whether native crash handling is worth a separate native-envelope review | Eng lead |

Items 1–5 are **external setup that cannot be done from this repository**.
Items 6–8 require them first.
