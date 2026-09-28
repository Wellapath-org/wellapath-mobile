# Telemetry MVP — privacy-safe specification

**Status: proposal. Nothing here is approved and nothing is enabled.**
Telemetry is disabled by two independent gates in every build to date and stays
disabled until this document is separately reviewed and approved.

**Scope:** product analytics only — anonymous, aggregate, count-level product
usage. This document says nothing about crash diagnostics; see
`SENTRY_ACTIVATION_CHECKLIST.md`. The two subsystems share no code, no
transport, no keys and no decision.

---

## 0. Read this first — the brief's premise needs correcting

The instruction for this work was to *"produce a privacy-safe MVP specification
before implementation."* **A complete telemetry implementation already exists
in this repository and has since the I1/W1 phase.** It is switched off, not
absent. Specifically:

| | |
|---|---|
| Code | `lib/core/telemetry/` — config, service, Hive-backed queue, Dio transport, runtime, privacy guard, typed contract |
| Tests | 268 |
| Contract | v1.0, a hand-written deterministic mirror of the backend allowlist, drift-guarded in both directions |
| Event vocabulary | 12 defined, 10 emitted |
| Instrumentation | Live call sites in `app.dart`, `home_screen`, `locator_screen`, `results_screen`, `red_flag_interrupt_screen`, `assessment_controller` — all inert while disabled |
| State | `TELEMETRY_ENABLED=false` and `TELEMETRY_PRODUCTION_APPROVED=false` in the bundled `.env`; no `TELEMETRY_BASE_URL`, which fails the config closed independently |

This changes what "MVP" means. The useful question is no longer *what should we
build* but **what subset of what already exists should be switched on first,
and what should stay off.** That is what this document specifies. Treating it
as a greenfield design would mean discarding a reviewed, backend-agreed
contract and rebuilding it slightly differently — expensive and strictly worse.

### The proposed vocabulary collides with the agreed contract

The brief proposes: `app_opened`, `onboarding_completed`,
`symptom_check_started`, `symptom_check_completed`, `locator_opened`,
`learn_opened`, `help_opened`.

None of these names exists. The shipped contract uses different ones, and the
backend allowlist is pinned to them by a parity test in both directions.
Renaming means a coordinated contract v1.1 on both sides.

| Proposed | Shipped equivalent | Assessment |
|---|---|---|
| `app_opened` | `app_open` | Same event, different tense. **Keep `app_open`.** |
| `onboarding_completed` | *none* | Genuinely new. See §2. |
| `symptom_check_started` | `assessment_start` | Same event. **Keep `assessment_start`** — see the naming note below. |
| `symptom_check_completed` | `assessment_complete` | Same event, and the shipped one distinguishes completed / abandoned / interrupted, which the proposal loses. **Keep `assessment_complete`.** |
| `locator_opened` | *none* — `facility_search` fires on search, not open | Genuinely new, and weaker than what exists. See §2. |
| `learn_opened` | `library_article_view` is article-level | Genuinely new, and coarser. See §2. |
| `help_opened` | *none* | Genuinely new. See §2. |

**On the name `symptom_check_*`.** The proposed names are not themselves a
privacy leak — an event name carries no symptom content. But the existing
vocabulary deliberately avoids the word, and that discipline is worth keeping:
the privacy guard's denylist matches symptom-related tokens in field names, and
a vocabulary that normalises `symptom_` as an acceptable prefix invites a future
property like `symptom_count` that the guard would then have to catch. Keeping
`assessment_` costs nothing and removes the temptation. **Recommendation: keep
the shipped names.**

---

## 1. The privacy boundary — what may never be sent

This is the part that is not negotiable, and it is already enforced in code by
two independent layers: a sealed typed contract in which a prohibited field
*cannot be expressed*, and a runtime `PrivacyGuard` that validates every event
twice — once before it is written to the queue and once before it leaves the
device.

**Never transmitted, under any flag combination:**

- Symptoms, symptom tokens, body areas, any selection the user made
- Answers to any assessment question, and any count derived from them
- Results, urgency categories, red-flag state, scores, medical guidance
- GPS coordinates, precise or coarse location, admin area codes
- Facility search text, clinic names the user searched for
- Free text of any kind — feedback bodies, support messages, notes
- A persistent user ID, a device ID, an advertising ID, any fingerprint
- Anything that links two sessions to the same person
- OS version (omitted deliberately: Android's value is a kernel uname string,
  and a normaliser once shipped `"64"` from an Android 8.0.0 device)

**Three fields exist in the contract and are deliberately never populated.**
Keep them unpopulated:

- `admin_area_code` — the artifact-to-ISO-3166-2 mapping is unconfirmed
- `step_count` on `assessment_step_view` — the flow total is derived from
  selected symptom tokens, so sending it on every step would leak an
  answer-derived quantity
- `search_mode: name` — no name search exists

**Hashing is not sanitisation.** A prohibited value is dropped, never hashed
and forwarded. A hash of a symptom is still a symptom.

---

## 2. Every event, challenged for necessity

The brief asked that each event be challenged. Several do not survive.

### Recommended for the MVP

**`app_open`** — *keep.* Properties: `launch_type` (cold/warm),
`is_first_launch`. It is the denominator for every other rate. Without it no
other number can be interpreted.

**`assessment_start`** — *keep.* Properties: `assessment_session_id`,
`flow_version`, `entry_point`. The session id is per-assessment, generated from
nothing, and dies with the object; it is not a user identifier.

**`assessment_complete`** — *keep.* Properties: session id,
`completion_status` (completed / abandoned / interrupted), `duration_ms`,
`step_count`. Completion rate is the single most important product question,
and the three-way status distinguishes "finished" from "gave up" from
"interrupted by a red flag" — which the proposed binary `symptom_check_completed`
would collapse into one number.

### Rejected — do not enable in the MVP

**`assessment_step_view`** — *reject for MVP.* One event per step multiplies
volume by the flow length for a drop-off curve nobody has yet committed to
acting on. `assessment_complete` already carries `step_count`, which answers
"how far did they get" in one event instead of N. Revisit only if a specific
drop-off question is asked.

**`result_view`** — *reject.* Given `assessment_complete` with status
`completed`, this adds almost nothing. The gap between completing and viewing
is a rendering detail.

**`facility_call`, `directions_open`** — *reject for MVP.* These are the most
sensitive events in the contract: they carry a `facility_id`, which is a strong
proxy for location. A user who calls one clinic has effectively disclosed their
neighbourhood. Justifiable later with an explicit decision; not in a first
switch-on.

**`facility_view`** — *reject*, same reason.

**`emergency_action`** — *reject.* It is a red-flag-adjacent signal, and even
the aggregate count of emergency-number taps is closer to clinical outcome data
than to product usage. The contract already refuses it a session id; treat that
as a hint about how careful this one is.

**`library_article_view`** — *reject for MVP.* `article_id` reveals what
health topic a person read. Aggregate popularity is genuinely useful, but it is
health-interest data and deserves its own decision rather than riding along.

**`feedback_submit`** — *reject.* Feedback is disabled in the app and has no
backend. An event for a feature that cannot fire is dead weight.

### New events the brief proposes

**`onboarding_completed`** — *accept in principle, not yet implemented.*
Genuinely useful and genuinely safe: a single boolean-shaped milestone.
Requires a contract v1.1 on both sides.

**`locator_opened`** — *accept in principle, and prefer it to the
facility events above.* Knowing the locator was opened is useful and carries no
facility id. Requires contract v1.1.

**`help_opened`** — *accept in principle.* Safe, and a proxy for confusion
that costs nothing. Requires contract v1.1.

**`learn_opened`** — *accept in principle, and prefer it to
`library_article_view`.* Section-level open, no `article_id`, so no
health-interest disclosure. Requires contract v1.1.

### The resulting MVP set

Enable: `app_open`, `assessment_start`, `assessment_complete`.
Add in contract v1.1: `onboarding_completed`, `locator_opened`, `learn_opened`,
`help_opened`.
Keep defined but disabled: everything else.

Three events on day one. Seven once v1.1 lands. That is enough to answer
"do people install it, get through onboarding, start a check, and finish it" —
which is the entire question a launch needs answered.

---

## 3. Transport, queue and retention

All of this already exists and needs no change; it is restated so the review
covers it.

**Endpoint.** `POST /v1/telemetry/events`, path from the contract, base URL
from config, never hard-coded. Unauthenticated, no secret.

**Envelope.** `contract_version`, `sent_at`, `app` (exactly `platform`,
`app_version`, `app_build`), `events`. Per event: `event_name`, `event_id`,
`client_ts`, plus the event's own scalar properties. No nested objects, no
arrays — the contract has no such type, which is itself a privacy control.

**Offline queuing.** Hive box `telemetry_queue` in the app data directory.
FIFO, capped at 500 events, drop-oldest on overflow. Removed by app uninstall.
Events are removed from the queue **only after a confirmed outcome**, so a kill
mid-flight re-sends with the original `event_id` and `client_ts` — at-least-once
delivery, deduplicated server-side by `event_id`.

**Retention on device.** 30 days. Anything older is discarded at flush time,
unsent. A corrupt record is discarded, never migrated.

**Retry limits.** 3 attempts per batch, backoff `[2s, 4s, 8s]` with equal
jitter in `[0.5, 1.0]`. `Retry-After` honoured when longer, capped at 60s,
delta-seconds form only. 4xx other than 429 is never retried — the batch is
dropped. 429/5xx/network/timeout retry within the limit.

**Kill switch.** A `503 telemetry_disabled` or a
`400 unsupported_contract_version` discards the batch, clears the queue,
disables the session and makes every later capture a no-op. The server can
therefore stop a client without an app update. This is the only remote control
that exists and it is one-directional — the server can switch telemetry off,
never on.

**Flush cadence.** 60s timer, plus an eager flush at a full batch of 20,
started after `runApp`.

**Deletion.** There is no per-user deletion request path and none is needed:
no event carries a user identifier, a device identifier or anything that links
sessions, so there is no record to look up. Uninstalling removes the local
queue. **This is a consequence of the design and should be stated in the privacy
policy in exactly those terms** — not as "we delete on request" but as "there is
nothing to delete, because we never know who you are."

---

## 4. Dashboard definitions

Each metric below, and what it is *not*. These feed the launch command centre,
which must render "Disabled" — never `0` — while telemetry is off.

| Metric | Definition | Not |
|---|---|---|
| Daily opens | count of `app_open` per UTC day | not users, not sessions |
| Cold-start share | `app_open` with `launch_type=cold` ÷ all `app_open` | not a performance measure |
| First launches | `app_open` with `is_first_launch=true` | **not installs** — a reinstall counts again, and a blocked first flush is lost |
| Onboarding completion | `onboarding_completed` ÷ first launches, same day | approximate; the two can straddle a day boundary |
| Assessments started | count of `assessment_start` | not people |
| Completion rate | `assessment_complete` with `completed` ÷ `assessment_start` | not clinical accuracy, not usefulness |
| Abandonment rate | `assessment_complete` with `abandoned` ÷ `assessment_start` | not dissatisfaction |
| Interrupted rate | `assessment_complete` with `interrupted` ÷ `assessment_start` | **not a red-flag rate** — do not present it as one |
| Median duration | median `duration_ms` where status is `completed` | not time-to-value |
| Locator opens | count of `locator_opened` | not searches, not facility views |
| Help opens | count of `help_opened` | not a support volume |

**The counting rule that matters:** every one of these is an event count, not a
person count. Nothing in this design can produce a user count, a retention
cohort or a funnel that follows one person across sessions, because nothing
links two sessions. Any dashboard that claims a "user" number from this data is
wrong, and the definitions above say so in the "Not" column deliberately.

**When telemetry is disabled**, every metric here renders as **Disabled**. Not
zero, not blank, not 100%.

---

## 5. What must be decided before anything is enabled

1. **Analytics consent.** Unresolved. Owner: Product + Privacy. If consent is
   required, `TelemetryConfig` gains a runtime gate and `Telemetry.init` reads
   it — the plumbing is ready, the decision is not.
2. **This event set.** Approve or amend §2. The rejections are
   recommendations, not facts.
3. **Contract v1.1**, if the four new events are wanted. Coordinated change on
   Mobile and Backend, with the parity test updated in the same change.
4. **Backend enablement.** The endpoint currently returns
   `503 telemetry_disabled`. Two of seven staging integration tests skip
   because of it.
5. **Store declarations.** Both stores currently declare "no data collected".
   Enabling telemetry makes that false and the declarations must change in the
   same release — the same rule as Sentry, for the same reason.
6. **Physical low-end handset validation.** Only emulator validation exists
   (Android 8.0.0 API 26, 2 GB, software rendering; no measurable regression
   found, but an emulator is not a handset).

---

## 6. A correction to make while here

`docs/TELEMETRY_MOBILE.md` §10 states that no crash provider exists in this
repository and that stack traces are not forwarded. Both were true when
written and are now false — Sentry landed afterwards and stack traces are
forwarded, sanitised per frame. The same stale text is duplicated in the
header comment of `lib/core/crash/crash_reporter.dart`. Correct both, so a
reader assessing privacy is not reassured by a claim that has expired.
