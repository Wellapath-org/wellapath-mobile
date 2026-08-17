# Question Flow 1.1 — Grouping in the Isolated Consumer

The isolated engineering consumer now speaks contract **1.1**. It reproduces the
knowledge base's parity evidence independently, and in two places produces
stronger evidence than the knowledge base could.

> ### Unpublished, clinically unreviewed, inactive
> Candidate 1.1 is not an asset. Not in `pubspec.yaml`. Not imported by any
> screen, `AssessmentController` or `QuestionEngine`. The live application
> continues to use its compiled Dart question flow, unchanged.
>
> **IM-003 dynamic re-branching is not implemented.**
> **IM-001 is not activation-ready** — 135 Product wording decisions are open.

**Contract:** `wellapath-knowledge-base` @
`cffbe8a673c7a5be5dfb882cea77c1705c7515c3` (PR #29, reviewed head `2defee9f`).

---

## 1. What 1.1 changes

The live `QuestionEngine` **de-duplicates**: it asks one severity question, one
duration question and one additional-symptoms question however many symptoms
were selected. Candidate 1.0 modelled one question per token per role, so it
planned a different question **set** on 1,930 of 2,325 paths — the blocker
recorded at the end of Step 3.

Candidate 1.1 models the grouping. This consumer implements it, and matches
real captured Dart output on **2,325 of 2,325 paths**.

---

## 2. Captured-Dart parity, reproduced here

Computed by `test/question_flow_v1_1/grouping_parity_test.dart` against
`live_question_oracle_v1.json` — the actual output of
`QuestionEngine.generateQuestions` at Mobile `657739cc`. Nothing is normalised
or rewritten to obtain a pass.

| Dimension | Result over 2,325 paths |
|---|---|
| Identical | **2,325 / 2,325** |
| Question-set differences | **0** |
| Question-order differences | **0** |
| Wording differences | **0** |
| Option-set / option-order differences | **0 / 0** |
| Token-effect differences | **0** |
| Red-flag-effect differences | **0** |
| Truncation differences | **0** |
| Red-flag questions dropped | **0** |
| Path-limit violations | **0** |

Comparison keys are declared in the test, not chosen to flatter it. Severity and
duration options are **not** compared: the live `FollowupQuestion` carries an
empty option list for them, so there is nothing to compare and no match is
claimed.

---

## 3. Reversed order, and a figure that needed decomposing

The knowledge base publishes **1,680 / 2,300** live instability. This consumer
measured **1,887** at first. Neither number was wrong — they measure different
things, and the discrepancy is worth recording rather than reconciling away:

| Metric | Paths |
|---|---|
| live **wording** sequence differs (**the KB's published figure**) | **1,680** |
| live **option list** differs | 1,872 |
| wording **or** options differ | 1,887 |
| wording identical, option **order** differs | 207 |
| live **role** sequence differs | **0** |
| **candidate** differs from itself | **0 / 2,300** |

The live engine appends additional-symptom options in tap order, so a path can
show identical wording with a different option order. Reporting only the wording
figure understates how order-dependent the baseline is. The test asserts the
specified 1,680 **and** discloses the broader measurements; the extra
instability makes the case for the correction stronger, not weaker.

**Which questions get asked never depends on order** — only how they are worded
and how their options are arranged.

On reversed paths the candidate changes: question set **0**, option set **0**,
token effects **0**, red-flag effects **0**, truncation set **0**.

---

## 4. GF-006 and GF-008, re-measured against the live engine

Both are pinned against `QuestionEngine` itself, not against a recalled number.

**GF-006 — default duration.** Six authoritative cases. Candidate 1.1 matches
live on all six; candidate 1.0 differs on exactly three — the empty selection,
and the two mapped-but-duration-less tokens combined with an unmapped one.
Neither `chest_indrawing_severe` nor `fast_breathing_child` appears as a
duration source, so no missing mapping is invented.

**GF-008 — clarifier order.** Of **248** captured paths presenting two or more
clarifiers, candidate 1.0's ordering differs from live on **168**; candidate 1.1
on **0**. `kRedFlagClarifiers` is ordered `breathlessness_at_rest,
inability_to_drink, abnormal_bleeding` — not alphabetical. Clarifier priorities
encode emission order and **not** clinical precedence: every clarifier remains
individually undroppable and individually evaluated.

---

## 5. Supplemental coverage — stronger here than in the knowledge base

The knowledge base could not run Dart, so its size 4–5 evidence is
**model-derived**: a Python transcription, validated against all 4,625 captured
cases first. Its own report says so.

This consumer calls the **real `QuestionEngine`** for the same 53,130 paths, so
Mobile's result is **captured Dart output**:

| Size | Paths | Set | Option | Red-flag | Truncation | Candidate stable |
|---|---|---|---|---|---|---|
| 4 | 10,626 | 0 | 0 | 0 | 0 | yes |
| 5 | 42,504 | 0 | 0 | 0 | 0 | yes |

**The shipped artifact is still backed by the weaker evidence**, so the
knowledge base's limitation is restated in the test rather than dropped now that
a stronger run exists. **Sizes above 5 remain uncovered at both ends.**

Of the 16 authoritative path fixtures, 11 carry real live output and are
asserted against it *and* against the engine directly; the 5 marked
`not_captured` are model-derived and are labelled, never cited as live.

---

## 6. Loader and grouping semantics

### The version gate was a real hazard

The 1.0 loader accepted any schema **major** 1. A 1.1 artifact would therefore
have parsed without error — the grouping block being merely an unknown field —
and then been planned as if every question stood alone, presenting the **full**
option union instead of the triggered union and offering the user symptoms no
selected token contributed.

The gate is now an exact set: `{1.0, 1.1}`. `1.2`, `1.10`, `2.0`, `1` and `''`
are all refused.

### Enforced by artifact version, not by appearance

- a **1.0** artifact declaring `grouping_semantics` → refused;
- a **1.0** question carrying a grouping block → refused;
- a **1.1** artifact without `grouping_semantics` → refused;
- `grouping_phase` other than `before_truncation` → refused;
- `red_flag_clarifier` missing from `non_groupable_roles` → refused.

1.0 is never implicitly grouped, whatever its questions look like.

### Three gaps the invalid fixtures found in this loader

The first run rejected 19 of 22. All three misses were real:

1. **Unknown grouping fields were ignored.** An unknown field is a merge
   directive this consumer does not implement; ignoring it is exactly the
   failure this contract exists to prevent. Grouping blocks and sources now
   have closed field sets.
2. **`tie_break_key` collisions were unchecked.** Two ungrouped questions
   sharing one is an unresolved order tie, never an implied merge. Scoped to
   1.1 — candidate 1.0 legitimately reuses the key across roles separated by
   priority, and an earlier revision applied it to every version and stopped 1.0
   loading, which is a compatibility break rather than a safety gain.
3. **No source-trigger containment.** A source that fires where its question
   cannot would need a question that is never presented.

Containment is decided **exactly**. A structural fast path handles the shape the
contract uses (`any([token_present …])` containing `token_present t`); anything
else falls back to enumerating the referenced token subsets, and above 20 tokens
the answer is **UNDECIDED** and the artifact is refused rather than assumed fine.
The fast path is not just an optimisation — the enumeration cost 87 ms of load
time against 1.5 ms for all of candidate 1.0. It is now **2.4 ms**.

**All 22 invalid fixtures are rejected**, each for a reason about its own
declared defect — matched on the defect's subject rather than a fixture-id table
copied from the knowledge base, so the two are not merely agreeing with each
other.

---

## 7. The grouped planner

Eleven steps, in the order the contract fixes:

```
1  triggered sources        →  5  union triggered sources only
2  preserve non-groupable   →  6  de-duplicate by option id
3  group only groupable     →  7  deterministic option order
4  representative =            8  retain source provenance
   lowest_source_order_index   9  combine grouped + ungrouped
                              10 deterministic question order
                              11 limit 5, red flags never dropped
```

Grouping runs **before** truncation. Counting un-merged questions against the
limit is what made candidate 1.0 drop questions the live engine asks.

`planGroupedInitialPath` takes a token **Set**. That is not a style preference:
the defect being corrected is a dependence on selection order, and a `List`
would leave the door open to reintroducing it.

Two invariants are asserted on **every** plan, not only at load — a group never
presents two questions, and a groupable role never presents two questions. A
breach throws `GroupedPlanViolation` rather than returning a degraded plan,
because a silently degraded plan is how a danger-sign question goes missing.

---

## 8. Runtime isolation

Asserted structurally, not promised:

- no live assessment or engine source imports the consumer;
- `QuestionEngine` and `AssessmentController` do not import it;
- nothing outside `lib/core/question_flow/` imports it;
- `main.dart` and `app.dart` do not initialise it;
- no `fromEnvironment` exists, so no build flag can enable it;
- it imports no `dart:io`, Dio, HTTP, Hive, telemetry, scoring, evaluator or
  controller, and constructs no widget;
- `pubspec.yaml` declares no question-flow asset; nothing under `assets/` is one;
- every 1.1 fixture lives under `test/`.

### Binary exclusion, with working controls

**Android** `app-release.apk` (64.6 MB) — no `question_flow`, `oracle` or
`invalid_grouping` entry. `libapp.so`:

| Symbol | |
|---|---|
| `planGroupedInitialPath`, `QuestionGrouping`, `GroupedPathPlan`, `PresentedQuestion`, `QuestionGroupSource` | **ABSENT** |
| `lowest_source_order_index`, `union_of_triggered_sources`, `grouping_semantics` | **ABSENT** |
| `loadQuestionFlowFromBytes`, `FlowLoadFailure` | **ABSENT** |
| *controls:* `generateQuestions`, `FollowupQuestion`, `RedFlagClarifier`, `AssessmentController` | **PRESENT** |

**iOS** `Runner.app` (26.8 MB, `--no-codesign`) — same result in
`App.framework/App`, same controls present.

The controls matter: without them, "absent" would only prove the search was
broken.

The 4 MB oracle is the largest file this branch adds. Bundling it would cost
every install 4 MB for evidence no user needs; it is a test fixture only.

---

## 9. IM-003 remains absent by construction

The grouped planner takes one immutable state and returns one plan. It exposes
no `replan`, `onAnswer`, `recordAnswer`, `afterAnswer`, `reevaluate` or
`invalidateDependents`. `invalidates_on_change` is loaded and reported and
**never referenced by the planner**. No question in the candidate declares a
branch condition, so there is nothing to re-branch on even in principle.

Restoration, editing and skips remain unimplemented. Optional skips remain zero.

---

## 10. Clinical behaviour unchanged

| | |
|---|---|
| Case bank | **239 executed · 238 passed · 1 known finding · 0 unexpected failures** |
| Cases skipped | **0** |
| Pass rate | 99.58% · engine errors 0 |
| Red-flag cases | **124/124 emergency with no ranked cause** |
| Global red-flag rules exercised | 13/13 |
| CB_211 | pinned, unresolved |
| QB-002 | unconditional, 27/27 |
| Path limit | 5 |

The live `QuestionEngine` is untouched. No question wording, answer meaning,
token effect, red-flag rule, scoring, urgency or ranking changed. Vocabulary 2.0
remains inactive and no alias or metadata participates in question eligibility.

---

## 11. Performance (engineering harness only)

| Metric | Measured |
|---|---|
| Candidate 1.1 | 155,532 B · 13 questions · 179 options · 3 groups · 40 sources |
| Parse + full validation (median of 10) | **2.4 ms** |
| Grouped plan, 5 tokens (median of 200) | **34 µs** |
| Option union, 18 sources → 15 options | **45 µs** |
| 2,325-path oracle comparison | **48 ms** (21 µs per plan) |
| RSS, 5 flows held | +10.7 MB |

**No user pays any of this** — asserted structurally in §8, not inferred from
these numbers.

---

## 12. Remaining activation blockers

1. **IM-001 — 135 Product wording decisions, all `PENDING`.** Path content no
   longer changes, but which of two existing wordings is shown can differ from a
   given tap order. Every wording involved already exists in the live app.
2. Question content unapproved (`content_approved: false` throughout).
3. No clinical review of the candidate (`not_reviewed`).
4. Unpublished — no R2 object, no `/config` entry, no manifest.
5. 7 of 13 condition operators unverified against real candidate data.
6. IM-003 deferred.
7. Path-limit value 5 is measured, not approved.
8. Subset sizes above 5 uncovered.

---

## 13. Rollback

Nothing is live, so there is nothing to roll back operationally. The consumer is
unreachable from the application, both candidates are test fixtures, and no
manifest or asset changed. A revert is a single-commit revert; no user-visible
behaviour changes either way. Candidate 1.0 remains byte-identical
(`c403648f…37024998`) and still loads, so reverting the 1.1 work leaves a
working 1.0 consumer behind.
