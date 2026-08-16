# QB-002 — Immediate Red-Flag Interruption

A red-flag clarifier answered "Yes" now interrupts the assessment at once,
instead of after up to four further questions.

> **Behind a default-off flag.** `--dart-define=W3_IMMEDIATE_RED_FLAG=true`.
> With the flag unset — every ordinary build, every test run, every release
> today — `_onNext` takes exactly the path it took before. That is the rollback.

**Authoritative handoff:** `wellapath-knowledge-base` @
`aa7a2f13c577ea23f78235d9d8585416bd07f9de`,
`mobile_handoff/question_flow_v1/IM002_SAFETY_FIX.md`
(sha256 `6bc1863d02ec565f2f0e47ca1a536a97e17e62add9cb341553666d195df9d29c`),
evidence `reports/qb002_evidence_v1.json`
(sha256 `3a82e89571371344271302aaa2a9bcd640fb0582a0dc7c1a54f6270c163b4f8a`).
All three supplied hashes were verified against that commit before anything was
relied on. **The question candidate was not vendored and is not a runtime
artifact.**

---

## 1. Root cause

`_answers` is a widget-local `Map<int, dynamic>`. `_commitAnswers()` — the only
thing that writes answers into `AssessmentController` — was called **only in the
final-question branch** of `_onNext`. Every answer, including a clarifier that
declares a danger sign, sat in widget state until the questionnaire ended.

So the engine could not see the red flag until the user had finished. It then
handled it perfectly: `RedFlagEvaluator` runs before `ScoringEngine`, a matched
global rule returns `proceedToScoring: false`, `ScoringEngine.score` throws if
called with that false, and `UrgencyDeterminer` checks `redFlagTriggered` at
priority 1.

**This was never an under-triage defect.** The 239-case bank reports 124/124
red-flag cases at emergency and **zero safety-critical under-triage**, before
and after. The harm was delay: someone who had just declared a danger sign was
asked up to four more routine questions before being told to seek emergency
care — and could abandon first, receiving nothing.

### Measured worst case (live flow)

```
[0] redFlagClarifier (breathlessness_at_rest)  <- user answers "Yes"
[1] redFlagClarifier (abnormal_bleeding)       <- still asked
[2] severity                                   <- still asked
[3] duration                                   <- still asked
[4] additionalSymptoms                         <- still asked
```

Four further questions, reproduced by
`test/assessment/qb002_immediate_red_flag_test.dart`.

**Note on the handoff's example.** IM002_SAFETY_FIX.md illustrates the worst
case with four *per-symptom* follow-ups (`abdominal_cramps-severity`,
`body_pain-severity`, …). That shape belongs to the **W3 candidate** flow. The
live `QuestionEngine` de-duplicates to one severity and one duration question,
so the live worst case needs a second clarifier to reach four remaining. **The
count is the same — four — and the defect is identical.**

---

## 2. Event order

**Before** (advance branch):

```
recordStepView()  ->  setState(advance)  ->  ...  ->  last question
                                            ->  _commitAnswers()  ->  engine
```

**After**, with the flag on and the current question able to affect a red flag:

```
commit THIS answer (exactly once)
  ->  read committed controller state
  ->  red flag token present?
        yes ->  STOP. no step-view, no setState, queued questions discarded
                ->  LoadingScreen -> EngineController -> RedFlagEvaluator
                ->  RedFlagInterruptScreen (existing)
        no  ->  recordStepView()  ->  setState(advance)      [unchanged]
```

The answer is committed **before** evaluation. Evaluating against state that
does not yet include the answer would be the same bug in a new place.

---

## 3. Implementation boundary

| File | Change |
|---|---|
| `lib/features/assessment/followup_screen.dart` | The only production file changed |
| `lib/core/engine/red_flag_evaluator.dart` | **unchanged** |
| `lib/core/engine/scoring_engine.dart` | **unchanged** |
| `lib/core/engine/urgency_determiner.dart` | **unchanged** |
| `lib/features/results/red_flag_interrupt_screen.dart` | **unchanged** |
| `lib/core/telemetry/**` | **unchanged** |

**No clinical rule is duplicated in UI code.** The screen decides only *whether
to hand over early*, using the clarifier's own declared `redFlagToken` read back
out of committed controller state. The clinical decision is still made by
`RedFlagEvaluator` inside `EngineController`, reached through the existing
`LoadingScreen`, which already routes to the existing `RedFlagInterruptScreen`
with the existing emergency actions.

`_currentAnswerCanAffectRedFlag()` is derived from the question's own type and
`redFlagToken`, not a hardcoded list — a clarifier added to
`kRedFlagClarifiers` is covered automatically.

**Scoring is never invoked after a red flag:** `EngineController` short-circuits
on the red-flag path and `ScoringEngine.score` is never called. Scoring was not
moved into the screen.

---

## 4. Race and lifecycle protections

| Hazard | Protection |
|---|---|
| Double tap / repeated `_onNext` | `_transitionInProgress` guard, set before any commit and never cleared on the interrupt path — exactly one transition wins |
| Answer committed twice | `_committed` set; `_commitAnswer` is idempotent per question, and the final `_commitAnswers()` sweep skips anything already written |
| Widget disposed mid-transition | `_goToEvaluation` returns early unless `mounted` |
| Commit failure | Caught and **failed closed** — hands over to the engine rather than advancing past a possible danger sign. The exception is never swallowed into "no red flag" |
| Ordinary frame after the red flag | No `setState` on the interrupt path, so no ordinary question can be painted between the decision and handover |
| Queued questions | Discarded, not deferred |
| Cancellation | Unchanged — the existing cancel dialog still records `abandoned` and calls `clearAll()` |

---

## 5. Telemetry

**Contract v1.0 is unchanged. No event, field or status was added.**

Interception happens **before** `recordStepView()`, so an interrupted path emits
no step event for the question it prevented from appearing. Recording one would
be both untrue and a red-flag oracle.

The session was already designed for this: `recordComplete` reports
`completed` on the red-flag path exactly as on the ordinary one, and
`recordResultView` fires from **both** the results screen and the interrupt
screen. Nothing here changes that.

Regression `a red-flag path is structurally indistinguishable from abandonment`
asserts a red-flag interrupt and an abandonment at the same step produce the
same step count. No question ID, answer, symptom token, red-flag ID, rule ID,
urgency, score or path is emitted.

---

## 6. Offline

Everything on the interception path is on-device: one map write and one list
membership check. **No network call was added.** The consumer files import no
HTTP client, and the widget tests run against a binding with no client wired —
completing at all proves nothing reached for one.

The subsequent engine run uses `StagedArtifactLoader`'s cached artifacts, which
is the existing offline path, unchanged.

### Restoration — reported, not implemented

**The MVP does not persist an in-flight assessment.** Per
`assessment_telemetry_session.dart`: *"Resuming — not applicable. The MVP does
not persist an in-flight assessment; there is nothing to resume."* Answers live
in widget state and die with the route.

So the handoff's restoration requirement — and IM-004 ID-keyed answers, which it
lists as a prerequisite — **do not apply to the current application** and were
not implemented. Handoff cases 7 (edit an earlier answer) and 8 (restore state
containing a red-flag token) are **not reachable in the live flow**: there is no
answer editing and no restoration. They become live when the W3 restoration
model does, and are recorded here as deferred rather than silently skipped.

---

## 7. Evidence

### Reproduction proved failing before the fix

Disabling only the interception branch (`if (false && …)`) with the flag on made
**4 tests fail**. The assertions are real, not weakened to pass.

### Regression

22 tests in `test/assessment/qb002_immediate_red_flag_test.dart`, green in
**both** flag states.

| Handoff case | Covered |
|---|---|
| 1 — Yes with 4 queued | ✅ 0 further questions presented |
| 2 — Yes as last question | ✅ unchanged |
| 3 — No | ✅ flow continues, no red flag |
| 4 — ordinary path | ✅ exact question sequence asserted |
| 5 — clarifier suppressed when red flag already selected | ✅ unchanged (`QuestionEngine`) |
| 6 — no scoring after red flag | ✅ engine short-circuit |
| 7 — edit an earlier answer | ⚠️ not reachable — no answer editing exists |
| 8 — restore red-flag state | ⚠️ not reachable — no restoration exists |
| 9 — double tap | ✅ one interrupt, one commit |
| 10 — cancel | ✅ `abandoned`, `clearAll()` |
| 11 — airplane mode | ✅ no I/O on the path |
| 12 — 239 cases | ✅ 238 pass, CB_211 known finding |

### Clinical regression — unchanged

**239 executed · 238 passed · 1 known finding · 0 unexpected failures**, CB_211
still pinned, **0 safety-critical under-triage**, 124/124 red-flag cases
emergency with empty ranked causes. Identical in both flag states.

### Timing

| Answer kind | Flag OFF | Flag ON |
|---|---|---|
| Affirmative red-flag clarifier | 1,183 µs | 1,303 µs |
| Negative clarifier | 1,616 µs | 1,243 µs |
| Ordinary question | 1,058 µs | 1,516 µs |

The added work is **not measurable above run-to-run jitter** — flag-on is faster
than flag-off in one of the three. All well inside one 60 fps frame budget
(16,667 µs), which is the only threshold asserted. **No clinical latency
threshold was invented.**

### Runtime verification

Android release built in both flag states; iOS simulator build installed,
launched and rendering with `W3_IMMEDIATE_RED_FLAG=true`.

**A step-verified human walkthrough was NOT performed** — no Android emulator or
low-end device profile was available in this environment, and driving the full
assessment requires artifact downloads and a human observer. What exists instead
is deterministic widget coverage of each requested step (ordinary assessment,
red-flag assessment with questions remaining, offline, cancel/back) plus proof
the app launches with the flag on. **The low-end emulator profile is not
covered and is reported as a gap.**

---

## 8. Rollback

Unset the flag. Behaviour returns to today's exactly — the flag guards the whole
early-commit block, and nothing else in `_onNext` changed.

Nothing is persisted, no artifact is published, no `/config` entry exists.
A revert is a single-commit revert. Because the fix only makes evaluation
**earlier**, rolling back cannot introduce an under-triage that was not already
present.

---

## 9. Limitations and out of scope

- **IM-001** (deterministic ordering) — not implemented.
- **IM-003** (dynamic re-branching) — not implemented; it changes scoring inputs.
- **IM-004** (ID-keyed answers) — not implemented; only required by restoration,
  which the live app does not have. Answers remain index-keyed.
- The adaptive question engine, the declarative condition evaluator, the graph
  engine and loading the question candidate — all later W3 tasks.
- Question ordering, wording, answer meanings, token effects, the path limit of
  5 and optional skips are all unchanged.
- **The W3 question candidate remains unpublished and inactive**: not vendored,
  not an asset, not referenced by any `lib/` source.
