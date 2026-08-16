# Question Flow 1.0 — Offline Consumer and Deterministic Planner

An engineering consumer for the W3 question-flow candidate: a strict offline
loader, the 13-operator condition evaluator, deterministic ordering, a bounded
**initial-only** path planner, and an ID-keyed answer state model.

> ### The candidate is unpublished, clinically unreviewed and inactive
> Not an asset. Not in `pubspec.yaml`. Not imported by any screen,
> `AssessmentController` or `QuestionEngine`. The live application continues to
> use its compiled Dart question flow, unchanged.
>
> **IM-003 dynamic re-branching is not implemented.**

**Contract:** `wellapath-knowledge-base` @
`aa7a2f13c577ea23f78235d9d8585416bd07f9de`.

---

## 1. The headline finding

**Deterministic ordering (IM-001) is not activation-safe as it stands.** It does
not merely reorder questions — it changes which questions are asked.

Across all **2,325** bounded paths:

| | |
|---|---|
| Identical to the live engine | **395** |
| Differing | **1,930** |
| — order-only differences | **0** |
| — question-set changed | **1,930** |
| — of which truncation selects a different set | **1,192** |
| — involving a red-flag question | **960** |

The cause is structural, not a tie-break subtlety. The live `QuestionEngine`
**de-duplicates**: `severityQuestion ??= …` keeps the first severity question it
meets while iterating selected tokens, and merges all additional-symptom options
into one question. The candidate models **one question per token per role**. For
`[headache, fever]` the live engine asks 3 questions; the candidate plans 5.

Because the limit is 5, that difference is not cosmetic: on 1,192 paths a
different set of questions survives truncation, so a user would be asked about
different symptoms. Per the step's own rule, that is a **path/content exposure
change** and activation stays blocked pending product and clinical review.

Full record: `build/w3_question_flow/im001_tie_path_evidence.json`.

### The defect IM-001 addresses is real

The live engine **is** order-dependent — reversing the selected token order
changes which wording is asked (e.g. `abdominal_cramps + bleeding + body_pain`).
IM-001 is the right fix; it simply cannot be switched on without deciding what
the per-token question model does to path content.

---

## 2. Architecture and the isolation boundary

```
  test harness  ─────────────────────────────┐
                                             ▼
  question_flow_loader.dart   →   QuestionFlow (immutable)
        │  local bytes only                  │
        ▼                                    ▼
  condition_evaluator.dart          question_ordering.dart
        │  FlowEvaluationState              │  (priority, tie_break_key, id)
        └──────────────┬────────────────────┘
                       ▼
            initial_path_planner.dart  →  InitialPathPlan
                       │
                       ▼
              flow_answer_state.dart  (ID-keyed, isolated)

  ───────────────────────────────────────────────────────────
  LIVE PATH (untouched):  QuestionEngine → FollowupScreen →
                          AssessmentController → EngineController
```

**The boundary is that no arrow crosses.** Asserted structurally, not promised:

- no live assessment source *imports* the consumer (13 files checked);
- nothing outside `lib/core/question_flow/` imports it at all;
- the consumer imports no `dart:io`, Dio, HTTP client, artifact loader,
  telemetry, scoring engine, evaluator or `AssessmentController`;
- it contains no `fromEnvironment` — there is no flag that could enable it;
- `git diff` over `lib/features/assessment/`, `lib/core/engine/` and
  `lib/core/telemetry/` is **0 files**.

Engineering evaluation happens through tests only. No user-accessible internal
screen was added.

---

## 3. Contract provenance

34 files vendored byte-for-byte, every one hash-verified against `aa7a2f13`
before use. The five published hashes:

| File | SHA256 |
|---|---|
| `candidate/question_flow.ng.v1.0.json` | `c403648f…37024998` ✅ |
| `schema/question_flow.v1.schema.json` | `4b9f0938…bd4726` ✅ |
| `mobile_handoff/…/question_flow_types.dart` | `4576fb22…2fba53a` ✅ |
| `reports/question_baseline_freeze_v1.json` | `031f3f8f…6387b3` ✅ |
| `reports/qb002_evidence_v1.json` | `3a82e895…163b4f8a` ✅ |

The other 29 — the contract doc, handoff README, graph analysis, compatibility
report, path fixtures, and all 23 invalid fixtures plus their index — had their
authoritative hashes computed from the commit and recorded in
`test/question_flow/question_flow_contract.dart`.

**Note:** the generated types file is stored as `question_flow_types.dart.txt`.
Bytes and hash are unchanged; only the extension differs, so the analyzer does
not compile a reference artifact as project source.

---

## 4. Loader

Supports schema **major version 1**; a different major is refused rather than
best-effort parsed. Validates metadata, question and answer-option ids, question
types, answer value types, clinical roles, condition structure, next-question
references, canonical token references, red-flag metadata, review/publication
fields and path controls; rejects duplicates, missing references, unsupported
operators and fields.

Every failure is a typed `FlowLoadFailure`. **It never returns partial data, and
never treats a malformed condition as `false`** — a malformed condition would
otherwise hide behind a plausible-looking "not eligible".

Refuses outright: `max_followup_questions` ≠ 5 · a removed red-flag truncation
exemption · a missing impedance mismatch · a flow claiming Vocabulary 2.0
participates · an operator whose name suggests regex/fuzzy/scored matching · a
required question marked skippable · a skip sentinel that produces a token · a
publication or content-approval claim without a completed clinical review · a
red-flag question ordered behind an ordinary one · an unreachable or
self-contradictory trigger · a branch cycle.

**Enums were taken from the schema, not guessed** — an early revision invented
`option_ids`/`scale_value` and rejected the real candidate; the shipped set is
`option_id`, `option_id_set`, `boolean`, exactly as `$defs.question` declares.

`invalidates_on_change` accepts the documented `<all follow-up questions>`
sentinel. It is recorded and **never acted on**: acting on it is IM-003.

---

## 5. Condition semantics

All 13 operators implemented: `all`, `any`, `not`, `equals`, `one_of`,
`token_present`, `token_absent`, `prior_answer_equals`, `age_range`, `sex`,
`pregnancy`, `always`, `never`. Four readable fields: `sex`, `age_token`,
`body_area`, `assessment_phase`.

Two rules that look alike and are not:

- **Unknown operator or field → contract failure**, never `false`. The loader
  refuses such a flow, and the evaluator throws if one ever arrives.
- **Unknown demographic value → `false`.** Sex, age or pregnancy *not stated*
  makes a gated condition ineligible, so the question is not asked rather than
  wrongly asked. A **missing prior answer is never an affirmative match**.

`{"all": []}` is **true**; `{"any": []}` is **false** — stated by the contract
so two implementations cannot silently disagree, and asserted here.

No arbitrary code, no regex over clinical text, no free-text interpretation, no
fuzzy matching, no network.

### The candidate exercises only 6 of the 13

`all`, `any`, `always`, `sex`, `token_present`, `token_absent` appear in the
artifact. The other seven are implemented from the contract's prose and covered
by unit tests, but **are not verified against real candidate data**. Their
payload shapes (`equals`/`one_of` as `{field, value|values}`,
`prior_answer_equals` as `{question_id, answer_option_id}`, `age_range` as a
list) are the canonical forms; a future candidate using a different shape would
be refused rather than misread.

---

## 6. Deterministic ordering

`(priority, tie_break_key, question_id)`. String comparison is `compareTo` —
code-unit ordering, not locale-aware, so question order cannot depend on the
user's phone settings. The question id makes the comparison **total**: no two
questions compare equal, asserted across all 50×50 pairs.

Stable across reversed input, 50 randomized seeds, repeated runs, and offline.
Sorting never mutates the caller's list. Duplicate order keys fail validation.

---

## 7. Initial-only planning, and why IM-003 is absent

The planner takes **one** immutable `FlowEvaluationState` and returns **one**
plan. It has no method that accepts an answer, no reference to mutable state,
and no re-evaluation loop.

**That is IM-003 being absent by construction, not by discipline** — there is
nothing to call after an answer, so nothing can add, remove or invalidate a
question because of one. Proven by test: recording an answer in the isolated
state model leaves every plan byte-identical.

Truncation follows the contract: the limit applies to the **total** follow-up
count, and red-flag questions are never the ones dropped — if they alone reach
the limit, the limit yields. (An early revision counted only ordinary questions
against the limit; the authoritative `longest_reachable_path` fixture caught it.)

Demographic, symptom-picker and body-area nodes are represented (IM-006) but
never planned as follow-ups — the live app owns those screens.

---

## 8. Red-flag invariants

Modelled and tested, referencing existing metadata only — **no clinical rule is
duplicated**:

- every red-flag question is marked `evaluate_after_answer`, enforced at load;
- red-flag questions are ordered ahead of ordinary ones, enforced at load;
- a red-flag question is never truncated, even when the path overflows;
- the planner reads state and never writes it, so it cannot suppress an existing
  red-flag token;
- the plan carries questions, never tokens — scoring is outside and after this
  boundary, and is never invoked.

The merged QB-002 live correction is untouched and still unconditional (27/27).

---

## 9. ID-keyed state (IM-004, contract level only)

Answers keyed by stable question and answer-option id. Rejects unknown question
ids, options belonging to another question, and a second answer unless
replacement is requested. Serialization is deterministic regardless of insertion
order.

**Restoration is not implemented and this does not provide it.** The MVP
persists no in-flight assessment and has no answer editing. The model is
unconnected to `AssessmentController`, persistence, restoration, editing UI,
dynamic invalidation, telemetry, scoring and production state. The 3
authoritative `edit_cases` are vendored and recorded but **not executed as
behaviour**, because the behaviour does not exist.

---

## 10. Results

| Suite | Result |
|---|---|
| Contract, publication and isolation guards | 24/24 |
| Loader + all 23 invalid fixtures | 25/25 |
| 13 condition operators | 19/19 |
| Ordering, planner, red-flag, IM-003, state | 31/31 |
| 18 authoritative path fixtures | **18/18 exact** |
| IM-001 tie-path evidence | 4/4 |
| Performance and determinism | 3/3 |

**All 23 invalid fixtures are correctly rejected.** Six checks were missing on
the first pass — branch reference resolution, branch cycles, unreachable and
self-contradictory triggers, red-flag effect/hook agreement in both directions,
and red-flag ordering — and were added from the fixtures' own defects.

Clinical regression unchanged: **239 executed · 238 passed · 1 known finding ·
0 unexpected failures**, CB_211 pinned, **0 safety-critical under-triage**,
**124/124 red-flag cases emergency with empty ranked causes**.

Full suite **993 passed, 7 skipped, 0 failed**. `flutter analyze` clean,
`dart format` exit 0.

### Performance (engineering harness only)

| Metric | Measured |
|---|---|
| Artifact | 177,357 bytes · 50 questions · 300 options |
| Parse + validate (median of 10) | **1.5 ms** |
| Deterministic ordering | **29 µs** |
| Condition evaluation | **<1 µs** |
| Initial path planning | **30 µs** (p95 34 µs) |
| RSS, 5 flows held | **10.8 MB** |

**No user pays any of this.** The candidate is not an asset and the consumer is
never initialised by the application, so a normal build parses nothing and plans
nothing — asserted structurally, not inferred from these numbers.

---

## 11. Activation blockers

1. **IM-001 changes path content on 1,930 of 2,325 paths, 1,192 with different
   truncation.** Product and clinical review required — this is the blocker.
2. **Question content is unapproved** (`content_approved: false` throughout).
3. **No clinical review** of the candidate (`not_reviewed`).
4. **Candidate is unpublished** — no R2 object, no `/config` entry, no manifest.
5. **7 of 13 operators unverified against real data.**
6. **IM-003 deferred** — it can change scoring inputs.
7. **IM-004 restoration** needs a persistence model the MVP lacks.
8. **Path-limit value 5 is measured, not approved** (`fixed_at_5_pending_product_review`).
9. The bounded evidence covers token subsets up to size 3; larger subsets are a
   **coverage limit**, not a soundness gap.

---

## 12. Rollback

Nothing is live, so there is nothing to roll back operationally. The consumer is
unreachable from the application, the candidate is a test fixture, and no
manifest or artifact changed. A revert is a single-commit revert; no user-visible
behaviour changes either way.
