# WellaPath Internal Beta — Known Limitations

Owner: Mobile Engineer. Phase E9.
Applies to the `v0.1.0-beta.1` internal beta release candidate.

Everything below is **known, accepted and non-blocking** for internal beta by
engineering lead ruling. It is written for the people testing the build, so a
tester who hits one of these recognises it as expected rather than filing it
fresh — and so nothing here is mistaken for having been missed.

Verified on the signed release build against kb.ng.v2.4 / rules.ng.v2.2 /
token_dictionary.ng.v1.1 / facilities.ng.v1.1.

---

## 1. No offline indicator — [#21](../../issues/21)

**What a tester sees:** with no connectivity the app still works, but nothing
on screen says it is offline. Results look identical to an online run.

**Verified working offline** (E9.3 demo 3, app traffic blocked at the kernel
by UID, artifacts pre-cached):

- Full assessment completes from cached artifacts — urgent / malaria returned
- No crash
- No error screen

Only the indicator itself is missing. Waived into beta; tracked on #21.

## 2. Offline cold boot sits on the splash for ~50 seconds

**What a tester sees:** launching with no connectivity holds the WellaPath
splash for roughly 50 seconds before the home screen appears, with no
progress text.

**This is correct behaviour, not a hang.** It is the `/config` retry with
exponential backoff added in [#26](../../issues/26) running to exhaustion —
2s + 4s + 8s of backoff plus per-attempt timeouts — before falling back to the
cached config. The app then proceeds normally.

Not blocking. Worth noting for a tester who would otherwise force-quit at the
30 second mark and report a freeze.

## 3. "Call" button rarely appears in the facility locator — [#50](../../issues/50)

**What a tester sees:** facility cards show **Directions** but usually no
**Call**.

**This is a data coverage gap, not a defect.** In `facilities.ng.v1.1`:

- 5,344 facilities total
- **45 have a phone number — 0.84%**
- Those 45 cluster in a few LGAs (Ajeromi/Ifelodun, Agege, Alimosho)

The locator lists the 30 nearest facilities. For a central-Lagos position,
**none of the 30 nearest has a phone number** — the closest that does is
6.7 km away, outside the window. So the Call button is expected to be absent
for most positions.

Everything else in the locator is verified working: permission prompt, map
with markers, list view, and correct distance sorting (0.3 → 0.5 → 0.6 →
1.4 → 1.5 km).

Improves when the NHFR API key lands and phone coverage is enriched.

## 4. Locator does not re-query when location changes — [#49](../../issues/49)

**What a tester sees:** if the device location changes while the locator is
open, the facility list keeps the previous location's results and distances.

Low impact within a single assessment. Observed on emulator with a synthetic
location fix; to be re-checked on a real device during SIM validation
([#23](../../issues/23)).

## 5. Body-area search box does not search symptoms — [#45](../../issues/45)

**What a tester sees:** the box on the body-area screen is placeholdered
*"Search symptoms eg. headache"*, but it filters **body areas**. Typing a
symptom — including `headache`, the placeholder's own example — returns an
empty list with no "no results" message.

**Workaround:** tap into a body area, then "Add symptoms", and use the search
inside that sheet. That inner search does search symptoms correctly.

## 6. Clinical questions open against the knowledge base

Not defects — open questions recorded for the clinical reviewer, listed here
so testers do not re-report them:

| Behaviour | Issue |
|---|---|
| Isolated headache with no fever routes to malaria at `urgent` | [#42](../../issues/42) |
| Malaria wins mixed presentations on `base_weight` 10, the highest in the KB | [#38](../../issues/38) |
| `increase_urgency` is a no-op on conditions already `urgent`/`emergency` | [#36](../../issues/36) |
| Empty input would return `urgent`/malaria if it reached the engine — blocked in the app before it can | [#35](../../issues/35) |

---

## What is verified working

For balance, confirmed on the signed release build during E9.3:

- **Triage flow end to end** — fever + headache + chills → **URGENT**, malaria
  top, correct care instruction
- **Red flag interrupt** — seizures → **EMERGENCY**, rule name *"Active
  Seizures — this is a universal danger sign"*, Call Emergency CTA, CDSS
  disclaimer
- **Per-condition explanations** — each possible condition shows its own
  `explanation_template` (fixed in [#46](../../issues/46); before that every
  card showed the top condition's text)
- **Case bank** — 235/236 = **99.58%**, zero under-triage, zero
  safety-critical failures, 13/13 global red flag rules exercised
- **No PHI in release logs** — a full assessment on the release build produced
  zero symptom tokens, condition names or urgency values in logcat
- **Artifact integrity** — sha256 verified on every artifact read, cache hit
  and fresh download alike

## Rollback

See [`BETA_ROLLBACK.md`](BETA_ROLLBACK.md) for frozen artifact versions and
the two rollback levers.
