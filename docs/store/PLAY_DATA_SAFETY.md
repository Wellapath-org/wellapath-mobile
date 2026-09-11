# Play Console — Data Safety evidence worksheet

**Build:** 0.3.0+210 · `org.wellapath.app` · internal testing, staging only.
**Status:** evidence prepared; the form itself is filled in the Play Console
(no console access yet). Every answer below cites where the behaviour lives
in code so the person filling the form is not relying on memory.

## Ground truth about data flows

| Flow | Off device? | Where | Evidence |
|---|---|---|---|
| Symptom answers, scoring, results | **Never** | on-device only | LOCKED PRINCIPLES #2/#3; engine runs locally (`lib/core/engine/`); Dio interceptor logs no bodies |
| `/config` + clinical artifacts | download only | staging backend + R2 CDN | `config_service.dart`, `staged_artifact_loader.dart` — plain GETs, nothing user-derived sent |
| Precise location | **No** — read on device to sort facilities and centre the map | — | `geolocator`; `facility_locator_service.dart` computes distance locally |
| Map tiles | tile indices (z/x/y) of the viewed area go to the tile CDN | `basemaps.cartocdn.com` (CARTO) | `locator_screen.dart` TileLayer — ephemeral servicing of the map view; nothing stored by us |
| Telemetry events | only when `TELEMETRY_ENABLED=true` (default **false**; shipped `.env` is false) | staging backend | contract v1.0 (`lib/core/telemetry/contract/`): funnel events, random per-assessment session id, `admin_area_code` (state level), app version/build, platform. No os_version, no device id, no symptom tokens (privacy guard enforces) |
| Crash reports | only when a DSN + both crash gates are supplied at build time (none bundled) | Sentry EU | `sentry_crash_sink.dart`: `sendDefaultPii=false`, no breadcrumbs, no screenshots, redacted exception values, `tracesSampleRate=null` |

No account system, no advertising SDK, no tracking SDK, no third-party
analytics beyond the above.

## Recommended form answers

**Does your app collect or share any of the required user data types?**
→ **Yes** (telemetry/crash capability exists in internal builds; declaring
"No" would be false the moment an internal build enables them).

| Data type | Collected | Shared | Ephemeral | Required/Optional | Purposes |
|---|---|---|---|---|---|
| Location → Approximate location | Yes (state-level `admin_area_code` in telemetry, only when telemetry is enabled) | No | No | Optional (feature works without granting location; manual state picker exists) | Analytics |
| Location → Precise location | **Not collected** (accessed on device only; tile fetches are ephemeral servicing) | No | — | — | — |
| App activity → App interactions | Yes (telemetry funnel events, when enabled) | No | No | Optional | Analytics |
| App info and performance → Crash logs | Yes (when crash reporting is enabled for a build) | No | No | Optional | Analytics / App functionality |
| Health info | **Not collected** — symptom input never leaves the device | No | — | — | — |
| Personal identifiers / name / email / contacts / photos / files / audio | Not collected | — | — | — | — |

**Is all of the user data collected by your app encrypted in transit?** → Yes
(HTTPS everywhere; no cleartext endpoints configured).

**Do you provide a way for users to request that their data is deleted?** →
Telemetry/crash data carries no user identifier, so no per-user deletion is
possible or applicable; state this in the form's free-text if asked. A
privacy-policy statement covering this is **required before submission**
(see `SUPPORT_AND_PRIVACY_POLICY.md`).

## Independent security review / data-deletion URL

Not applicable at internal-testing stage; revisit before production.

## Caveats for the form-filler

- If the first uploaded build keeps `TELEMETRY_ENABLED=false` and no Sentry
  DSN (the current artifact does), it factually collects **nothing** — the
  "Yes" answers above are forward-safe declarations so a later internal
  build that enables telemetry does not contradict the published form.
- Never answer "data is encrypted at rest", "independent review", or any
  claim not verified here.
