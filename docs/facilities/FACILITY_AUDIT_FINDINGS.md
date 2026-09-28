# Facility data audit — findings

Phase 1 and Phase 2 of the facility refresh audit, 2026-09-28. Read-only.
**Nothing in the production artifact, the app or any build has been changed.**

Artifact audited: `facilities.ng.v1.1.json`, sha256
`25684c714367abf2f3c305c8a5597b5f7eb0d11baaf658c5b9e2f8f5e2982398`,
1,695,844 bytes, 5,344 records. Downloaded from the `/config`-published R2 URL
and hash-matched against the frozen record, so this is exactly the artifact the
app loads.

Reproduce with `python3 scripts/audit/audit_facilities.py <artifact> <out-dir>`.
Aggregates in `FACILITY_AUDIT_v1.1.json`; no facility-level records are
committed anywhere in this repository.

---

## Findings by severity

### 1. "Open now" is a hardcoded literal — latent, and a refresh would activate it

`lib/features/locator/facility_card.dart:73-81`:

```dart
if (openingHours != null)
  const Text(
    'Open now',
    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                     color: Color(0xFF22C55E)),
  ),
```

The value of `opening_hours` is never parsed, never compared to the clock,
never read. Any non-null value renders a green "Open now", at any hour.

**It cannot fire today: `opening_hours` is null on all 5,344 records.** The
field exists in every record and is populated in none. So the app currently
tells nobody that a facility is open, by accident rather than by design.

That is what makes it the top finding rather than a curiosity. The moment any
refresh populates `opening_hours` — and GRID3 v3.0 ships a `functional` field
that a generator could reasonably map to it — the app begins telling people a
health facility is open at 3 a.m. on a Sunday on the strength of a string it
never read. **This must be fixed before, not after, any data refresh.**

### 2. `emergency_capable` is an inference presented as a fact

Across all 5,344 records, `emergency_capable` is **exactly** `type == 'hospital'`,
with zero exceptions: 924 hospitals, 924 true.

Nothing observed a resuscitation bay, an oxygen supply or a doctor on site. The
locator ranks emergency-capable facilities first, so a field that means "is
labelled a hospital" is steering people during an emergency as though it meant
"can handle an emergency". The naming invites exactly that reading.

### 3. No provenance fields at all

None of `source`, `source_version`, `source_updated_at`, `contact_verified_at`,
`verification_method`, `operational_status`, `contact_status` or `confidence`
exists. Every one of the 5,344 records is undated and unsourced, and the UI
shows no source or verification date because there is none to show.

### 4. The Call button has no empty-string guard

`facility_card.dart:88` gates on `phone != null` only. A record with
`phone: ""` renders a live Call button that dials nothing. Two hundred lines
away, `facility_id` *is* emptiness-checked, so the pattern exists in the
codebase and was not applied here.

Currently low-impact: only 45 of 5,344 records carry a phone at all, all in
Lagos, and all 45 are structurally well-formed. But "structurally well-formed"
is not "answers", and none has ever been verified.

### 5. `city_area` means something different in each state

Distinct values: Lagos 27, FCT 16, **Kano 307**.

Lagos and FCT look like LGA or area-council granularity. Kano at 307 is
ward or settlement level — Kano State has 44 LGAs. So the one sub-state field
in the schema is not comparable across states, and the manual area picker
offers users a list whose meaning silently changes depending on where they are.

There is no LGA field. Any crosswalk keyed on admin2 has to reckon with this.

### 6. `facility_id` is synthetic, so identifier matching has nothing to match

Values are `ng_lag_001`-style local sequence numbers, unique across the file
but carrying no external meaning. There is no NHFR code and no other official
identifier, so the first and most reliable crosswalk tier cannot be used from
the WellaPath side at all.

### 7. Duplicate candidates: 225 groups, 245 extra records

Normalised name plus state. Some are certainly legitimate — a pharmacy chain
with seven Lagos branches is seven real facilities — which is why these are
review candidates and not merges. 70 pairs additionally sit within 2 km of a
same-named record, which is the subset most likely to be genuine duplication.

### 8. Coordinates are clean

All 5,344 parse, none missing, none structurally invalid, none outside the
Nigeria bounding box, none at 0,0. This is the healthiest part of the dataset
and the refresh should be careful not to make it worse.

### 9. Integrity gaps in the loading path

Reported by subsystem inspection and worth engineering review rather than
action here:

* The locator reads the parsed list straight from the `facility_cache` Hive box
  (`locator_screen.dart:93-100`), bypassing `StagedArtifactLoader` and therefore
  bypassing hash verification on the cached path the app actually uses.
* `_matchesHash` treats a null or empty expected hash as a pass
  (`staged_artifact_loader.dart:320`), so integrity depends on `/config` always
  publishing one.
* The artifact version falls back to `'1.0'` when `/config` omits it
  (`locator_screen.dart:180`), and the version is the cache-key suffix, so two
  different datasets could collide on one key.
* No test asserts the sha256, the record count or the byte size. They exist as
  prose in `RC_FROZEN_INPUTS.json` and nothing would fail if the published
  artifact changed.

---

## Counts

| | |
|---|---|
| Records | 5,344 |
| Lagos / Kano / FCT | 2,690 / 2,040 / 614 |
| Types | health_centre 4,278 · hospital 924 · pharmacy 92 · clinic 50 |
| Ownership | **no field** — public/private cannot be reported |
| Level (primary/secondary/tertiary) | **no field** — the four values above are the only taxonomy |
| With a phone | 45 (0.8%), all Lagos, all structurally valid |
| With an email | 0 |
| Coordinates usable | 5,344 (100%) |
| `opening_hours` populated | 0 |
| Provenance fields | 0 |

Several items the brief asked for cannot be answered from this dataset because
the fields do not exist: ownership counts, primary/secondary/tertiary counts,
LGA counts, source fields, and verification dates. That absence is itself the
finding.

---

## GRID3 v3.0 as a candidate source

Full record in `GRID3_V3_PROVENANCE.md`. The decisive points:

**Licence is clean.** CC BY 4.0, commercial use permitted, attribution the only
condition. Public API, no account needed, fully reproducible.

**Coverage excludes Lagos.** GRID3 v3.0 covers 24 states; Lagos is not one of
them, confirmed both in the publisher's state list and by a distinct-values
query against the live service. Lagos is 50.3% of the current dataset.

| State | WellaPath | GRID3 v3.0 |
|---|---:|---:|
| Lagos | 2,690 | **0** |
| Kano | 2,040 | 2,124 |
| FCT | 614 | 1,047 |

**It cannot supply contact details.** There is no telephone or email field in
GRID3 at all, so the 45 phone numbers stay exactly as unverified as they are.

**Identifier matching is weak.** `nhfr_facility_code` is populated on 4,063 of
41,778 records (9.7%), and WellaPath has no official identifier at all, so the
crosswalk cannot lead with identifiers from either side.

**The publisher says it is not validated.** In their words: a "non-exhaustive,
non-validated geographic representation"; "may lead to … the erroneous
inclusion of abandoned health facilities"; "has not been fully validated by
government officials or in-country stakeholders".

What GRID3 *would* add for Kano and FCT: a real LGA and ward hierarchy,
ownership, a richer level/type taxonomy, per-record provenance, quality flags,
and a `functional` status — with the caveat above about what that status is
worth.
