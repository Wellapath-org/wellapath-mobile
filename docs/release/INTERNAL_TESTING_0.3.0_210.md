# Internal Testing — 0.3.0 (build 210)

**Status:** prepared, **not uploaded, not submitted, external testing not
enabled.** No console access exists yet; everything here is ready to paste
once it does.

| | |
|---|---|
| Application identifier | `org.wellapath.app` (both platforms) |
| Version | 0.3.0 |
| Build | 210 (Android `versionCode`, iOS `CFBundleVersion`) |
| Backend | **staging only** (`wellapath-backend-staging.onrender.com`) |
| Telemetry | disabled (`TELEMETRY_ENABLED=false`; enable per-build via `--dart-define` only) |
| Crash reporting | disabled (no DSN bundled) |
| Facility coverage | Lagos, Kano and FCT only |
| Visible marker | "Internal testing — staging" on the home screen footer |

---

## Play internal track — release name

```
0.3.0 (210) — internal, staging
```

## Release notes (both stores, verbatim)

```
Internal testing — staging

This is an internal test build of WellaPath. It talks to the staging
backend only and may be reset at any time. Facility data covers Lagos,
Kano and FCT only. WellaPath helps you decide what to do next; it is not
a diagnosis and not a substitute for emergency services.
```

## Tester instructions

### What WellaPath is

WellaPath is a Clinical Decision Support System (CDSS). It helps you decide
how urgent your symptoms may be and where to find care. **It never gives a
diagnosis** and it does not replace a medical professional.

### Install

- **Android (Play internal track):** accept the internal-tester invitation
  link, then install/update WellaPath from the Play listing it opens.
- **iOS (TestFlight internal):** accept the TestFlight invitation, install
  the TestFlight app if prompted, then install WellaPath from TestFlight.

No account or login exists — the app opens straight into onboarding.

### Test path (happy path, ~3 minutes)

1. Launch the app. First launch against an idle staging backend can take
   **15–20 s** while the backend wakes — the splash shows "Connecting…".
   With no network at all you get an offline screen with "Try again".
2. Swipe through the 4 onboarding pages → home screen.
3. Confirm the footer shows **"Internal testing — staging"**.
4. Tap **Check your symptoms** → read the info sheet → start the assessment.
5. Pick a body area, select symptoms (e.g. Fever + Headache), answer the
   follow-up questions → results screen with possible causes and an urgency
   level.
6. Red-flag path: run a second assessment selecting **Seizures** — the app
   must interrupt immediately with the EMERGENCY screen and a call-112
   option. Do **not** call 112 while testing; do not tap the dial button on
   a device with a SIM you don't want to dial from.
7. Tap **Find a clinic** → allow location (or pick a state manually).
   Facility data exists for **Lagos, Kano and FCT only**; elsewhere you'll
   see the coverage disclosure.

### Known limitations in this build

- Staging backend only; cold launches can be slow (free-tier spin-down).
- Facilities: Lagos, Kano, FCT only. No distance cap — listed facilities
  can be far away; every card shows the distance.
- No account, no data sync; symptom answers never leave the device.
- English only.

### Demo credentials

None needed — the app has no login.

### Reporting problems

Report to the engineering lead through the internal tester channel with:
device model, OS version, build number (210), and the screen you were on.

---

## What this build must NOT be used for

- No external testers, no production users, no store review submission.
- CB_211 (issue #35) blocks external beta and production; it is unreachable
  through the UI and does not affect internal testing.

## Console steps that remain (require access — do not perform early)

See `docs/store/CONSOLE_RUNBOOK.md`.
