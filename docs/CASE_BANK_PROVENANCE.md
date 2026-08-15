# Case Bank Provenance and Drift Guard

The Top-50 clinical case bank is authored in the Knowledge Base repository and
vendored into Mobile byte-for-byte. This document records where it came from,
what enforces that it stays identical, and what the current 239-case execution
produced.

> **Not a clinical certification.** The case bank is engineering-approved and
> specification-derived. It carries **no recorded clinical approval**. A passing
> run demonstrates that the engine still behaves as the specification says it
> should — it is not sign-off by a clinical reviewer, and must not be described
> as one.

---

## Authoritative source

| Field | Value |
|---|---|
| Repository | `Wellapath-org/wellapath-knowledge-base` |
| Commit | `dceecde2ee7545664bf45ea5edfa137a52acdebd` |
| Source path | `testing/case_bank_v1.json` |
| Destination path | `test/fixtures/case_bank_v1.json` |
| Artifact version | `1.0` |
| Byte count | 138,988 |
| SHA256 | `c7bdc434a33d341e21e015f0defe567274d7f6271c332352b19ba21e7d998834` |
| Git blob SHA | `3b94de68ba04efa8967382a4bba20fd67dc01e41` |
| Declared case count | 239 |
| Actual case count | 239 |
| Case ID range | `CB_001` … `CB_239`, no gaps, no duplicates |

The vendored file's git blob SHA is identical to the blob at that commit in the
Knowledge Base repository, which is a stronger identity check than the content
hash alone: it proves the bytes were copied, not re-serialised into something
that merely hashes the same way.

### Known-findings registry

The registry that carries the Option D disposition is vendored the same way and
bound cryptographically to the case bank above.

| Field | Value |
|---|---|
| Repository | `Wellapath-org/wellapath-knowledge-base` |
| Merge commit | `550e8f179021139a4c9084ba19d1f80111edbfba` |
| Source path | `testing/known_findings.json` |
| Destination path | `test/fixtures/known_findings.json` |
| Version / schema version | `1.0` / `1.0` |
| Byte count | 9,730 |
| SHA256 | `fadaea063303ecd27a90c233dba7782f8840c85aef4e3a7cca61b1e4793537ed` |
| Git blob SHA | `3d835d40d06acf402f901557231269ccd3b4a42f` |
| Engineering disposition | `option_d_adopted` |
| Bound to case bank | `c7bdc434…d998834` — the exact fixture above |
| Registered findings | 1 (`CB_211`) |
| Contract | `docs/KNOWN_FINDINGS_CONTRACT.md` — sha256 `81455b4f5995d9ea403dcc174d54329a097a35b4af09332e61f50d53564163e2` |
| CB_211 decision package | sha256 `fdda2501bbffd4979972ec3d3a0431639eea876a65e8528512e10dde699f9701` |

The binding is computed, not restated: the harness hashes the case-bank bytes it
actually loaded and refuses the registry unless
`authoritative_fixture.sha256` matches. A swapped fixture therefore cannot
inherit an adjudication made against a different one.

**This registry carries engineering authority only.** It cannot record clinical,
external-beta or production approval, and the consumer rejects any entry that
claims to.

### Supported artifact combination

| Artifact | Version | SHA256 |
|---|---|---|
| Knowledge base | `kb.ng.v2.4` | `6c00d8257f8417e86bd5e237630bf8a4623ad72e2e46b1b071dd447c067cec2b` |
| Rules | `rules.ng.v2.2` | `1d27e854cba95b179577a88f92445400f494a7fe8e6a53a60fcaa98b3870d1c4` |
| Token dictionary | `token_dictionary.ng.v1.1` | `0cc47ad9537c0bd4c6ef3aec8f1931eb9b4c62103a8809d16544f94a90b5c019` |

Pinned under `test/fixtures/artifacts/` and hash-verified at load by
`test/engine/case_bank/artifact_fixtures.dart`. These were already vendored and
already at the required versions; this work did not add, change or refresh any
of them.

The bank's own `_metadata.built_from` names `rules.ng.v2.1`, with
`valid_against_rules` recording that it is valid against both v2.1 and v2.2 —
v2.2 removes `rf_147` (RTI `circulatory_collapse`), which is behaviourally inert
because `circulatory_collapse` still returns emergency via global `rf_006`.
CB_159 already encodes that (`source: global_red_flag`), and it passes.

---

## What enforces this

`test/engine/case_bank_provenance_test.dart` — 10 tests, no network access, and
**it never skips**. A missing fixture fails CI rather than quietly passing,
because a silently skipped clinical regression is indistinguishable from a
passing one. It fails on:

- fixture absent;
- byte count ≠ 138,988;
- SHA256 ≠ the value above;
- declared version ≠ `1.0`;
- declared or actual case count ≠ 239;
- duplicate case IDs, or any gap in `CB_001`…`CB_239`;
- the set of ungraded `observe` cases changing;
- a case missing or mistyping a field the harness grades on.

Both failure states were proven, not assumed: with the fixture removed the guard
fails, and with a single case renumbered (`CB_239` → `CB_240`) both the SHA256
check and the ID-range check fail. The fixture was restored to the authoritative
hash afterwards.

`test/engine/case_bank_determinism_test.dart` — 4 tests proving the run is
reproducible: two independently constructed engines produce field-identical
reports over all 239 cases, a case re-run on a warm engine (after the other 238)
returns exactly what it returned alone, and ranked-condition order is stable
across runs.

**Refreshing the hash on its own turns a real drift signal into a rubber stamp.**
If the Knowledge Base publishes a new bank, update every constant *and* re-run
the full 239-case regression.

---

## Execution results — 239 cases, KB 2.4 / rules 2.2 / token dict 1.1

Run through `EngineWiring.asShipped`, the production path via
`buildEngineInput()` — the same function `loading_screen.dart` calls.

**Authoritative result:**

> **239 executed · 238 passed · 1 known finding · 0 unexpected failures**

The known finding is **not** included in the 238. It is never counted as passed.

| Metric | Value |
|---|---|
| Total cases executed | 239 |
| **Passed** | **238** |
| **Known findings (registered, unresolved)** | **1** — CB_211 |
| **Unexpected failures** | **0** |
| **Under-triage** | **0** |
| Engine errors | 0 |
| **Safety-critical failures** | **0** |
| Safety-critical cases exercised | 150 |
| Global red flag rules exercised | 13/13 |
| Skipped for any reason | 0 |

CB_225, CB_232 and CB_233 count toward the 238: each passes the assertions its
case-bank record actually encodes (an `observe` case asserts only that it runs
cleanly). They remain separately reported below for human review.

The underlying engine-level view is unchanged from the first run — 236 graded,
235 graded-passes, 3 observe, 1 graded failure, 1 over-triage — and is still
written in full to the results file. The classification above is a partition of
the same run, not a re-scoring of it.

Full per-case output is written to
`build/e8_case_bank/case_bank_results_v1.json` on every run. `build/` is
gitignored, so it is regenerated rather than committed here; the Knowledge Base
repository is where the results file is retained
(`testing/case_bank_results_v1.json`).

### Red flag precedence

124 cases triggered a red flag. All 124 returned `emergency`, and all 124
returned empty `topCauses` — scoring is skipped entirely on the red flag path,
which is LOCKED PRINCIPLE #5 behaving as specified. No case expecting a red flag
failed to trigger one.

### Priority-4c (Case-04 Option B)

CB_229 and CB_230 both return `urgent` via `demographic_escalation`, not
`emergency`. Option B holds; there is no discrepancy to report.

### Comparison against the previous run

The previous recorded execution was 234 cases against KB 2.3 / rules 2.1, at a
51.52% graded pass rate. The jump to 99.58% is **not** an engine change — it is
the case bank adopting Option A from that run's open ruling: 111 of that run's
112 failures were red-flag cases where the bank asserted an
`expected_top_condition` the engine does not produce by design. This bank sets
`expected_top_condition: null` on all 128 red-flag cases, which is what the
engine has always done.

The one remaining failure, CB_211, is the same single failure the 234-case run
recorded. Nothing regressed between KB 2.3 and KB 2.4.

---

## Known finding — CB_211 (Option D adopted, unresolved)

**Option D was adopted at Knowledge Base merge `550e8f17`.** CB_211 is preserved
byte-for-byte and registered as an explicit, unresolved, fail-closed known
discrepancy. This is an **engineering disposition, not clinical approval.**

| | |
|---|---|
| Case | `CB_211` — "Edge: empty input — engine must not crash, returns safe default" |
| Input | `symptom_tokens: []`, `demographic_tokens: []`, `season: null` |
| Case-bank expectation (unchanged) | `non_urgent`, source `empty_default`, top condition `null` |
| Pinned observed output | `urgent`, source `urgency_default`, top condition `malaria`, `red_flag_triggered: false` |
| Direction | **Over-triage**, not under-triage |
| Safety critical | No |
| Classification | `obsolete_stale_case_bank_expectation` |
| Decision status | `open_option_d_adopted_awaiting_clinical_product_adjudication` |
| Must be resolved by | **external beta** |
| Tracked as | Issue #35 |

### What the registry does and does not do

- CB_211 **executes on every run** — it is never skipped, filtered, or
  pre-classified.
- Its actual output is computed normally first, then compared against **both**
  the unchanged case-bank expectation and the pinned observation.
- It is **never counted as passed** and is never folded into the pass total.
- **Any deviation from the pin fails the run — in either direction.** An
  apparent improvement to `non_urgent`/`empty_default` is *not* an automatic
  pass: it means the registry's description of reality has become wrong and the
  entry must be reviewed.
- Any *unregistered* mismatch fails. The registry cannot absorb a new finding.
- The registry entry **expires at external beta**; a build at that milestone
  fails until the deferred decision is made.

**Options B and C remain deferred** for clinical/product adjudication before
external beta:

- **Option B** — correct the expectation in a new versioned case bank.
- **Option C** — engine-level empty-input result (issue #35).

### Safety characterisation

- **Over-triage, not under-triage** — the engine reports a higher urgency than
  the bank expects, which is the safe direction.
- **It cannot suppress or bypass a red flag.** With an empty token set no
  red-flag rule can match, so there is no flag to suppress.
- **It does not affect any non-empty assessment.** The behaviour is a
  consequence of the empty input alone.
- **Unreachable through the current product UI, reachable through direct engine
  invocation.**

With zero symptoms, `RedFlagEvaluator` returns `proceedToScoring: true`,
`ScoringEngine` scores all 50 conditions on `base_weight` alone, and malaria wins
on the highest base weight (10). The bank's expected source, `empty_default`, is
**not a value any engine version emits** — `UrgencyDeterminer` produces only
`global_red_flag`, `condition_specific_red_flag`, `demographic_escalation` and
`urgency_default`. The expectation describes intended behaviour that was never
implemented, and its note cites E3.5 Case 12, which asserted only that empty
input must not crash — it does not crash, it fabricates.

This is unreachable in the product: `symptom_selection_screen.dart` disables
Continue while nothing is selected, and `loading_screen.dart` guards
`symptomTokens.isEmpty` before any work (E8 FIX 2). Both layers are covered by
`test/assessment/empty_input_guard_test.dart`, and the engine's own behaviour is
deliberately pinned by `test/assessment/engine_wiring_test.dart:218`.

**Still needs a ruling, not a code change here.** Either the engine returns a
safe default on empty input and emits an `empty_default` source (Option C), or
the bank drops an expectation the engine never promised (Option B). No clinical
fix has been attempted, and none is authorised by Option D.

**Neither external beta nor production is approved by this result.**

---

## Human-review observations — CB_225, CB_232, CB_233

These three carry `expected_urgency_source: "observe"` and null expectations.
They count toward the 238 passed — an observe case asserts only that it runs
cleanly, and it does — but their actual output is recorded separately here,
because "passed its encoded assertion" is a weaker statement than "produced the
right answer", and only a human can close that gap.

| Case | Input | Urgency | Red flag | Top condition | vs. KB 2.3 run |
|---|---|---|---|---|---|
| CB_225 | `fever` | `urgent` | no | `malaria` | unchanged |
| CB_232 | `fever, chills, watery_stool, vomiting` | `urgent` | no | `malaria` | unchanged |
| CB_233 | `chest_pain, dizziness, palpitations` | `urgent` | no | `cardio_symptoms` | unchanged |

All three are identical to the KB 2.3 run — no drift across the artifact bump.

### CB_232 — authoritative adjudication

The malaria/diarrhoea overlap was adjudicated upstream and needs **no behavioural
change**:

| | |
|---|---|
| malaria score | 26 |
| acute_diarrhoea score | 21 |
| margin | 5 |
| Tie | **no** |
| Tie-break involved | **no** |
| Iteration-order dependency | **no** |
| Output between KB 2.3 and KB 2.4 | **unchanged** |
| Engineering or clinical artifact change authorised | **none** |

The 5-point margin means the result is not a coin-flip resolved by map ordering,
so there is nothing here for a tie-break to fix — and none is to be implemented.
The observation is retained for clinical visibility, not as a defect.
