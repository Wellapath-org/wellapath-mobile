# CB_211 — release disposition

Reviewed for this release candidate rather than carried silently, as required
by Release Step 2 §7. Nothing about the clinical logic was changed; this is a
disposition record.

## What CB_211 is

| | |
|---|---|
| Case | `CB_211` — "Edge: empty input" |
| Input | `symptom_tokens: []`, `demographic_tokens: []`, `season: null` |
| **Expected** | urgency `non_urgent` · urgency_source `empty_default` · top_condition `null` |
| **Observed** | urgency **`urgent`** · urgency_source **`urgency_default`** · top_condition **`malaria`** · red_flag_triggered `false` |
| Classification | `obsolete_stale_case_bank_expectation` |
| Direction | **over-triage** (expected non-urgent, observed urgent) |

With no symptoms at all, the engine still ranks a condition and returns that
condition's default urgency. The expectation the case bank encodes
(`empty_default`) was hardcoded in `testing/build_case_bank.py:174-177` and
names an `urgency_source` value that **does not exist** in the shipped
`urgencySource` contract, which has four values and no `empty_default`. The
expectation describes an engine that was never built.

Verified independently for this candidate: the observed output is unchanged,
and the case-bank fixture still hashes to
`c7bdc434a33d341e21e015f0defe567274d7f6271c332352b19ba21e7d998834`, which is
the exact fixture the disposition is bound to. A swapped fixture cannot inherit
this adjudication — the harness recomputes the hash and refuses the registry on
a mismatch.

## Existing decision / waiver reference

| | |
|---|---|
| Disposition | **Option D** — registry until adjudicated |
| Adopted at | Knowledge Base merge `550e8f17` |
| Authority | **engineering lead** |
| Registry | `test/fixtures/known_findings.json` |
| Contract | `docs/KNOWN_FINDINGS_CONTRACT.md` (knowledge-base repo) sha256 `81455b4f…163e2` |
| Decision package | sha256 `fdda2501…f9701` (knowledge-base repo) |
| Status | `open_option_d_adopted_awaiting_clinical_product_adjudication` |
| Tracking issue | wellapath-mobile **#35 — OPEN** |

**This is an engineering disposition, not a waiver of the finding.** The
registry states so in its own fields:

```
classification_is_clinical_approval : false
is_external_beta_approval           : false
is_production_approval              : false
```

Option D authorises *carrying* CB_211 as a pinned, fail-closed, unresolved
discrepancy. It does not resolve it. The choice between **Option B** (correct
the expectation in a new versioned bank) and **Option C** (an engine-level
empty-input result) is deferred to clinical/product and, by the registry's own
`review_trigger`, **must be made before external beta**.

## Does it affect the frozen release path?

**No — it is not reachable through the product.** Both guards were re-verified
against the code in this candidate, not taken from the registry:

| Layer | Where | Mechanism |
|---|---|---|
| Symptom selection | `symptom_selection_screen.dart:83` | `final isEnabled = tokens.isNotEmpty;` gates `onPressed` at line 250 — Continue is disabled with no symptom selected |
| Pre-engine | `loading_screen.dart:71` | `if (widget.assessmentController.symptomTokens.isEmpty)` blocks before any engine work, records `CompletionStatus.interrupted`, shows "Please select at least one symptom to continue." |

Guard coverage: `test/assessment/empty_input_guard_test.dart`.
Engine behaviour pinned by: `test/engine/engine_wiring_test.dart:218-229`.

A user cannot construct the empty-input state through the UI. The finding is
reachable only by invoking `EngineController.run()` directly, which no shipped
code path does.

## Severity and user reachability

| | |
|---|---|
| Safety critical | **No** |
| Triage direction | **Over-triage** — errs toward more care, not less |
| Can suppress or bypass a red flag | **No** — with an empty token set no red-flag rule can match, so there is no flag to suppress |
| Can change a non-empty assessment result | **No** — the behaviour follows from the empty input alone |
| Affects other cases | **No** |
| Reachable via normal UI | **No** (two guards above) |
| Reachable via direct engine invocation | Yes — not a shipped path |

## Why "known" rather than "unexpected"

A known finding here is a **pinned observation, not a suppressed failure**. The
distinction is enforced mechanically, and the run output states it:

```
239 executed · 238 passed · 1 known finding · 0 unexpected failures
*** KNOWN FINDINGS — REGISTERED, UNRESOLVED, NOT COUNTED AS PASSED ***
  CB_211  obsolete_stale_case_bank_expectation
    counted as passed: NO
```

CB_211 executes on every regression run, its exact observed output is asserted
field by field, and it is **never counted as passed**. If its behaviour changes
in any field — better or worse — the run fails, because the registry's
description of reality would have become wrong. Any *additional* case mismatch
also fails the run. That is what separates it from an unexpected failure: an
unexpected failure is undescribed and ungoverned; this one is described,
bounded, owned and expiring.

## Disposition for this release

| Milestone | Disposition |
|---|---|
| **Internal distribution** | **Not blocking.** An authoritative engineering-lead disposition exists and covers exactly this: carrying the finding, pinned and fail-closed. The defect is unreachable through the UI, over-triage in direction, and cannot suppress a red flag. |
| **External beta** | **BLOCKING.** `review_trigger.must_be_resolved_before: external beta`. |
| **Store submission / production** | **BLOCKING.** No clinical or product adjudication exists, and issue #35 is open. |

Recorded as **`RC-BLK-016`** — `BLOCKS_STORE_SUBMISSION`, carried openly rather
than silently.

**No clinical logic was changed to reach this disposition, and none may be
changed without clinical authorization.** Options B and C both remain open and
both belong to the clinical reviewer, not to engineering.

## Re-review triggers

The disposition lapses and must be re-adjudicated if any of these occur:

- the case-bank fixture hash changes;
- CB_211's observed output changes in any field;
- `UrgencyDeterminer` gains or removes an `urgencySource` value;
- either product guard is removed, weakened, or bypassed by a new entry point;
- a new caller invokes `EngineController.run()` without an empty-input check.

`test/release/cb211_disposition_test.dart` fails the build if the guards
disappear, if the finding is marked resolved without clinical approval, or if
the registry starts claiming an authority it does not have.
