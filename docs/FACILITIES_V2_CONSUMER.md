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

## Unresolved dependencies (not this task's to decide)

- Source authorization for the candidate dataset (`may_publish`) — Data
  Engineering / source owner.
- Product + Clinical approval of FAC-D002 emergency fallback wording.
- Source public-use authorization for phone numbers and opening hours.
- Product/Clinical review before any service filter is exposed (none is).
- A real approved manifest + `/config`/Backend publication — Backend.
- Emergency Hub 2.0 — explicitly out of scope here.
