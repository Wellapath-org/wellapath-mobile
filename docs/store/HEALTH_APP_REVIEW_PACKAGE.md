# WellaPath — reviewer & tester briefing package

For store reviewers and internal testers. Build **0.3.0 (210)**,
`org.wellapath.app`, internal testing only. Every claim below is verified
in the repository; nothing here asserts accuracy, regulatory status or
coverage beyond what is shipped.

## What WellaPath is

WellaPath is a **Clinical Decision Support System (CDSS)** for people in
Nigeria deciding what to do about symptoms. The user answers a short
questionnaire; the app returns an **urgency level** (emergency / urgent /
non-urgent / self-care), a list of **possible causes** with match
strength, a fixed **care instruction**, and a **facility finder**.

**WellaPath does not diagnose and does not replace a medical
professional.** That disclaimer appears on the home screen, in the
pre-assessment info sheet, and on every results screen. Results language
is "possible causes" and "match strength" — never a diagnosis.

## How urgent / red-flag advice works

- Assessment logic runs **entirely on the device** against versioned,
  hash-verified clinical artifacts downloaded from WellaPath's backend.
  Symptom answers never leave the device.
- **Red-flag danger signs always override scoring.** A recognised danger
  sign (e.g. active seizures, inability to drink, severe chest indrawing)
  immediately interrupts the questionnaire and shows an EMERGENCY screen
  with a one-tap call to **112** and a facility option. 13/13 global
  red-flag rules are exercised by the automated clinical regression; in
  the 239-case clinical bank, all 124 red-flag cases return emergency with
  scoring skipped.
- The red-flag interrupt cannot be dismissed accidentally (back is
  intercepted with a confirmation).

## Active clinical artifacts (source and version)

Published by the staging backend `/config` and verified by SHA-256 on
every load; produced by the WellaPath knowledge-base workstream
(repository `Wellapath-org/wellapath-knowledge-base`):

| Artifact | Version |
|---|---|
| token_dictionary | 1.1 |
| knowledge_base | 2.4 |
| rules | 2.2 |
| facilities | 1.1 |

Clinical regression at this build: **239 cases executed · 238 passed ·
1 known finding · 0 unexpected failures · 0 safety-critical under-triage.**
This is engineering validation against the specification, **not clinical
certification** — the case bank carries no recorded clinical approval.

## Known limitation — CB_211 (why it stays, and why it is unreachable)

With a **completely empty** symptom set, the engine returns `urgent` with
a ranked cause instead of a neutral default. This is **over-triage** (it
can only err toward more care), it **cannot suppress a red flag**, and it
is **unreachable through the app**: the Continue button is disabled until
at least one symptom is selected, and the loading screen independently
refuses empty input. It is tracked as issue #35 with an engineering-lead
disposition (Option D), pinned by a fail-closed test, and **blocks
external beta and production** until clinically adjudicated. It does not
affect internal testing.

## Facility coverage — current limitation

The facility dataset holds **5,344 facilities in exactly three states:
Lagos (2,690), Kano (2,040), FCT (614)**. The app says so explicitly to
out-of-region users and in empty-result states. No nationwide-coverage
claim is made anywhere, and none may be added to store metadata. There is
no distance cap; every facility card shows its distance.

## Staging dependency

This build talks to WellaPath's **staging** backend only. First launch
after the backend has been idle can take 15–20 seconds (the app shows a
connecting state and retries with a bounded 30 s budget); after first
launch the app works offline from verified cached artifacts. There is no
production backend yet — that is a deliberate release gate, enforced at
boot: this build refuses to start against a production URL, and a
production-declared build refuses to start against staging.

## Support contact & privacy policy

Both **required and not yet live** — see
`docs/store/SUPPORT_AND_PRIVACY_POLICY.md`. The store declarations cannot
be completed until the founder designates the support mailbox and approves
the privacy-policy text.

## Test path and credentials

See `docs/release/INTERNAL_TESTING_0.3.0_210.md` for the step-by-step test
path. **No credentials exist or are needed — the app has no login.**

## Review-sensitivity notes (Apple §1.4 / medical scrutiny)

- All medical guidance is sourced from the versioned clinical artifacts;
  care instructions are four fixed strings; explanations come from
  artifact templates, never generated text.
- Emergency escalation is conservative by design (red flags dominate).
- The backend the reviewer will hit is staging; it must be kept warm/alive
  during any review window (Render free tier spins down — see runbook).
- No accuracy, cure, treatment or regulatory claims are made in-app or in
  metadata, and none may be added.
