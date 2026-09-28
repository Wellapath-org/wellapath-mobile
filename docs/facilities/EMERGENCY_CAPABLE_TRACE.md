# `emergency_capable` — behavioural trace

Traced manually against `origin/develop` @ `7e4def8`, 2026-09-28. **Nothing
changed.** This is the impact report; no ranking change is proposed for
implementation until it is reviewed.

## The headline

**The app prioritises hospitals. It does not claim they are emergency-capable
to any user.** No string anywhere tells a person that a facility provides
emergency services, has an ambulance, or can handle an emergency. The field
never reaches the screen.

That is the good news, and it bounds the problem: this is a naming and
data-integrity issue, not a live unsupported claim to a patient.

## What the value actually is

In the shipped artifact, `emergency_capable` is **exactly** `type == 'hospital'`
across all 5,344 records — 924 hospitals, 924 true, zero exceptions. Nothing
observed a resuscitation bay, an oxygen supply or a doctor on duty. It is a
restatement of the type column under a name that sounds like a clinical
assessment.

It must not be described as verified emergency capability, in code, in docs or
in any future UI.

## Producers

**None in the app.** The value arrives in the downloaded artifact and is read
as-is. There is no write, no default, no synthesis, no `?? true`. A grep across
`lib/` finds six occurrences, all reads.

The real producer is whatever generates `facilities.ng.v1.1.json`, which is
outside this repository.

## Consumers — two, both in one file

`lib/features/locator/facility_locator_service.dart`

**1. The emergency branch, lines 65–75.**

```dart
if (isEmergency) {
  final emergencyCapable = _sortedByDistance(
    filtered.where((f) => f['emergency_capable'] == true).toList());
  final others = _sortedByDistance(
    filtered.where((f) => f['emergency_capable'] != true).toList());
  filtered = [...emergencyCapable, ...others];
}
```

Partition and concatenate. Hospitals first by distance, then everything else by
distance. **Nothing is removed.**

**2. The manual-search comparator, lines 130–138.**

```dart
results.sort((a, b) {
  final aCapable = a['emergency_capable'] == true;
  final bCapable = b['emergency_capable'] == true;
  if (aCapable != bCapable) return aCapable ? -1 : 1;
  return aName.compareTo(bName);          // then alphabetical
});
```

A primary sort key with an alphabetical tiebreak.

## Filter or sort? Sort, always

**It never excludes a facility.** Both sites reorder.

Worth separating from something that does filter: `_typesForUrgency` (lines
17–27) is a genuine type filter — `urgent`/`non_urgent` restrict to hospital
and clinic, `self_care` to pharmacy and health centre. For `emergency` it
returns an empty set, and line 58 bypasses filtering entirely, so **the
emergency path is the one path that shows every facility type**. The
`emergency_capable` ordering then floats hospitals to the top of that
unfiltered list.

So a red-flag user sees pharmacies and health centres too, below the hospitals.
That is the right behaviour and the ordering is the only thing making it
useful.

## Journeys that depend on it

`LocatorScreen` takes a required `urgency`. Four entry points:

| Entry point | Urgency passed | Hits the emergency branch? |
|---|---|---|
| `results/red_flag_interrupt_screen.dart:73` | `engineOutput.urgency` | **Yes, when the engine returns `emergency`** |
| `results/results_screen.dart:81` | `engineOutput.urgency` | Yes, same condition |
| `home/home_screen.dart:40` | `'non_urgent'` (const) | No |
| `onboarding/onboarding_screen.dart:124` | `'non_urgent'` | No |

`emergency` is a real engine output — `output_formatter.dart:3` lists
`{emergency, urgent, non_urgent, self_care}`, and `urgency_determiner.dart`
sets it on a red-flag hit and on an `escalate_emergency` demographic modifier.

**So the red-flag journey is the one that depends on this ordering.** That is
the highest-stakes path in the product, which is the argument for getting the
naming right rather than for leaving it alone.

## User-facing text — none

No string in `lib/features/locator/` mentions emergency capability. The
facility card renders name, area, state, distance, and the Call and Directions
buttons. `type` and `emergency_capable` are used for ranking and shown nowhere.

The only occurrences of the word in the locator are the two code conditions.

**A user cannot see this field, cannot see that hospitals were floated, and is
never told a facility can handle an emergency.**

One consequence worth noting: because the ordering is invisible, a user has no
way to know why the list is in the order it is. That is defensible for a
distance-sorted list with a sensible bias, and it is also why renaming costs
nothing in the UI.

## Telemetry — not carried

No telemetry event includes `emergency_capable` or anything derived from it.
Grep over `lib/core/telemetry/` returns nothing.

## Tests

Three files assert on it.

* `test/locator/facility_locator_service_test.dart` — fixtures set the field on
  five records; **TEST 2** asserts emergency-capable facilities come first
  under `emergency` urgency.
* `test/locator/covered_state_search_test.dart:144` — asserts the ordering
  holds per covered state.
* `test/locator/facility_wording_test.dart:144` — asserts the **literal source
  text** `facility['emergency_capable'] == true` is present in the service.
  This one pins the implementation string, so any rename fails it by design.
  It is a deliberate tripwire, not an accident.

## Three options

### A. Rename, preserve ordering exactly — recommended

Rename the concept to what it is: hospital-type priority. Keep reading the same
artifact field for now, behind a clearly named accessor, so the ordering is
bit-for-bit identical.

* Behaviour: **identical**. Same comparator, same partition, same output order.
* Tests: TEST 2 and the covered-state assertion pass unchanged; the
  `facility_wording_test.dart:144` string pin must be updated to the new text.
* Risk: near zero. No user-visible change, no clinical change.
* Gains: the codebase stops asserting a clinical property it has never
  measured, and the next person to read it cannot mistake it for one.

### B. Drop the field, rank on `type == 'hospital'` directly

* Behaviour: **identical today**, because the two are equal on every record.
* Risk: slightly higher. If a future artifact ever populates
  `emergency_capable` independently of type, option B silently ignores it while
  option A would pick it up. Given NHFR has no verified emergency field either,
  that future is not near.
* Gains: removes the misleading field from the schema entirely.

### C. Recalculate from something real — not currently possible

Nothing in the current schema supports it. The fields are `facility_id`,
`name`, `type`, `state`, `city_area`, `latitude`, `longitude`, `phone`,
`opening_hours`, `emergency_capable`. None carries services, staffing,
equipment or hours of cover.

NHFR is richer — it has `ambulance_services`, bed counts and staffing columns —
but an NHFR registry flag is a listing, not a confirmation that a service
operates today, and its own publisher does not warrant it. **Emergency
capability cannot be derived from any source now available. It requires direct
verification per facility.**

## Recommendation

**Option A**, as a separate reviewed change, after this trace is accepted.

Two things to hold onto regardless of which option is chosen:

1. Hospital prioritisation on the red-flag path is **correct behaviour** and
   should be preserved. The problem is the name, not the ranking.
2. Nothing should ever display or imply verified emergency capability until a
   human has confirmed it for that facility. Not from `type`, not from
   `emergency_capable`, and not from an NHFR registry value.
