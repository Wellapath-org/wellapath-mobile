# Launch command centre

An internal view of where the launch actually stands. Founder and engineering
only.

**Not part of the shipping application.** It is a generator script plus two
generated files. It imports nothing from `lib/`, nothing in `lib/` references
it, and it adds zero bytes to any build — all four properties are pinned by
tests in `test/scripts/launch_dashboard_test.dart`.

```
dart run scripts/launch_dashboard.dart              # offline, deterministic
dart run scripts/launch_dashboard.dart --probe      # also measures production /config
dart run scripts/launch_dashboard.dart --stdout-summary
open docs/launch/launch_dashboard.html
```

Outputs `docs/launch/LAUNCH_STATUS.json` and
`docs/launch/launch_dashboard.html`. The HTML is self-contained: no CDN, no
fonts, no scripts, works offline from disk.

---

## The one rule

**A metric that was not measured carries no value.** Where a subsystem is
switched off, was never instrumented, has not reported yet, or simply has not
been checked, the dashboard prints a word — *Disabled*, *Not instrumented*,
*Awaiting data*, *Not verified* — and never a number.

This exists because `0 crashes` and `crash reporting is off` are opposite
facts, and a launch decision made on the first while the second is true is a
decision made on evidence that does not exist. The rule is enforced in the
model's constructor, not left to the renderer: a `Metric` in a non-reporting
state throws if given a value.

## How to read a panel label

Each panel is labelled by its **weakest** fact.

| Label | Meaning |
|---|---|
| **Live** | A real-time measurement backs it. Nothing missing, nothing typed in. |
| **Derived** | Reproduces from committed repository sources alone. Trustworthy and automatic, but it reflects what is committed, not what is happening right now. |
| **Manual** | At least one fact was typed in by a person. Carries their name and the date, and expires after the freshness window. |
| **Incomplete** | At least one fact is one nobody has supplied. The panel is reporting an absence, not good news. |

## Panels and where each fact comes from

| Panel | Source | Kind |
|---|---|---|
| Build status | `pubspec.yaml`, `test/release/build_identity_test.dart` | Derived |
| | App Store Connect, Play Console | Manual |
| Internal tester availability | Both consoles | Manual — no repository source exists |
| Clinical review | `test/fixtures/known_findings.json`, `test/fixtures/case_bank_v1.json` | Derived |
| | `build/e8_case_bank/case_bank_results_v1.json` (gitignored; run the suite) | Live when present |
| | Clinical reviewer | Manual |
| Physical-device smoke tests | A person with a handset | Manual |
| Production API and configuration | `.env` | Derived |
| | `GET https://api.wellapath.org/config`, compared in canonical form against the baseline in `docs/release/RC_FROZEN_INPUTS.json` | Live, `--probe` only |
| Facility data | `docs/release/RC_FROZEN_INPUTS.json` | Derived — a frozen snapshot, not what /config serves today |
| Feedback and support | `lib/core/config/feature_flags.dart` | Derived |
| | `docs/store/SUPPORT_AND_PRIVACY_POLICY.md` | Manual |
| Sentry | `lib/core/crash/crash_config.dart` | Derived |
| Telemetry | `.env`, `lib/core/telemetry/telemetry_config.dart` | Derived |
| Outstanding actions | `docs/launch/launch_actions.json` plus checks the generator makes on the repository | Manual + Derived |

## The two files a human edits

**`manual_status.json`** — facts the repository cannot observe. Console state,
clinical sign-off, device tests. Every entry renders with a MANUAL badge, the
observer's name and the date.

- `state: "manual"` requires `value`, `observer` and `observed_at`.
- Any other state must **not** have a value.
- Use `"notVerified"` for something nobody has looked at. **Never guess a
  value.** An entry declaring `state: "live"` is rejected — a hand-entered
  fact may not claim to be a measurement.
- Entries older than `freshness_window_days` are automatically demoted to
  *Not verified*, with the original date and observer kept in the note. A
  stale sign-off must never read as a fresh one.

**`launch_actions.json`** — the register of what still stands between here and
launch. Severity, owner as a role, and a reference to the evidence. The
generator appends its own `DERIVED-` checks, recomputed every run.

Neither file may contain an email address, a phone number or any other contact
detail. A test enforces this.

## What this never contains

No patient data and no symptom data of any kind, by construction. The
generator reads build metadata, configuration flags, committed fixtures and
hand-entered operational notes — nothing else. A test scans the generated
output for clinical vocabulary and fails if any appears.

## Caveats worth knowing

- **It reflects the checkout it runs in.** Run it on the branch you are
  actually asking about. Run on `develop`, it reports `develop`'s build
  numbers, not those of an unmerged evidence branch.
- **`--probe` reaches the public production endpoint.** It sends no data and
  logs no response body; it reads `/config`, hashes it and discards it.
- **Without `--probe`, network-dependent facts read *Not verified*** rather
  than showing a remembered result, because a stale reachability check is
  indistinguishable from a current one.
