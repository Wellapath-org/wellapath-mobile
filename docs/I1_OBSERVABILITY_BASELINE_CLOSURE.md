# I1 — Observability & Baseline: Closure Record

**Phase:** I1 (Observability & Baseline)
**Workstreams:** W1 privacy-safe product analytics · crash monitoring
**Develop at closure:** `bb39c6118cc0737972fb412c5c69278c758012ec` (PR #65 merge)
**Date of record:** 2026-08-14

---

## 1. Gate summary — answer first

| Question | Answer |
| --- | --- |
| **I1 technical engineering gate** | **PASSED** |
| **Sentry-enabled distribution beyond the authorized internal engineering group** | **BLOCKED** pending DPA acceptance |
| **External beta** | **NOT AUTHORIZED** |
| **I2 engineering work** | May begin **after this closure PR is approved and merged** |
| **Application architecture** | **UNCHANGED** |

The DPA is a vendor-governance requirement gating *distribution*, not an
unfinished code implementation. Every technical I1 deliverable is implemented,
tested and validated. Nothing in the engineering scope of I1 remains open.

**This document does not assert that the DPA is accepted.** It is pending formal
electronic acceptance — see §4.

---

## 2. What "passed" covers, and what it does not

Read this section before quoting anything below.

**Covered:** the Flutter/Dart crash path, privacy-safe product telemetry against
backend contract v1.0, and clinical-safety equivalence — all validated on a
low-end **Android emulator** and against **staging**.

**Not covered, and not claimed anywhere in this record:**

* native crash capture (deliberately disabled — §7);
* true crash-free-session metrics (sessions deliberately disabled — §7);
* physical low-end handset behaviour (emulator only);
* Top-50 clinical case-bank execution (fixture absent — §7);
* production monitoring (gated off — §6);
* external-beta authorization.

---

## 3. Architecture and clinical constraints — all intact

| Locked principle | State at closure |
| --- | --- |
| WellaPath is a CDSS, never a diagnosis engine | unchanged |
| No symptom-level PHI stored server-side | unchanged — telemetry carries none, and PHI is prohibited from Sentry |
| Scoring executes on-device only | unchanged — verified by clinical regression |
| Red flag overrides scoring output | unchanged — verified OFF and ON |
| Artifacts versioned, never overwritten | unchanged — no artifact touched in I1 |
| No secrets in source | unchanged — DSN is environment-scoped only |

No engine, artifact, red-flag, scoring or assessment file was modified by any
I1 change.

---

## 4. Governance — confirmed operational facts

| Fact | Value |
| --- | --- |
| Authorized Sentry access | **2 users** — 1 Team Admin, 1 Contributor |
| Open Membership | **disabled** |
| Beta testers with Sentry access | **none** |
| Current plan | Business Plan **Trial** — temporary |
| Selected ongoing plan | **Team** |
| Ongoing error-event retention (Team) | **30 days** |
| Terms | **version 3.0 accepted** |
| BAA | **unavailable on Team**, and **not relied upon** — PHI is prohibited from Sentry by the approved architecture |
| **DPA** | **PENDING formal electronic acceptance** |
| Alert recipients | the **2 authorized users** (Team Admin, Contributor) |
| Alert scope | new and regressed issues in `internal-beta` |
| Forwarding | **none** — no public channel, no beta-tester, no raw-payload, no webhook |

Retention is a property of the **plan**. If the plan changes, the 30-day figure
**must be reconfirmed** and this record updated.

### DPA disposition

DPA acceptance gates **distribution of Sentry-enabled builds beyond the
currently authorized internal engineering group**. It does not gate closing the
I1 technical engineering phase, and it does not gate starting I2.

Until it is accepted, Sentry-enabled builds stay within the authorized internal
engineering group.

---

## 5. Completed evidence

### 5.1 Backend telemetry — supplied by the backend workstream

Recorded here as the interface this repository was built against; validated in
the backend repository, not in this one.

* telemetry contract **v1.0**;
* staging acceptance and the privacy-log gate;
* **25/25** verification;
* safe log sink;
* retention and operational limitations documented;
* rollback path.

### 5.2 Mobile telemetry — validated in this repository

* **Contract parity** — a hand-written Dart mirror of the backend allowlist,
  tested in **both** directions; CI fails on contract drift.
* **Schema conformance** — serialised fixtures validated against the backend's
  own `telemetry.v1.schema.json`.
* **Offline queue** — Hive-backed FIFO, 500 cap, drop-oldest, 30-day expiry,
  schema-versioned, corruption recovery.
* **Retry and de-duplication** — batching 1–20, size limits, deterministic
  backoff, stable event IDs across retries, `telemetry_disabled` handling.
* **Prohibited-data defenses** — ~60 adversarial injection attempts, plus proof
  that rejected values reach neither queue, transport, nor diagnostics.
* **Live staging validation** — the full staging gate runs against the deployed
  endpoint and passes.
* **`os_version` omission fix** — `Platform.operatingSystemVersion` returned a
  kernel uname string on Android, yielding a contract-*valid* but semantically
  wrong value the backend could not have rejected. Fixed by omitting the
  optional field entirely on all platforms; no proxy, no new dependency.
* **Low-end performance** — startup, 20 observations per mode per kind,
  interleaved: cold **−4.2 %**, warm **+7.9 %** mean / **−15.4 %** median,
  Welch t ≈ 0.3. No material regression.
* **Low-end memory** — equivalent-state TOTAL PSS deltas in both directions;
  repeated after-flush across 3 controlled pairs: median **+0.11 %**, mean
  **−0.27 %**. No persistent material regression.

Zero crashes, fatal exceptions, ANRs, memory-pressure terminations, queue
corruption or unexpected retries in either mode, across every run.

### 5.3 Clinical safety

* Scoring remains **on-device**; telemetry cannot observe, alter or delay
  clinical state.
* **Red flags override scoring** — identical presentation and immediacy,
  **3.3 s** in both modes; **3.2 s** with a populated queue.
* **Offline assessment** completes on-device with an identical result and **0**
  events delivered.
* **Red-flag OFF/ON equivalence** — identical scoring outcomes (URGENT /
  Malaria, Pneumonia (Children), Dysentery) and telemetry indistinguishability.
* Existing clinical behaviour **unchanged**.

### 5.4 Crash monitoring

* Provider **Sentry Cloud, EU region**; **Flutter/Dart monitoring only**.
* Protected workflow run
  [`31794343788`](https://github.com/Wellapath-org/wellapath-mobile/actions/runs/31794343788)
  transmitted exactly **three** sanitized validation events through the real
  crash path, approved through the `internal-beta` environment gate by a human
  reviewer with no admin bypass.
* Human dashboard inspection confirmed: **3 events**, **1 grouped issue**,
  **0 users**, **2 fatal / 1 non-fatal**, one event per `crash_source`
  (`flutter_framework`, `platform_dispatch`, `handled`), exception type
  `CrashValidationError` with a **redacted** value, **useful stack traces**, no
  duplicates, only expected safe operational tags, and **no clinical,
  assessment, location, identity or telemetry identifier**.
* **Provider-unavailable behaviour verified** — startup unaffected, offline
  assessment identical, red flag still 3.3 s, zero crashes or ANRs, no failure
  propagates to the application.
* **Default-disabled** in every ordinary build; internal-beta requires two
  independent gates (`CRASH_REPORTING_ENABLED=true` **and** a structurally valid
  `SENTRY_DSN`), with a third gate holding production closed.

Full detail, including the sanitized dashboard matrix, is in
[`docs/CRASH_MONITORING.md`](CRASH_MONITORING.md) §11.

### 5.5 Post-merge regression from `develop`

`flutter analyze` clean · `dart format` clean · **673 passed / 13 skipped / 0
failed** · staging-gated telemetry **340 passed / 0 skipped**.

The 13 skips are the Top-50 clinical case bank (6, fixture absent — §7) and the
staging tests (7), which were run separately and passed.

---

## 6. Configuration state at closure

| Setting | State |
| --- | --- |
| Crash reporting in ordinary builds | **disabled** |
| Native crash handling | **disabled** |
| Automatic session tracking | **disabled** |
| Breadcrumbs | `maxBreadcrumbs = 0` |
| Screenshots / view hierarchy / replay / attachments | **disabled** |
| Tracing / profiling / user-interaction tracing | **disabled** |
| HTTP request capture (`captureFailedRequests`) | **disabled** |
| User identity (`sendDefaultPii`) | **disabled** |
| Production monitoring | **gated off** — requires separate approval |
| Public beta | **gated off** |
| Symbol-upload auth token | **none, and not required** while Dart traces are unobfuscated |

---

## 7. Limitations and carried-forward work

| # | Item | Gate | Owner |
| --- | --- | --- | --- |
| 1 | **DPA pending formal electronic acceptance** | before Sentry-enabled distribution beyond the authorized internal engineering group | Founder |
| 2 | **Native crash capture disabled** — native fatal crashes are not reported | before external beta / W9 | Mobile / eng lead |
| 3 | **True crash-free sessions unavailable** — sessions disabled, so any crash-free figure would overstate coverage | before external beta / W9 | Mobile / eng lead |
| 4 | **Physical low-end handset validation** — emulator only so far | before external beta | Mobile |
| 5 | **Analytics consent decision** | before external beta | Product / Privacy |
| 6 | **Backend `/internal/metrics` is unauthenticated** — must be protected or disabled | before external beta | Backend |
| 7 | **Team error-event retention is 30 days** — reconfirm if the plan changes | ongoing | Founder / eng lead |
| 8 | **Crash disablement requires a new build or DSN revocation** — no runtime remote kill switch | ongoing | Eng lead |
| 9 | **Corrected `internal-beta-validation.yml` lives on `main`**; `develop` carries an older copy from PR #65. Inert today (dispatch registers only from the default branch) but must be reconciled | next controlled branch integration | Eng lead |
| 10 | **`admin_area_code` artifact mapping pending** | before the field can be populated | Facilities / data owner |
| 11 | **Top-50 case-bank execution blocked** — `case_bank_v1.json` absent; only harness behaviour is covered | before external beta | Data engineer |
| 12 | **Supabase free-tier reliability risk** | pre-production gate | Backend / founder |

---

## 8. What this record does not say

Stated explicitly so no downstream summary overstates it:

* The **DPA is not accepted** — it is pending.
* **Native crash coverage is not complete.**
* **Physical-device validation is not complete.**
* The **Top-50 case bank has not been executed.**
* **External beta is not approved.**
* **Production monitoring is not enabled.**

---

## 9. Closure conditions

I1 closes when this documentation-only PR is reviewed and merged into
`develop`. **I2 must not begin before then.**

Items 2–12 in §7 are carried forward and are not I1 deliverables. Item 1 gates
distribution, not closure.
