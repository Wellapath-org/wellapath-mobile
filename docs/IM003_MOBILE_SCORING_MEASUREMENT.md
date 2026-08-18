# IM-003 — Scoring Impact Measured with the Shipped Mobile Engine

The knowledge-base analysis established exactly which tokens additive
re-branching makes reachable and what weight they contribute. It could not
compute the resulting score, ranking or urgency, because that needs Mobile's
engine. This measures it.

> ### IM-003 is not implemented and no decision is approved
> Nothing here is wired to the application. The live flow still plans its
> question list once, in `initState`, and no answer changes eligibility.
> **D004 remains `pending`.**

**Baseline:** Mobile develop `d820d6cfc3b96cbbba9d434ef4684b9a36140991` ·
Knowledge Base `5a8563bf8702bd506a7b67ccc6c9a8faef8ef574`.

---

## 1. The headline finding

**On one measured path, additive re-branching moved urgency from `emergency`
down to `urgent`.**

`S10_path_limit_pressure`, seeds `bleeding, difficulty_breathing, fever,
headache, poor_feeding`:

| | Baseline | Expanded |
|---|---|---|
| Top condition | `lassa_fever` (score **26**) | `malaria` (score **52**) |
| Runner-up | `malaria` (25) | `acute_diarrhoea` (30) |
| Urgency | **emergency** | **urgent** |
| Urgency source | `urgency_default` | `urgency_default` |
| Red flag | none | none |

`lassa_fever` leads by a single point and its `urgency_default` is `emergency`.
The closure adds 10 tokens, `malaria` climbs to 52, and the urgency that the
user is shown comes from `malaria`'s default instead — **a de-escalation, with
no red flag involved on either side.**

This is recorded as **`IM003-SB-001`, a potential safety blocker, open for
clinical review**. This report does not judge whether it is acceptable.

### Why the knowledge base could not have found this

The KB analysis correctly established that **no** newly reachable token touches
any red-flag pathway, and this measurement reproduces that: **0 red-flag
changes** across all 63 scenarios. That conclusion is sound.

It does not follow that urgency is stable. Urgency also comes from the
`urgency_default` of whichever condition ranks **first**, so adding scoring
tokens can lift a lower-urgency condition above a higher-urgency one without any
red flag moving. The knowledge base said so explicitly — *"Do not treat
unchanged red-flag membership as proof that urgency cannot change; measure
urgency through the shipped engine"* — and this is the case that warning was
protecting against.

---

## 2. Method

Every clinical value comes from the **shipped** `EngineController` —
`RedFlagEvaluator` → `ScoringEngine` → `UrgencyDeterminer` → `OutputFormatter` —
over the pinned KB 2.4, rules 2.2 and token dictionary 1.1.

**No scoring logic exists in this harness.** No condition weight is copied, no
urgency inferred, no ranking recomputed. The knowledge base's Python
approximation disagreed with this engine on **22 of 239** urgencies, which is
precisely why the measurement moved here; a second approximation in Mobile would
have repeated the mistake.

`OutputFormatter` truncates `topCauses` to three, which is right for the app and
wrong for a ranking measurement, so the full scored-condition list comes from the
same shipped `ScoringEngine` instance. The controller remains the authority for
urgency, source and red-flag result, and **the two are cross-checked on every
run** — a disagreement throws rather than being reported.

An engine exception propagates. A measurement that swallowed one would report a
difference of zero.

---

## 3. Scope

**63 scenarios**, provenance kept distinct:

| Class | Count |
|---|---|
| Authoritative — supplied by the KB decision package for D004 | **12** |
| Graph-boundary — derived mechanically from the authoritative graph | **51** |

The derived cases are each of the 15 newly reachable tokens alone, all 15
two-cycles, every graph node, the max-closure and max-depth seeds, a no-op
closure, a duplicate-seed idempotence case, and the `pain → minor_injury` case by
name. **No clinical answer sequence was invented** — every seed is a token or
token pair the authoritative graph already contains.

---

## 4. Reproduced counts

Recomputed here from the vendored pair table, not read back:

| | Declared | Reproduced |
|---|---|---|
| Trigger nodes | 18 | **18** |
| Trigger edges | 56 | **56** |
| Two-cycles · self-loops | 15 · 0 | **15 · 0** |
| Newly reachable tokens | 15 | **15** |
| Affected conditions | 31 | **31** |
| Max closure · max depth | 14 · 5 | **14 · 5** |
| Monotonicity violations | 0 | **0** |
| Red-flag-affecting tokens | 0 | **0** |

**`pain` is present**, and `pain → minor_injury` carries weight **6**. A
second-hop-only computation drops it — that was the defect in the first version
of the KB analysis, and a guard now fails if the closure regresses to 14 tokens
or 30 conditions.

---

## 5. Measured outcomes

Primary class is the most significant that applies, so an urgency change is
never filed as a ranking change. The classes reconcile to 63.

| Outcome | Scenarios |
|---|---|
| Red-flag changes | **0** |
| **Urgency changes** | **25** |
| Urgency-source changes | **0** |
| Top-condition changes *(primary class)* | **6** |
| Ranking changes without top-condition change | **29** |
| Score-only changes | **0** |
| No effect | **3** |
| **Total** | **63** |

### Urgency direction — the distinction that matters

| | |
|---|---|
| Escalations | **24** |
| **De-escalations** | **1** |

"25 urgency changes" would have hidden that one of them went *down*. Direction is
counted separately and the de-escalating scenario is listed in full.

### Top condition

31 scenarios changed top condition in total (6 as their primary class; the rest
also changed urgency, which outranks it). **In every single one the expanded top
condition is `malaria`** — it accumulates the largest share of the newly
reachable tokens.

---

## 6. Determinism and convergence

Closure is **idempotent** (re-closing adds nothing), **order-independent**
(reversed seeds give the same closure), **monotone** (0 violations over every
ordered node pair) and converges within the declared depth of 5 on every
scenario. Repeated execution over 5 rounds gives byte-identical urgency, ranking
and score deltas.

---

## 7. Uncovered state space

Stated, not implied:

- Demographic and seasonal inputs are not varied — escalation via those paths is
  exercised only where the token set alone reaches it.
- **Answer sequences are not modelled.** The closure is the fixed point, not a
  per-answer trajectory; intermediate states are unmeasured.
- Removal, invalidation, answer-edit and restoration re-branching are out of
  scope.
- The 239-case bank carries no answer sequence and **cannot** exercise IM-003. It
  is not used here as adaptive-branching evidence.
- Seeds are single tokens, declared graph pairs and the authoritative scenarios.
  Arbitrary larger user selections are not enumerated.

---

## 8. Guards

**49 tests.** The build fails if a source hash or byte count drifts, the KB
binding commit changes, any declared count moves, `pain` disappears, the closure
regresses to 14 tokens or 30 conditions, an edge is dropped or added, closure
stops being monotone or idempotent, convergence exceeds the bound, a decision
becomes approved, the report omits a change flag, the outcome classes stop
reconciling, **a de-escalation is dropped from the report**, or the report claims
any approval.

**Eight mutation tests** prove the guards reject the corruptions they exist to
catch, rather than merely never having fired.

Two self-referential guard bugs were caught during construction: a scan matched
its own search string, and the fix for it matched one level deeper. Both are
fixed by exact-path exclusion with the reason recorded.

---

## 9. Runtime isolation

The harness imports the shipped engine deliberately — that is the point — but
the arrow goes one way only.

- nothing under `lib/` imports it;
- the engine, UI, controller, `main.dart` and `app.dart` never reference it;
- no build flag; no new dependency; no pubspec or asset change;
- the harness writes exactly one file, its own report;
- `followup_screen.dart` still calls `generateQuestions` **once**, asserted — a
  second call would mean IM-003 had been implemented in the live flow;
- no live source contains a re-branching entry point.

**Binary exclusion, both platforms, with positive controls:**

| | Android `libapp.so` | iOS `App.framework/App` |
|---|---|---|
| 11 harness symbols | **ABSENT** | **ABSENT** |
| bundle IM-003 entries | **0** | **0** |
| controls (`ScoringEngine`, `RedFlagEvaluator`, `EngineController`) | **PRESENT** | **PRESENT** |

---

## 10. Clinical baseline unchanged

**239 executed · 238 passed · 1 known finding · 0 unexpected failures · 0
skips** · 13/13 global red-flag rules · CB_211 pinned, not counted as passed ·
**QB-002 27/27**. No runtime artifact was modified, so nothing about the baseline
could have moved.

Full suite **1,199 passed, 7 skipped, 0 failed** · `flutter analyze` clean ·
`dart format` clean · Android and iOS release builds pass.

---

## 11. What this informs, and what it does not

This report states **what changed**. It does not characterise any difference as
safe, acceptable, clinically correct or activation-ready.

It informs **`IM003-D004-SCORING-REACHABILITY`**, which stays `pending` until the
knowledge base and the Product/clinical reviewers assess it — now with the
de-escalation finding in front of them.

It authorizes nothing: not implementing IM-003, not approving any decision, not
clinical or product sign-off, not beta or production activation, not publishing
either candidate, and no change to the live `QuestionEngine`, `ScoringEngine`,
`RedFlagEvaluator` or urgency logic.
