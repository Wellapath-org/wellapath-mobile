# Telemetry MVP — which subset to switch on first

**Status: proposal. Nothing here is approved and nothing is enabled.**
Telemetry is disabled by two independent gates in every build to date and stays
disabled until this is separately reviewed and approved.

**Scope:** product analytics only. Crash diagnostics are a different subsystem
with different data, separate gates and a separate decision — see
`SENTRY_ACTIVATION_CHECKLIST.md` and `CRASH_MONITORING.md`.

This document does **not** restate how the pipeline works. `TELEMETRY_MOBILE.md`
is the reference for the contract, the queue, the transport, the retry policy
and the privacy guard, and remains authoritative for all of it. What follows is
only the part that is not written down anywhere: **which events should be
enabled first, and why the rest should not be.**

---

## 0. The premise this started from was wrong

The work was briefed as "produce a privacy-safe MVP specification before
implementation". There is no implementation to precede. Telemetry has been
complete since the I1/W1 phase and is switched off, not absent.

Verified directly against `develop` @ `d84fdac`:

| | |
|---|---|
| Implementation | 10 files, 2,606 lines under `lib/core/telemetry/`, covering config gating, the event contract, the queue, transport, the privacy guard and runtime seams |
| Tests | `test/telemetry/` holds **251 static `test(` invocations across 13 files**, which expand to **340 executed cases** because 12 sites generate tests from a literal collection. A default run reports **333 passed, 7 skipped** — the 7 are the deployed-staging group, gated behind an environment variable |
| Contract | v1.0, a hand-written deterministic mirror of the backend allowlist, drift-guarded in both directions |
| Vocabulary | 12 events defined; **10 have a producer in `lib/`, 2 do not** — and the two are different cases, see below |
| Gates | `TELEMETRY_ENABLED=false` and `TELEMETRY_PRODUCTION_APPROVED=false` in the bundled `.env`, with `APP_ENV=production`. Either flag alone is enough to keep it off |

> **Correction to an earlier internal report.** That report gave the figure as
> "268 tests". 268 is not the count by any measure: it is 17 too high as a
> static count and 72 too low as an executed count, and it has never matched
> at any commit in the file's history. The figures above are the measured ones.

**Not every contract event is wired, and the two gaps are not the same thing.**

* **`feedback_submit` has no producer, and that is expected.** The feedback
  feature is gated off by `FeatureFlags.feedbackEnabled`, which is a
  compile-time constant that is false in every build, and its screen documents
  itself as unreachable. An event for a feature that cannot fire would be dead
  weight. This one resolves itself if and when feedback is activated, and needs
  no action now.
* **`library_article_view` has no producer, and that is a real gap.** The Learn
  feature is not gated: `lib/features/learn/learn_screen.dart` is a live shell
  tab reachable by every user. So this event is simply not instrumented, which
  is a different situation from the one above and should not be described as
  expected.

Neither absence is a defect in the pipeline, and no claim should be made that
all twelve events are wired.

The useful question is therefore not what to build. It is **what to switch on
first, and what to leave off.**

### The proposed vocabulary does not match the shipped one

A proposed event list circulated as `app_opened`, `onboarding_completed`,
`symptom_check_started`, `symptom_check_completed`, `locator_opened`,
`learn_opened`, `help_opened`. None of those names exists. Renaming means a
coordinated contract v1.1 on Mobile and Backend, with the parity test updated
in the same change.

| Proposed | Shipped | Assessment |
|---|---|---|
| `app_opened` | `app_open` | The same event. Keep the shipped name. |
| `symptom_check_started` | `assessment_start` | The same event. Keep the shipped name. |
| `symptom_check_completed` | `assessment_complete` | The same event, and the shipped one distinguishes completed, abandoned and interrupted, which the proposal would collapse into one number. Keep the shipped name. |
| `onboarding_completed` | none | Genuinely new. Worth adding. |
| `locator_opened` | none | Genuinely new, and safer than the facility events that do exist. |
| `learn_opened` | none | Genuinely new, and safer than `library_article_view`. |
| `help_opened` | none | Genuinely new. |

**On the `symptom_` prefix.** The names are not themselves a leak; an event
name carries no symptom content. But the shipped vocabulary avoids the word,
and that discipline is worth keeping. The privacy guard's denylist matches
symptom-related tokens in field names, and a vocabulary that normalises
`symptom_` as an acceptable prefix invites a future property like
`symptom_count` that the guard would then have to catch. `assessment_` costs
nothing and removes the temptation.

---

## 1. Every event, challenged

### Enable

**`app_open`** — properties `launch_type`, `is_first_launch`. The denominator
for everything else. Without it no other number can be interpreted.

**`assessment_start`** — the session id is per-assessment, generated from
nothing, and dies with the object. It is not a user identifier.

**`assessment_complete`** — `completion_status` separates finished from
abandoned from interrupted. Completion rate is the single most important
product question, and the three-way status is what makes it answerable.

### Leave off

**`assessment_step_view`** — one event per step multiplies volume by the flow
length to produce a drop-off curve nobody has committed to acting on.
`assessment_complete` already carries `step_count`. Revisit when a specific
drop-off question is asked.

**`result_view`** — given `assessment_complete` with a completed status, this
adds almost nothing. The gap between completing and viewing is a rendering
detail.

**`facility_view`, `facility_call`, `directions_open`** — each carries a
`facility_id`, which is a strong proxy for where someone is. A person who calls
one clinic has effectively disclosed their neighbourhood. Defensible later with
an explicit decision; not in a first switch-on.

**`emergency_action`** — even an aggregate count of emergency-number taps is
closer to clinical outcome data than to product usage. The contract already
refuses this event a session id, which is a hint about how carefully it was
treated.

**`library_article_view`** — `article_id` reveals which health topic a person
read. Aggregate popularity is genuinely useful and deserves its own decision
rather than riding along. It also has no producer today even though the Learn
feature is live, so enabling it would mean instrumenting it first.

**`feedback_submit`** — no producer, which is expected: the feedback feature is
compile-time disabled with no backend, so the event could not fire even if
telemetry were on. Revisit when feedback is activated, not before.

### Add in contract v1.1, if wanted

`onboarding_completed`, `locator_opened`, `learn_opened`, `help_opened`. All
four are single milestones with no identifier and no content. `locator_opened`
and `learn_opened` are strictly safer than the facility and article events they
would stand in for, because neither carries an id.

### The resulting set

Three events on day one: `app_open`, `assessment_start`, `assessment_complete`.
Seven once v1.1 lands. Everything else stays defined and disabled.

That is enough to answer whether people install it, get through onboarding,
start a check and finish it, which is the whole question a launch needs
answered.

---

## 2. Deletion, stated precisely

There is no per-user deletion request path and none is needed. No event carries
a user identifier, a device identifier or anything linking two sessions, so
there is no record to look up. Uninstalling removes the local queue.

**This should be stated in the privacy policy in exactly those terms** — not as
"we delete on request" but as "there is nothing to delete, because we never
know who you are." The first is a weaker claim that also happens to be harder
to honour.

Everything else about queuing, retention, retry limits and the kill switch is
in `TELEMETRY_MOBILE.md` and is not repeated here.

---

## 3. Dashboard definitions

The second column is the part worth agreeing before any number exists.

| Metric | Definition | Not |
|---|---|---|
| Daily opens | `app_open` per UTC day | not users, not sessions |
| Cold-start share | `launch_type=cold` ÷ all `app_open` | not a performance measure |
| First launches | `is_first_launch=true` | **not installs** — a reinstall counts again, and a blocked first flush is lost |
| Onboarding completion | `onboarding_completed` ÷ first launches, same day | approximate; the two can straddle a day boundary |
| Assessments started | `assessment_start` | not people |
| Completion rate | `assessment_complete` completed ÷ `assessment_start` | not clinical accuracy, not usefulness |
| Abandonment rate | `assessment_complete` abandoned ÷ started | not dissatisfaction |
| Interrupted rate | `assessment_complete` interrupted ÷ started | **not a red-flag rate** — do not present it as one |
| Median duration | median `duration_ms` where completed | not time-to-value |
| Locator opens | `locator_opened` | not searches, not facility views |
| Help opens | `help_opened` | not support volume |

**Every one is an event count, not a person count.** Nothing in this design can
produce a user count, a retention cohort or a funnel that follows one person
across sessions, because nothing links two sessions. A dashboard claiming a
"user" number from this data is wrong, which is why the third column exists.

While telemetry is disabled every metric here renders as **Disabled**. Not
zero, not blank, not 100 per cent.

---

## 4. Decide before anything is enabled

1. **Analytics consent.** Unresolved. Owner: Product and Privacy. The config
   plumbing for a runtime gate is ready; the decision is not.
2. **This event set.** Approve or amend section 1. The exclusions are
   recommendations, not facts.
3. **Contract v1.1**, if the four new events are wanted. Coordinated change on
   Mobile and Backend with the parity test updated in the same commit.
4. **Backend enablement.** The endpoint currently answers `503
   telemetry_disabled`, which is why 2 of the 7 staging integration tests skip.
5. **Store declarations.** Both stores declare "no data collected" today.
   Enabling telemetry makes that false, and the declarations must change in the
   same release — the same rule as crash reporting, for the same reason.
6. **Physical low-end handset validation.** Only emulator validation exists.

---

## 5. A correction to make while here

`TELEMETRY_MOBILE.md` section 10 states that no crash provider exists in this
repository and that stack traces are not forwarded. Both were true when written
and are now false: crash reporting landed afterwards and stack traces are
forwarded, sanitised per frame. The same stale text is duplicated in the header
comment of `lib/core/crash/crash_reporter.dart`.

Correct both, so that a reader assessing privacy is not reassured by a claim
that has expired.
