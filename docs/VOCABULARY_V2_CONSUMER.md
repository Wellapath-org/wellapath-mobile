# Vocabulary 2.0 — Offline Consumer and Search Foundation

Mobile-side loader, normalization pipeline, search resolver, canonical-token
boundary and feature gate for the schema-2.0 token dictionary.

> **Vocabulary 2.0 is unpublished, clinically unreviewed and inactive.** It has
> no R2 object, no live-manifest entry, zero approved aliases, zero approved
> associations, and `display_safe: false` on all 295 tokens. Nothing in this
> work publishes it, activates it, or makes it the scoring vocabulary. The live
> app still uses **token dictionary 1.1 / KB 2.4 / rules 2.2**, unchanged.
>
> **This is not clinical approval, and nothing here demonstrates a real-user
> search improvement.**

---

## 1. Architecture and data flow

```
  user query (String)
        │
        ▼
  normalizeVocabularyQuery()          vocabulary_normalizer.dart
        │  pure, total, idempotent, deterministic
        ▼
  VocabularySearchIndex.resolve()     vocabulary_search.dart
        │  whole-string equality only
        ▼
  VocabularyResolution
        │  resolvedTokenId: CanonicalTokenId?   ← null on ambiguous / no_match
        ▼
  CanonicalTokenBoundary.commit()     canonical_token_boundary.dart
        │  refuses anything not in the ACTIVE APPROVED vocabulary
        ▼
  AssessmentController.addSymptomToken(canonical id)
        │
        ▼
  buildEngineInput → EngineController   ← unchanged, still reads v1.1
```

| File | Role |
|---|---|
| `lib/core/vocabulary/vocabulary_normalizer.dart` | The authoritative normalization pipeline |
| `lib/core/vocabulary/vocabulary_v2.dart` | Immutable domain model + `CanonicalTokenId` |
| `lib/core/vocabulary/vocabulary_v2_loader.dart` | Strict offline loader, typed failures |
| `lib/core/vocabulary/vocabulary_search.dart` | Offline index + resolver |
| `lib/core/vocabulary/canonical_token_boundary.dart` | The only path into assessment state |
| `lib/core/vocabulary/vocabulary_config.dart` | Build-time gate, default off |

**The engine is untouched.** `EngineController`, `ScoringEngine`,
`RedFlagEvaluator`, `UrgencyDeterminer` and `OutputFormatter` are unchanged and
have no reference to anything in `lib/core/vocabulary/`.

---

## 2. Contract provenance

Vendored byte-for-byte from `Wellapath-org/wellapath-knowledge-base` at
`dceecde2ee7545664bf45ea5edfa137a52acdebd`, into
`test/fixtures/vocabulary/`. Hashes are pinned in
`test/vocabulary/vocabulary_contract.dart` and enforced by
`vocabulary_contract_test.dart`, which never skips.

| Source path | Destination | SHA256 | Bytes |
|---|---|---|---|
| `candidate/token_dictionary.ng.v2.0.json` | `candidate/token_dictionary.ng.v2.0.json` | `07f93596…4e34cd2d` | 339,948 |
| `candidate/manifest.candidate.json` | `candidate/manifest.candidate.json` | `fa7045a0…1d31c7c545b`¹ | 3,065 |
| `schema/token_dictionary.v2.schema.json` | `schema/token_dictionary.v2.schema.json` | `397227a1…3f47580f` | 15,898 |
| `schema/token_dictionary_schema_v2.0.json` | `schema/token_dictionary_schema_v2.0.json` | `f2b1d73a…cebfaf80` | 35,409 |
| `mobile_handoff/vocabulary_v2/vocabulary_types.dart` | `handoff/vocabulary_types.dart.txt` | `d3a1fa28…d5132b7c5399` | 14,781 |
| `docs/VOCABULARY_NORMALIZATION_SPEC.md` | `docs/VOCABULARY_NORMALIZATION_SPEC.md` | `b7c901fa…1f26e307bc` | 6,903 |
| `docs/VOCABULARY_AMBIGUITY_SPEC.md` | `docs/VOCABULARY_AMBIGUITY_SPEC.md` | `78c9095e…5c7688ab34` | 7,949 |
| `testing/…/search_cases_v1.json` | `search/search_cases_v1.json` | `6472a698…f3c3d370e7` | 11,852 |
| `testing/…/ambiguity_cases_v1.json` | `search/ambiguity_cases_v1.json` | `7964cb05…5ca1870c156` | 4,382 |
| `testing/…/synthetic_vocabulary_v1.json` | `search/synthetic_vocabulary_v1.json` | `e60dee1d…8d708ff362` | 7,823 |
| `testing/…/invalid/index.json` + 21 fixtures | `invalid/` | see contract file | — |

¹ Full values are in `test/vocabulary/vocabulary_contract.dart`.

**Note on the handoff types file:** stored as `vocabulary_types.dart.txt`. The
bytes are unchanged and the hash matches; only the extension differs, so the
analyzer does not compile a reference artifact as project source.

### Drift protection

CI fails if any fixture is missing or its hash/byte count changes, and
separately if the candidate's `version`, `schema_version`, `release_status`,
`may_publish`, clinical-review status or token count changes, if any canonical
token id is added/removed/renamed/deprecated, if a frozen legacy array differs,
or if the candidate is wired into `pubspec.yaml`, `assets/` or any `lib/`
source.

`may_publish` is asserted as **"never `true`"** rather than `== false`: the
current candidate carries `null`, and absence is not permission.

---

## 3. Normalization

Direct implementation of `VOCABULARY_NORMALIZATION_SPEC.md`, normalization
version **1.0.0**, in the specified order:

1. **Variant folding** — apostrophe-like → `'`, dash-like → `-`, space-like →
   ` `. Runs **before and after** NFKC, because NFKC decomposes some of these
   into forms the map would no longer recognise.
2. **Unicode NFKC**
3. **Case folding** (full Unicode, not ASCII-only)
4. **Apostrophe deletion** — `'` removed with no replacement
5. **Punctuation pass** — letters/digits kept; `.` and `/` kept *between ASCII
   digits*; `,` deleted between digits; everything else → a single space.
   Hyphens become **spaces, not nothing**.
6. **Whitespace collapse** and trim

`normalizeTokenId(id) = normalize(id.replace('_', ' '))`.

### Deliberately not done

No stemming, plural folding, spelling correction, edit-distance or fuzzy
matching, prefix or substring inference, stopword removal, synonym expansion,
diacritic stripping, semantic similarity, AI/LLM matching, or any server-side
interpretation. Every one is a safety property.

Because negation words survive and matching is whole-string equality,
**`no fever` normalizes to `no fever` and resolves to nothing.** It cannot
reach `fever` by any path.

### Dependency added

`unorm_dart: ^0.3.2` — pure Dart, offline, no native code. Dart has no built-in
NFKC, and step 2 is required by the specification. The alternative was a
hand-rolled partial fold that would conform to the fixtures while silently
diverging from the contract on input they do not cover. **This is a new runtime
dependency and needs engineering-lead sign-off.**

---

## 4. Search and ambiguity

Resolution order, highest precedence first:

| Order | Match | Status |
|---|---|---|
| 1 | raw query is a token id, byte for byte | `exact_canonical` |
| 2 | raw query is an approved alias, byte for byte, unique | `exact_alias` |
| 3 | normalized query hits the index | `normalized` |
| — | 2 or 3 reaching more than one token | `ambiguous` |
| — | nothing | `no_match` |

- The resolver returns **canonical token ids, never alias strings**.
- `match_source` is reported: `token_id`, `alias` or `canonical_label`.
- Candidate ordering comes from the artifact's own
  `search_index.normalized_forms`, **consumed rather than rebuilt**, so ordering
  is authoritative and deterministic.
- Duplicates resolving to the same token are deduplicated.
- **Ambiguity never auto-selects.** `resolvedTokenId` is null and
  `scoring_eligible` is false; the candidates are reported so a picker can ask
  the user.
- The exact-id rule sits above the others, so a token whose id collides with
  another token's label still resolves to itself when typed exactly.

### Display safety

`displaySafeLabel()` returns null unless the token is `display_safe`. Every
token in the current candidate is `display_safe: false`, so **it returns null
for all 295** and no candidate label is shown anywhere. The existing approved
`kSymptomDisplayMap` remains the display-label source.

---

## 5. The canonical-token boundary

`CanonicalTokenId` has a **private constructor**. The only way to obtain one is
`VocabularyV2.canonicalTokenId(String)`, which returns null for anything not in
the loaded vocabulary. The resolver uses that same validating accessor — there
is no privileged construction path anywhere in the app.

So these are not "rejected by a check", they are **unrepresentable at the call
site**: raw query text, normalized query text, alias text, body-area labels,
complaint-group labels, severity labels, duration labels, arbitrary metadata,
and unknown token ids.

An unresolved or ambiguous resolution carries no `CanonicalTokenId` at all, so
ambiguity cannot enter scoring even via a caller that ignores the status.

`CanonicalTokenBoundary` additionally refuses any token absent from the
**active approved vocabulary** (v1.1), so loading a candidate can never widen
what scoring accepts.

### Known limitation

`AssessmentController.addSymptomToken(String)` still exists and still accepts a
string, because the live v1.1 picker uses it and this work must not change live
behaviour. The v2 path cannot reach it with anything but a validated canonical
id. Making the string overload private is a follow-up that touches the live
picker and should be its own reviewed change.

---

## 6. Feature gate and production block

Two independent build-time keys, mirroring `CrashConfig` / `TelemetryConfig`:

| Define | Meaning |
|---|---|
| `VOCABULARY_V2_EVALUATION` | Gate 1. Only `true` enables |
| `APP_ENV=production`/`prod` | Forces disabled |
| `VOCABULARY_V2_PRODUCTION_APPROVED` | The only key that lifts the production block |

Defaults to disabled in every ordinary build, local build and test run.
**The presence of the candidate enables nothing** — it ships only as a test
fixture, is not declared in `pubspec.yaml`, and is not in `assets/`, so a normal
build cannot read it at all. Enabled still does *not* make the candidate the
scoring vocabulary.

---

## 7. Offline behaviour and privacy posture

- The loader reads **local bytes only**. `vocabulary_v2_loader.dart`,
  `vocabulary_search.dart`, `vocabulary_normalizer.dart` and
  `canonical_token_boundary.dart` import no `dart:io`, no Dio, no HTTP client,
  no telemetry — asserted structurally by a test that greps their imports.
- **No search query, symptom token, selected symptom or assessment path is
  transmitted.** There is nothing in these files that could transmit one.
- Loading and searching work in airplane mode; the test binding has no platform
  channels or HTTP client wired, and the load completes.
- A malformed candidate returns a typed `VocabularyLoadFailure` and **never
  partial data**; the live v1.1 path is untouched.
- Telemetry contract v1.0 and crash-monitoring configuration are unchanged.

---

## 8. Results

### Authoritative fixtures

| Fixture set | Cases | Result |
|---|---|---|
| `search_cases_v1.json` (real candidate) | 34 | **34/34 pass** |
| `ambiguity_cases_v1.json` (synthetic vocabulary) | 11 | **11/11 pass** |
| `invalid/` defect fixtures | 21 | **21/21 correctly rejected** |

Every case matches on all five recorded dimensions: normalized form, status,
resolved token id, candidate list **in order**, and scoring eligibility.

### Hit rate — read carefully

20 of the 34 authoritative cases are designed to resolve; the other 14 are
negation, prefix, typo, plural, phrase and punctuation queries that **must not**
resolve. The measured hit rate is exactly 20/34, and the test asserts that
number in **both directions** — a higher count would be a contract violation,
not an improvement.

| Claim | Status |
|---|---|
| Contract-fixture conformance | **34/34 + 11/11 + 21/21** |
| Candidate-real-data result | The real candidate has **zero aliases and zero label collisions**, so it cannot exercise alias or ambiguity behaviour at all. Those paths are proven only against the synthetic fixture. |
| Real-user hit-rate improvement | **No evidence. Not claimed.** Synthetic fixtures say nothing about real users. |

### Current v1.1 picker vs the v2 resolver

The live picker filters `kSymptomDisplayMap` (129 labels) with a case-insensitive
**substring** test. The v2 resolver uses whole-string equality over 295 tokens.
They answer different questions:

- `ever` → current picker offers *Fever*; v2 returns `no_match`.
- `no fever` → both refuse, but the picker only incidentally (its label does not
  contain the query) while v2 refuses by explicit contract.
- v2 reaches ids the display map never exposes (e.g. `haemoglobinuria`) — that is
  **reach, not approval**: those labels are still unreviewed.

### Clinical regression — unchanged

| | |
|---|---|
| Case bank | **239 executed · 238 passed · 1 known finding · 0 unexpected failures** |
| CB_211 | pinned and unresolved, not counted as passed |
| Safety-critical under-triage | **0** |
| Red-flag precedence | intact — red flags still override scoring |
| v1.1 reconstruction | **byte-identical** from the candidate's frozen arrays |
| `breathlessness` / `shortness_of_breath` | independent tokens; neither aliases, replaces or reaches the other |

### Performance (developer machine)

| Metric | Measured |
|---|---|
| Artifact size | 339,948 bytes, 295 tokens |
| Parse + validate (median of 10) | **7.3 ms** |
| Index build (median of 10) | **25 µs** |
| Cold first query | **492 µs** |
| Warm query (median of 2000) | **4 µs** |
| Warm query p95 | **6 µs** |
| RSS delta, 5 vocabularies + indexes held | **2.1 MB** |

Test thresholds are order-of-magnitude ceilings far above these values, set to
catch a regression rather than to assert a target.

**Not measured: the documented low-end Android emulator profile.** These are
developer-machine numbers and are not evidence about low-end handset behaviour.
Because the gate is off, the candidate is never loaded in a normal build, so
there is no assessment-path delay to measure there.

---

## 9. Limitations

1. **No low-end device measurement.** See above.
2. **Alias and ambiguity behaviour is proven only synthetically** — the real
   candidate has none. Aliases were deliberately **not** added to the candidate
   to make tests pass.
3. **No real-user evidence** of any search improvement.
4. **`addSymptomToken(String)` remains** on the controller for the live picker.
5. **New runtime dependency** (`unorm_dart`) needs sign-off.
6. **Complaint groups are empty** in the candidate, so group filtering is
   implemented and type-checked but exercises no real data.
7. **JSON Schema is vendored but not executed** — validation is implemented as
   explicit Dart checks against the contract's named rules, and verified by all
   21 defect fixtures. Wiring a JSON-Schema validator would need another
   dependency for no additional coverage the fixtures do not already provide.

---

## 10. Activation prerequisites

All of these must land before Vocabulary 2.0 can be considered for activation:

- [ ] **Approved clinical/product alias and label catalogue**
- [ ] **Approved body-area, severity, duration and complaint-group associations**
- [ ] **Display-safe approval** — every label to be shown reviewed and
      `display_safe: true` with `label_review_status: approved`
- [ ] **Case-bank clinical sign-off** (still absent; see
      `docs/CASE_BANK_PROVENANCE.md`)
- [ ] **Separately reviewed publication decision** — `release_status` and
      `may_publish` changed deliberately, not incidentally
- [ ] **Published versioned artifact and manifest** — R2 object uploaded, live
      `/config` manifest entry added with hash
- [ ] **Successful internal evaluation** under the gate
- [ ] Engineering-lead sign-off on the `unorm_dart` dependency
- [ ] Low-end handset performance measurement

---

## 11. Rollback

Nothing is live, so there is nothing to roll back operationally. If this branch
is reverted:

- No user-visible behaviour changes — the gate is off and the candidate is not
  in the asset bundle.
- The live artifact set (v1.1 / KB 2.4 / rules 2.2) is untouched, and its
  manifest was never modified.
- The only production-graph change is the `unorm_dart` dependency, removed by
  the revert.

If the candidate were ever activated and had to be withdrawn, the artifact's own
`rollback_target` names token dictionary **1.1**, sha256
`0cc47ad9537c0bd4c6ef3aec8f1931eb9b4c62103a8809d16544f94a90b5c019`, and
`StagedArtifactLoader` already verifies every cached artifact against its
expected hash on **every read**, deleting and re-fetching on mismatch — so
reverting the manifest entry is sufficient to return clients to v1.1.
