# Facilities 2.0 Consumer — contract preparation (inactive)

**Status: default-off, production-blocked, unreachable from the product.**
The candidate dataset (`facilities.ng.v2.0.json`) remains
`candidate_unapproved` / `may_publish: false`, is **not** in this
repository, and cannot be activated by any flag combination this
repository can express. The live locator uses facilities **1.1** exactly
as shipped in build 210.

## Layout — `lib/core/facilities_v2/` (zero inbound imports)

| File | Role |
|---|---|
| `facilities_v2_gate.dart` | `FacilitiesV2Gate` — the development gate |
| `facilities_v2_manifest.dart` | approval record; `isApprovedForConsumption` |
| `facility_v2.dart` | model, `FacilityTypeV2`, approval-gated presentation |
| `facilities_v2_parser.dart` | version-aware parser, per-record isolation |
| `facilities_v2_search.dart` | local search/sort/filter, null-type guarantee |
| `emergency_fallback_policy.dart` | FAC-D002 decision point |
| `facilities_v2_loader.dart` | gate-checked, hash-verified load + fallback |

Isolation is guarded by `test/facilities_v2/facilities_v2_isolation_test.dart`
— the same convention as the Question Flow 1.1 and Vocabulary 2.0
consumers: no file outside the directory may reference it, the consumer
imports no HTTP client/plugin/telemetry/storage (seams are injected), and
the v1.1 locator files must not mention it.

## The gate — `FacilitiesV2Gate`

Activation requires **all** of:

1. `FACILITIES_V2_EVALUATION=true` as a `--dart-define` (absent by
   default; not in `.env`; build 210 resolves inactive);
2. not production — `APP_ENV=production` blocks unless the separately
   named `FACILITIES_V2_PRODUCTION_APPROVED` is set, which nothing sets;
3. a `FacilitiesV2Manifest` whose artifact is `status: approved` **and**
   `may_publish: true` **and** schema major 2 **and** carries a SHA-256.

The candidate fails (3) on two independent fields, so the v2 path cannot
activate today even with every flag set. No real v2 URL or hash exists in
this repository; tests use a synthetic manifest pointing at
`example.invalid` with a hash over the synthetic fixture.

## Contract tolerances (schema 2.0)

`type: null` → `FacilityTypeV2.unspecified` (unknown, never false, never
inferred from the name); unknown future type strings →
`FacilityTypeV2.unrecognized` with the raw value preserved — both stay
fully visible and searchable, and `filterForUrgency` retains them after
typed matches, so a null/unknown type can never empty a result list.
`emergency_capable: null` stays null — **only `== true` earns emergency
priority** (FAC-D002 pending; fallback wording claims no capability and
keeps 112 first, isolated in `EmergencyFallbackPolicy.pendingApproval`).
Missing phone/opening hours parse as absent; v2 phone numbers and opening
hours are reachable only through `FacilitiesV2Presentation`, whose
approvals default off pending source public-use authorization — unknown
hours can never render as "open" (the display enum has no `open` state).
Provenance/coordinate-audit fields are carried opaquely. Coordinates pass
through verbatim; out-of-range or non-numeric coordinates reject the
record — Mobile never repairs, snaps, swaps or infers coordinates (Data
Engineering owns those transformations). Malformed records are isolated
per-record; wrong schema major, non-list facilities and an empty
candidate are artifact-level rejections.

## Fallback and rollback

`FacilitiesV2Loader.load` resolves **fallbackToV1** on: gate inactive ·
manifest unapproved · download failure · SHA-256 mismatch (verified via
`StagedArtifactLoader.verifyArtifactHash`, the same trusted check every
shipped artifact uses) · schema/parse failure · empty/unusable candidate.
v2 caches under its own namespace (`artifact_facilities_v2_v<version>`,
`facilities_v2_data`), disjoint from every v1.1 key; the loader never
reads, writes or deletes a v1.1 key, so a failed v2 attempt cannot erase
the last valid v1.1 cache — asserted by a write-set spy in tests.

## Fixture

`test/fixtures/facilities_v2/synthetic_facilities_v2_fixture.json` — 11
entries (6 valid, 5 malformed), every name prefixed `ZZTest … (synthetic)`
with a `_fixture_note` stating it derives from no candidate record.

## Attribution — `FacilitiesV2Attribution` + `FacilityDataSourceEntry`

The Knowledge Base attribution notice (`facilities/ATTRIBUTION_GRID3.md`)
makes in-app attribution a **condition of first publication** for the
GRID3 lineage. The consumer now carries it, gated exactly like everything
else v2:

- `FacilitiesV2Attribution` holds the citation, licence name and
  validated links. Artifact `_metadata.source` fields are consumed as
  plain text only (length-capped, control-character-checked) and links
  render only as absolute `https://` URLs — `http:`, `javascript:`,
  `data:`, `file:` and every other scheme are dropped. Any invalid field
  falls back per-field to the vendored GRID3 notice, because the citation
  is a licence obligation and must not disappear on malformed metadata.
  The normalization disclosure and the non-endorsement statement are
  compile-time constants an artifact can never override.
- `FacilityDataSourceEntry` renders a small, accessible "Facility data
  source" block (semantic header, 48 dp link targets) **only when
  `FacilitiesV2Gate.active` and the v2 load actually served
  (network/cache)**. Gate off, no manifest, unapproved manifest or
  `fallbackToV1` all render nothing, so the notice can never accompany
  v1.1 data and no build that exists today can show it. The v1.1
  locator's (absent) facility-data attribution behaviour is untouched —
  nothing outside `lib/core/facilities_v2/` references the widget.
- **Activation requirement:** the future change that wires the v2 loader
  into the locator UI MUST mount `FacilityDataSourceEntry` in the
  facility-locator experience. Until then the widget is complete, tested
  and unmounted, like the rest of the consumer.

## Performance — measured against the real served candidate (evaluation only)

Evaluated 2026-09-14 against KB PR #42's served candidate
(`03a58e67…cebd75`, 8,749,444 B, 51,022 records) from an untracked local
copy; the artifact was not committed, bundled or configured. Host
reference (macOS arm64 AOT; the low-end Android profile could not be
exercised in that session — see PROGRESS.md):

- read+hash+decode+parse of all 51,022 records: ~130 ms end to end
  (hash 65 ms, decode ~35 ms, parse 15 ms); zero record rejections.
- The gate-off path performs zero download/parse/cache work (measured
  0–1 µs, no I/O touches) — v2 costs nothing while disabled.
- Search initially re-normalized every record's text per query
  (~78 ms/query for contains searches on the host — projected past the
  200 ms repeated-search budget on low-end Android). Fixed by per-record
  `Expando` normalization caches in `FacilitiesV2Search`: normalize once
  per record on first use, results proven identical by test. After:
  state ≈1 ms, contains ≈8–11 ms per query on the host.
- Distance sort over all records ≈8 ms; repeated open/close parses
  plateau in memory (no unbounded duplicates).
- Steady-state Dart heap for the full dataset ≈80 MB on the host VM;
  Android AOT uses compressed pointers so the on-device figure is
  expected lower, but **must be re-measured on the agreed low-end
  Android profile before activation** — recorded as an open
  activation-gating measurement.

## Unresolved dependencies (not this task's to decide)

- Source authorization for the candidate dataset (`may_publish`) — Data
  Engineering / source owner.
- Product + Clinical approval of FAC-D002 emergency fallback wording.
- Source public-use authorization for phone numbers and opening hours.
- Product/Clinical review before any service filter is exposed (none is).
- A real approved manifest + `/config`/Backend publication — Backend.
- Emergency Hub 2.0 — explicitly out of scope here.
